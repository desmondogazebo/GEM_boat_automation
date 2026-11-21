import hashlib
import requests
import sqlite3
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi.testclient import TestClient

from config import Settings
from database import Database
from main import _format_discord_timestamp, create_app


DISCORD_ID = "123456789012345678"
PNG = b"\x89PNG\r\n\x1a\nexample"


def test_game_time_formats_as_discord_timestamp_using_nearest_year():
    now = datetime(2026, 11, 21, 16, 7)
    expected_time = datetime(2026, 11, 21, 15, 48)
    expected_epoch = int(time.mktime(expected_time.timetuple()))

    assert _format_discord_timestamp("11/21 15:48", now=now) == (
        f"<t:{expected_epoch}:F>"
    )


def make_client(tmp_path: Path):
    database_path = tmp_path / "echelon.db"
    settings = Settings(database_path=database_path)
    database = Database(database_path)

    with sqlite3.connect(database_path) as connection:
        connection.execute(
            "INSERT INTO authorised_users (discord_id) VALUES (?)", (DISCORD_ID,)
        )

    app = create_app(settings)
    return TestClient(app), database_path


def get_authenticated_key(client: TestClient, discord_id: str = DISCORD_ID) -> str:
    response = client.post(
        "/auth/simple",
        json={"discord_id": discord_id},
    )
    assert response.status_code == 200
    return response.json()["api_key"]


def test_reauthentication_replaces_previous_api_key(tmp_path):
    client, database_path = make_client(tmp_path)
    old_key = get_authenticated_key(client)
    new_key = get_authenticated_key(client)

    old_key_response = client.post(
        "/deathcheck", headers={"Authorization": f"Bearer {old_key}"}
    )
    new_key_response = client.post(
        "/deathcheck", headers={"Authorization": f"Bearer {new_key}"}
    )
    assert old_key_response.status_code == 401
    assert new_key_response.status_code == 200


def test_heartbeat_refreshes_session_and_expired_key_is_rejected(tmp_path):
    client, database_path = make_client(tmp_path)
    api_key = get_authenticated_key(client)

    with sqlite3.connect(database_path) as connection:
        before_heartbeat = connection.execute(
            "SELECT last_seen FROM authorised_users WHERE discord_id = ?",
            (DISCORD_ID,),
        ).fetchone()[0]

    response = client.post(
        "/deathcheck", headers={"Authorization": f"Bearer {api_key}"}
    )
    assert response.status_code == 200

    with sqlite3.connect(database_path) as connection:
        last_seen = connection.execute(
            "SELECT last_seen FROM authorised_users WHERE discord_id = ?",
            (DISCORD_ID,),
        ).fetchone()[0]
        assert last_seen != before_heartbeat
        connection.execute(
            "UPDATE authorised_users SET last_seen = ? WHERE discord_id = ?",
            (
                (datetime.now(timezone.utc) - timedelta(minutes=21)).isoformat(),
                DISCORD_ID,
            ),
        )
    assert last_seen

    expired = client.post(
        "/deathcheck", headers={"Authorization": f"Bearer {api_key}"}
    )
    assert expired.status_code == 401


def test_report_rejects_when_webhook_is_not_configured(tmp_path):
    client, database_path = make_client(tmp_path)
    api_key = get_authenticated_key(client)

    headers = {"Authorization": f"Bearer {api_key}"}
    report = client.post(
        "/deathreport",
        headers=headers,
        data={"victim": "TestVictim", "killer": "TestKiller", "death_time": "19:30"},
        files={"screenshot": ("screen.png", PNG, "image/png")},
    )
    assert report.status_code == 503
    assert report.json()["detail"] == "Discord webhook is not configured"


def test_report_rejects_non_png_images(tmp_path):
    client, _ = make_client(tmp_path)
    api_key = get_authenticated_key(client)

    invalid_image = client.post(
        "/deathreport",
        headers={"Authorization": f"Bearer {api_key}"},
        data={"victim": "A", "killer": "B", "death_time": "19:30"},
        files={"screenshot": ("screen.png", b"not png", "image/png")},
    )
    assert invalid_image.status_code == 415


def test_report_requires_valid_key(tmp_path):
    client, _ = make_client(tmp_path)

    unauthorized = client.post(
        "/deathreport",
        data={"victim": "A", "killer": "B", "death_time": "19:30"},
        files={"screenshot": ("screen.png", PNG, "image/png")},
    )
    assert unauthorized.status_code == 401


def test_report_rejects_screenshot_over_five_megabytes(tmp_path):
    client, _ = make_client(tmp_path)
    api_key = get_authenticated_key(client)

    response = client.post(
        "/deathreport",
        headers={"Authorization": f"Bearer {api_key}"},
        data={"victim": "A", "killer": "B", "death_time": "19:30"},
        files={
            "screenshot": (
                "large.png",
                b"\x89PNG\r\n\x1a\n" + b"x" * (5 * 1024 * 1024),
                "image/png",
            )
        },
    )
    assert response.status_code == 413


def test_expired_key_is_rejected_for_death_report(tmp_path):
    client, database_path = make_client(tmp_path)
    api_key = get_authenticated_key(client)

    with sqlite3.connect(database_path) as connection:
        connection.execute(
            "UPDATE authorised_users SET last_seen = ? WHERE discord_id = ?",
            (
                (datetime.now(timezone.utc) - timedelta(minutes=21)).isoformat(),
                DISCORD_ID,
            ),
        )

    response = client.post(
        "/deathreport",
        headers={"Authorization": f"Bearer {api_key}"},
        data={"victim": "A", "killer": "B", "death_time": "19:30"},
        files={"screenshot": ("screen.png", PNG, "image/png")},
    )
    assert response.status_code == 401


def test_report_rejects_blank_fields(tmp_path):
    client, _ = make_client(tmp_path)
    api_key = get_authenticated_key(client)

    response = client.post(
        "/deathreport",
        headers={"Authorization": f"Bearer {api_key}"},
        data={"victim": "", "killer": "B", "death_time": "19:30"},
        files={"screenshot": ("screen.png", PNG, "image/png")},
    )
    assert response.status_code == 422


def test_report_uses_configured_webhook(tmp_path, monkeypatch):
    database_path = tmp_path / "echelon.db"
    Database(database_path)
    with sqlite3.connect(database_path) as connection:
        connection.execute(
            "INSERT INTO authorised_users (discord_id) VALUES (?)", (DISCORD_ID,)
        )

    webhook_url = "https://example.test/webhook"
    app = create_app(
        Settings(database_path=database_path, discord_webhook_url=webhook_url)
    )
    client = TestClient(app)
    api_key = get_authenticated_key(client)
    posted = {}

    class WebhookResponse:
        status_code = 204

        def raise_for_status(self):
            pass

    def fake_post(url, **kwargs):
        posted["url"] = url
        posted.update(kwargs)
        return WebhookResponse()

    monkeypatch.setattr("main.requests.post", fake_post)
    response = client.post(
        "/deathreport",
        headers={"Authorization": f"Bearer {api_key}"},
        data={
            "victim": "TestVictim",
            "killer": "TestKiller",
            "death_time": "11/21 15:48",
        },
        files={"screenshot": ("screen.png", PNG, "image/png")},
    )

    assert response.status_code == 200
    assert posted["url"] == webhook_url
    assert posted["files"]["file"][1] == PNG
    assert "Time: <t:" in posted["data"]["content"]


def test_report_returns_error_when_webhook_delivery_fails(tmp_path, monkeypatch):
    database_path = tmp_path / "echelon.db"
    Database(database_path)
    with sqlite3.connect(database_path) as connection:
        connection.execute(
            "INSERT INTO authorised_users (discord_id) VALUES (?)", (DISCORD_ID,)
        )

    app = create_app(
        Settings(
            database_path=database_path,
            discord_webhook_url="https://example.test/webhook",
        )
    )
    client = TestClient(app)
    api_key = get_authenticated_key(client)

    def fail_post(*args, **kwargs):
        raise requests.ConnectionError("simulated local webhook failure")

    monkeypatch.setattr("main.requests.post", fail_post)
    response = client.post(
        "/deathreport",
        headers={"Authorization": f"Bearer {api_key}"},
        data={"victim": "TestVictim", "killer": "TestKiller", "death_time": "19:30"},
        files={"screenshot": ("screen.png", PNG, "image/png")},
    )

    assert response.status_code == 502
    assert response.json()["detail"] == "Discord webhook delivery failed"
