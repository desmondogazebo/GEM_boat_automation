import hashlib
import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from config import Settings
from database import Database
from main import create_app


DISCORD_ID = "123456789012345678"
UNAUTHORIZED_ID = "999999999999999999"
PNG = b"\x89PNG\r\n\x1a\nexample"


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


def test_simple_auth_issues_key_for_authorized_user(tmp_path):
    client, database_path = make_client(tmp_path)

    response = client.post(
        "/auth/simple",
        json={"discord_id": DISCORD_ID},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["api_key"]
    assert body["discord_id"] == DISCORD_ID

    with sqlite3.connect(database_path) as connection:
        stored_hash, last_seen = connection.execute(
            "SELECT api_key_hash, last_seen FROM authorised_users WHERE discord_id = ?",
            (DISCORD_ID,),
        ).fetchone()

    assert stored_hash == hashlib.sha256(body["api_key"].encode()).hexdigest()
    assert stored_hash != body["api_key"]
    assert last_seen


def test_simple_auth_rejects_unauthorized_user(tmp_path):
    client, _ = make_client(tmp_path)

    response = client.post(
        "/auth/simple",
        json={"discord_id": UNAUTHORIZED_ID},
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Discord ID is not authorised"


def test_simple_auth_rejects_blank_discord_id(tmp_path):
    client, _ = make_client(tmp_path)

    response = client.post(
        "/auth/simple",
        json={"discord_id": ""},
    )

    assert response.status_code == 422


def test_simple_auth_rejects_whitespace_only_discord_id(tmp_path):
    client, _ = make_client(tmp_path)

    response = client.post(
        "/auth/simple",
        json={"discord_id": "   "},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Discord ID cannot be blank"


def test_heartbeat_uses_returned_api_key(tmp_path):
    client, _ = make_client(tmp_path)

    auth_response = client.post(
        "/auth/simple",
        json={"discord_id": DISCORD_ID},
    )

    assert auth_response.status_code == 200
    api_key = auth_response.json()["api_key"]

    heartbeat_response = client.post(
        "/deathcheck",
        headers={"Authorization": f"Bearer {api_key}"},
    )

    assert heartbeat_response.status_code == 200
    assert heartbeat_response.json()["status"] == "ok"


def test_deathreport_requires_valid_api_key(tmp_path):
    client, _ = make_client(tmp_path)

    response = client.post(
        "/deathreport",
        data={
            "victim": "TestVictim",
            "killer": "TestKiller",
            "death_time": "12:34:56",
        },
        files={"screenshot": ("death.png", PNG, "image/png")},
        headers={"Authorization": "Bearer invalid-key"},
    )

    assert response.status_code == 401


def test_deathreport_accepts_valid_data(tmp_path):
    client, _ = make_client(tmp_path)

    auth_response = client.post(
        "/auth/simple",
        json={"discord_id": DISCORD_ID},
    )

    api_key = auth_response.json()["api_key"]

    report_response = client.post(
        "/deathreport",
        data={
            "victim": "TestVictim",
            "killer": "TestKiller",
            "death_time": "12:34:56",
        },
        files={"screenshot": ("death.png", PNG, "image/png")},
        headers={"Authorization": f"Bearer {api_key}"},
    )

    assert report_response.status_code == 200
    assert report_response.json()["status"] == "submitted"


def test_rate_limiting_on_auth(tmp_path):
    client, _ = make_client(tmp_path)

    for i in range(10):
        response = client.post(
            "/auth/simple",
            json={"discord_id": DISCORD_ID},
        )
        assert response.status_code in (200, 403)

    response = client.post(
        "/auth/simple",
        json={"discord_id": DISCORD_ID},
    )

    assert response.status_code == 429
    assert response.json()["detail"] == "Too many requests"
