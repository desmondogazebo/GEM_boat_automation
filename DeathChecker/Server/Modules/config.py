from dataclasses import dataclass
from pathlib import Path

DATABASE_FILENAME = "SGMY.db"
REPORT_RELAY_URL = "https://deathcheck.desmond-zheng.com/__discord-relay"


@dataclass(frozen=True)
class Settings:
    database_path: Path

    @classmethod
    def for_directory(cls, directory: Path) -> "Settings":
        return cls(database_path=directory.resolve() / DATABASE_FILENAME)
