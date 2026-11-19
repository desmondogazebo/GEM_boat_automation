import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


@dataclass(frozen=True)
class Settings:
    database_path: Path
    discord_webhook_url: str | None = None

    @classmethod
    def from_env(cls) -> "Settings":
        load_dotenv(os.environ.get("ENV_FILE", ".env"))

        return cls(
            database_path=Path(os.environ.get("DATABASE_PATH", "./echelon.db")),
            discord_webhook_url=os.environ.get("DISCORD_WEBHOOK_URL") or None,
        )
