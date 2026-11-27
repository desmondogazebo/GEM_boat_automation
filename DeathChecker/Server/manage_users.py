import argparse
import sqlite3
from pathlib import Path

from Modules.config import DATABASE_FILENAME


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Add or remove authorised Discord IDs."
    )
    actions = parser.add_subparsers(dest="action", required=True)
    add = actions.add_parser("add", help="Authorise a Discord user ID")
    add.add_argument("discord_id")
    remove = actions.add_parser("remove", help="Revoke a Discord user ID")
    remove.add_argument("discord_id")
    args = parser.parse_args()

    server_directory = Path(__file__).resolve().parent
    database_path = server_directory / DATABASE_FILENAME

    with sqlite3.connect(database_path) as connection:
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
        if args.action == "add":
            connection.execute(
                "INSERT OR IGNORE INTO authorised_users (discord_id) VALUES (?)",
                (args.discord_id,),
            )
            print(f"Authorised Discord ID {args.discord_id}.")
        else:
            cursor = connection.execute(
                "DELETE FROM authorised_users WHERE discord_id = ?",
                (args.discord_id,),
            )
            if cursor.rowcount:
                print(f"Removed Discord ID {args.discord_id}.")
            else:
                print(f"Discord ID {args.discord_id} was not in the whitelist.")


if __name__ == "__main__":
    main()
