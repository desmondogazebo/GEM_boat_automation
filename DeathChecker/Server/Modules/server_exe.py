import logging
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
from collections import deque
from pathlib import Path

import uvicorn
from rich.console import Console, Group
from rich.live import Live
from rich.logging import RichHandler
from rich.table import Table
from rich.text import Text

from Modules.config import Settings, resolve_database_path
from Modules.main import ClientActivityTracker, RecentClient, create_app


HOST = "127.0.0.1"
PORT = 8000
TUNNEL_CONNECT_TIMEOUT = 60


class ClientDashboard:
    def __init__(self, activity: ClientActivityTracker) -> None:
        self._activity = activity

    def render(self) -> Group:
        table = Table(title="Recent heartbeat clients", expand=True)
        table.add_column("Discord ID", no_wrap=True)
        table.add_column("IP", no_wrap=True)
        table.add_column("Status", no_wrap=True)
        table.add_column("Last API called", overflow="ellipsis")

        clients = self._activity.recent_clients()
        if clients:
            for client in clients:
                table.add_row(
                    client.discord_id,
                    client.client_ip,
                    self._status_text(client),
                    client.last_api_called,
                )
        else:
            table.add_row("-", "-", "Waiting", "No heartbeat clients yet")

        return Group(
            table,
            Text(
                "Only current in-memory heartbeat clients are shown; "
                "rows expire after 20 minutes and clear on exit.",
                style="dim",
            ),
        )

    @staticmethod
    def _status_text(client: RecentClient) -> Text:
        style = "green" if client.status == "Active" else "yellow"
        return Text(client.status, style=style)


class CloudflareTunnel:
    def __init__(self, console: Console) -> None:
        self._console = console
        self._process: subprocess.Popen[str] | None = None
        self._reader: threading.Thread | None = None
        self._connected = threading.Event()
        self._output: deque[str] = deque(maxlen=30)
        self._lock = threading.Lock()

    def start_if_configured(self) -> bool:
        profile = os.environ.get("USERPROFILE")
        config_path = (
            Path(profile) / ".cloudflared" / "config.yml" if profile else None
        )
        if config_path is None or not config_path.is_file():
            return False

        executable = self._find_cloudflared()
        if executable is None:
            raise RuntimeError(
                "Cloudflare Tunnel is configured, but cloudflared.exe was not found."
            )

        self._console.print(
            f"[{self._timestamp()}] Starting Cloudflare Tunnel..."
        )
        self._process = subprocess.Popen(
            [
                executable,
                "tunnel",
                "--config",
                str(config_path),
                "run",
                "deathchecker",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        self._reader = threading.Thread(target=self._read_output, daemon=True)
        self._reader.start()

        deadline = time.monotonic() + TUNNEL_CONNECT_TIMEOUT
        while time.monotonic() < deadline:
            if self._connected.wait(timeout=0.2):
                self._console.print(
                    f"[{self._timestamp()}] Cloudflare Tunnel connected: "
                    "https://deathcheck.desmond-zheng.com"
                )
                return True
            if self._process.poll() is not None:
                raise RuntimeError(self._failure_message("Cloudflare Tunnel exited"))

        raise RuntimeError(
            self._failure_message(
                f"Cloudflare Tunnel did not connect within "
                f"{TUNNEL_CONNECT_TIMEOUT} seconds"
            )
        )

    def stop(self) -> None:
        process = self._process
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        if self._reader is not None:
            self._reader.join(timeout=1)

    def _read_output(self) -> None:
        process = self._process
        if process is None or process.stdout is None:
            return
        for line in process.stdout:
            line = line.rstrip()
            with self._lock:
                self._output.append(line)
            if "Registered tunnel connection" in line:
                self._connected.set()

    def _failure_message(self, message: str) -> str:
        with self._lock:
            output = "\n".join(self._output)
        return f"{message}." + (f"\n{output}" if output else "")

    @staticmethod
    def _find_cloudflared() -> str | None:
        executable = shutil.which("cloudflared.exe") or shutil.which("cloudflared")
        if executable:
            return executable
        program_files = os.environ.get("ProgramFiles(x86)")
        if program_files:
            candidate = Path(program_files) / "cloudflared" / "cloudflared.exe"
            if candidate.is_file():
                return str(candidate)
        return None

    @staticmethod
    def _timestamp() -> str:
        return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def _base_directory() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


def _load_settings(base_directory: Path) -> Settings:
    base_directory = base_directory.resolve()
    env_file = base_directory / ".env"
    example_file = base_directory / ".env.example"
    if not env_file.is_file():
        if example_file.is_file():
            raise FileNotFoundError(
                f"Server configuration not found: {env_file}. "
                f"Copy {example_file} to {env_file} and configure it."
            )
        raise FileNotFoundError(f"Server configuration not found: {env_file}.")

    os.environ["ENV_FILE"] = str(env_file)
    os.environ.pop("DATABASE_PATH", None)
    loaded_settings = Settings.from_env()

    return Settings(
        database_path=resolve_database_path(
            loaded_settings.database_path, base_directory
        ),
        discord_webhook_url=loaded_settings.discord_webhook_url,
    )


def _configure_logging(console: Console) -> None:
    handler = RichHandler(
        console=console,
        show_time=True,
        log_time_format="[%Y-%m-%dT%H:%M:%S%z]",
        show_level=True,
        show_path=False,
        markup=False,
        rich_tracebacks=True,
    )
    logging.basicConfig(level=logging.INFO, handlers=[handler], force=True)
    for name in ("echelon", "uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.setLevel(logging.INFO)
        logger.propagate = True


def _is_server_running() -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as connection:
        connection.settimeout(0.25)
        return connection.connect_ex((HOST, PORT)) == 0


def _run_server() -> int:
    console = Console(highlight=False)
    base_directory = _base_directory()
    os.chdir(base_directory)
    settings = _load_settings(base_directory)

    if _is_server_running():
        console.print(
            f"[{CloudflareTunnel._timestamp()}] "
            f"Server is already listening on http://{HOST}:{PORT}."
        )
        return 0

    tunnel = CloudflareTunnel(console)
    try:
        tunnel_started = tunnel.start_if_configured()
        if not tunnel_started:
            console.print(
                f"[{CloudflareTunnel._timestamp()}] "
                "No Cloudflare Tunnel configuration found; API is local only."
            )

        console.clear()
        console.print(
            f"[{CloudflareTunnel._timestamp()}] "
            f"Starting Echelon Death Monitor API on http://{HOST}:{PORT}"
        )
        console.print("Press Ctrl+C once to stop the API and tunnel.")

        tracker = ClientActivityTracker()
        app = create_app(settings, client_activity=tracker)
        _configure_logging(console)
        server = uvicorn.Server(
            uvicorn.Config(
                app,
                host=HOST,
                port=PORT,
                access_log=False,
                log_config=None,
            )
        )
        dashboard = ClientDashboard(tracker)
        with Live(
            dashboard.render(),
            console=console,
            refresh_per_second=1,
            transient=False,
        ) as live:
            stop_refresh = threading.Event()

            def refresh_dashboard() -> None:
                while not stop_refresh.wait(1):
                    live.update(dashboard.render(), refresh=True)

            refresher = threading.Thread(target=refresh_dashboard, daemon=True)
            refresher.start()
            try:
                server.run()
            except KeyboardInterrupt:
                pass
            finally:
                stop_refresh.set()
                refresher.join(timeout=2)
            if not server.started:
                return 1
        return 0
    finally:
        tunnel.stop()


def main() -> int:
    exit_code = 0
    try:
        exit_code = _run_server()
    except Exception as exc:
        console = Console(highlight=False)
        console.print(
            f"[{CloudflareTunnel._timestamp()}] [red]Server startup failed:[/] {exc}"
        )
        exit_code = 1
    finally:
        if sys.stdin.isatty():
            try:
                input("\nPress Enter to close.")
            except EOFError:
                pass
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
