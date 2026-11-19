import hashlib
import secrets
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterator


SESSION_TIMEOUT = timedelta(minutes=20)


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connection() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS authorised_users (
                    discord_id TEXT PRIMARY KEY,
                    api_key_hash TEXT,
                    last_seen DATETIME,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
                """
            )

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    @contextmanager
    def _connection(self) -> Iterator[sqlite3.Connection]:
        connection = self._connect()
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    @staticmethod
    def hash_api_key(api_key: str) -> str:
        return hashlib.sha256(api_key.encode("utf-8")).hexdigest()

    def is_authorised(self, discord_id: str) -> bool:
        with self._connection() as connection:
            row = connection.execute(
                "SELECT 1 FROM authorised_users WHERE discord_id = ?",
                (discord_id,),
            ).fetchone()
        return row is not None

    def issue_api_key(self, discord_id: str) -> str | None:
        api_key = secrets.token_urlsafe(32)
        now = datetime.now(timezone.utc).isoformat()
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                """
                UPDATE authorised_users
                SET api_key_hash = ?, last_seen = ?
                WHERE discord_id = ?
                """,
                (self.hash_api_key(api_key), now, discord_id),
            )
            if cursor.rowcount != 1:
                connection.rollback()
                return None
            connection.commit()
        return api_key

    def validate_api_key(
        self, api_key: str, *, touch_heartbeat: bool = False
    ) -> str | None:
        now = datetime.now(timezone.utc)
        key_hash = self.hash_api_key(api_key)
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                """
                SELECT discord_id, last_seen
                FROM authorised_users
                WHERE api_key_hash = ?
                """,
                (key_hash,),
            ).fetchone()
            if row is None:
                connection.rollback()
                return None

            try:
                last_seen = datetime.fromisoformat(row["last_seen"])
                if last_seen.tzinfo is None:
                    last_seen = last_seen.replace(tzinfo=timezone.utc)
            except (TypeError, ValueError):
                connection.rollback()
                return None

            if now - last_seen.astimezone(timezone.utc) >= SESSION_TIMEOUT:
                connection.rollback()
                return None

            if touch_heartbeat:
                connection.execute(
                    "UPDATE authorised_users SET last_seen = ? WHERE discord_id = ?",
                    (now.isoformat(), row["discord_id"]),
                )
            connection.commit()
            return str(row["discord_id"])

    def remove_user(self, discord_id: str) -> bool:
        with self._connection() as connection:
            cursor = connection.execute(
                "DELETE FROM authorised_users WHERE discord_id = ?",
                (discord_id,),
            )
        return cursor.rowcount == 1
