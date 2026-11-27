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


def resolve_database_path(database_path: Path, base_directory: Path) -> Path:
    base = base_directory.resolve()
    resolved = database_path if database_path.is_absolute() else base / database_path
    resolved = resolved.resolve()
    try:
        resolved.relative_to(base)
    except ValueError as exc:
        raise ValueError(
            "DATABASE_PATH must resolve inside the executable directory."
        ) from exc
    if resolved == base or (resolved.exists() and resolved.is_dir()):
        raise ValueError("DATABASE_PATH must point to a database file.")
    return resolved
