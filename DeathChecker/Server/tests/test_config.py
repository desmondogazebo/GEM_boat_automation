import pytest
from pathlib import Path

from config import Settings


def test_settings_loads_database_path(tmp_path, monkeypatch):
    monkeypatch.setenv("ENV_FILE", str(tmp_path / "missing.env"))
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "test.db"))
    settings = Settings.from_env()
    assert settings.database_path == tmp_path / "test.db"


def test_settings_defaults_to_local_echelon_db(tmp_path, monkeypatch):
    monkeypatch.setenv("ENV_FILE", str(tmp_path / "missing.env"))
    monkeypatch.delenv("DATABASE_PATH", raising=False)
    settings = Settings.from_env()
    assert settings.database_path == Path("./echelon.db")
