import json
import ipaddress
import logging
import re
import secrets
import time
from collections import OrderedDict, defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import RLock
from urllib.parse import urlencode, urlsplit

import requests
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.middleware.base import BaseHTTPMiddleware

from Modules.config import REPORT_RELAY_URL, Settings
from Modules.database import Database

logger = logging.getLogger("echelon")

MAX_SCREENSHOT_BYTES = 5 * 1024 * 1024
ACTIVE_CLIENT_WINDOW = timedelta(minutes=20)
MAX_TRACKED_CLIENTS = 100
RELAY_RECOVERY_DIRECTORY = "CloudflareWorker"


def _write_relay_recovery_instructions(server_directory: Path) -> Path:
    recovery_directory = server_directory / RELAY_RECOVERY_DIRECTORY
    readme_path = recovery_directory / "README.md"
    recovery_directory.mkdir(parents=True, exist_ok=True)
    if not readme_path.exists():
        readme_path.write_text(
            f"""# Cloudflare report relay recovery

The configured report relay endpoint (`{REPORT_RELAY_URL}`) could not be reached.
These steps apply only to the server owner:

1. In Cloudflare, open **Workers & Pages** and check the `gem-death-report-relay`
   Worker. Confirm it is deployed and its route matches
   `deathcheck.desmond-zheng.com/__discord-relay*`.
2. Check the Worker logs and confirm its `API_ORIGIN` variable is
   `https://deathcheck.desmond-zheng.com`.
3. In the Worker settings, confirm the `DISCORD_WEBHOOK_URL` secret is present.
   Never paste the webhook URL into this folder, a `.env` file, or source control.
4. If the Worker needs to be redeployed, use its deployed source or version
   history in the Cloudflare dashboard. This folder intentionally contains
   recovery instructions only, not a local copy of the deployed Worker.

After correcting the Worker or its route, retry a report from the client.
""",
            encoding="utf-8",
        )
    return readme_path


@dataclass(frozen=True)
class ClientActivity:
    discord_id: str
    client_ip: str
    last_api_called: str
    last_heartbeat_at: datetime | None


@dataclass(frozen=True)
class RecentClient:
    discord_id: str
    client_ip: str
    status: str
    last_api_called: str
    last_heartbeat_at: datetime


class ClientActivityTracker:
    def __init__(self) -> None:
        self._clients: OrderedDict[str, ClientActivity] = OrderedDict()
        self._lock = RLock()

    def record(
        self,
        *,
        discord_id: str,
        client_ip: str,
        api_call: str,
        status_code: int,
        heartbeat: bool = False,
        now: datetime | None = None,
    ) -> None:
        discord_id = discord_id.strip()
        if not discord_id:
            return
        current = now or datetime.now(timezone.utc)
        with self._lock:
            previous = self._clients.get(discord_id)
            heartbeat_at = previous.last_heartbeat_at if previous else None
            heartbeat_succeeded = heartbeat and 200 <= status_code < 400
            if previous is None and not heartbeat_succeeded:
                return
            if heartbeat_succeeded:
                heartbeat_at = current

            activity = ClientActivity(
                discord_id=discord_id,
                client_ip=client_ip,
                last_api_called=f"{api_call} [{status_code}]",
                last_heartbeat_at=heartbeat_at,
            )
            self._clients[discord_id] = activity
            self._clients.move_to_end(discord_id)
            self._remove_expired(current)
            while len(self._clients) > MAX_TRACKED_CLIENTS:
                self._clients.popitem(last=False)

    def recent_clients(self, now: datetime | None = None) -> list[RecentClient]:
        current = now or datetime.now(timezone.utc)
        with self._lock:
            self._remove_expired(current)
            activities = list(self._clients.values())

        clients = []
        for activity in activities:
            heartbeat_at = activity.last_heartbeat_at
            if heartbeat_at is None:
                continue
            clients.append(
                RecentClient(
                    discord_id=activity.discord_id,
                    client_ip=activity.client_ip,
                    status="Active",
                    last_api_called=activity.last_api_called,
                    last_heartbeat_at=heartbeat_at,
                )
            )
        return sorted(
            clients, key=lambda client: client.last_heartbeat_at, reverse=True
        )

    def _remove_expired(self, now: datetime) -> None:
        expired = [
            discord_id
            for discord_id, activity in self._clients.items()
            if activity.last_heartbeat_at is None
            or now - activity.last_heartbeat_at >= ACTIVE_CLIENT_WINDOW
        ]
        for discord_id in expired:
            del self._clients[discord_id]


def _format_discord_timestamp(value: str, *, now: datetime | None = None) -> str:
    match = re.fullmatch(r"\s*(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2})\s*", value)
    if not match:
        return value

    month, day, hour, minute = (int(part) for part in match.groups())
    current = now or datetime.now()
    current_epoch = time.mktime(current.timetuple())
    candidates = []
    for year in range(current.year - 2, current.year + 3):
        try:
            local_time = datetime(year, month, day, hour, minute)
        except ValueError:
            continue
        timestamp = int(time.mktime(local_time.timetuple()))
        candidates.append((abs(timestamp - current_epoch), timestamp))

    if not candidates:
        return value
    return f"<t:{min(candidates)[1]}:F>"


class SimpleAuth(BaseModel):
    discord_id: str = Field(min_length=1, max_length=64)


class RateLimitMiddleware(BaseHTTPMiddleware):
    LIMITS = {
        "/auth/simple": (10, 60),
        "/auth/validate": (30, 60),
        "/deathcheck": (30, 60),
        "/deathreport": (10, 60),
    }

    def __init__(self, app):
        super().__init__(app)
        self.requests = defaultdict(deque)
        self.last_cleanup = time.monotonic()

    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/deathreport":
            content_length = request.headers.get("content-length")
            if content_length:
                try:
                    if int(content_length) > MAX_SCREENSHOT_BYTES + 64 * 1024:
                        return JSONResponse(
                            status_code=413,
                            content={"detail": "Report upload exceeds the size limit"},
                        )
                except ValueError:
                    return JSONResponse(
                        status_code=400, content={"detail": "Invalid content length"}
                    )
        limit = self.LIMITS.get(request.url.path)
        if limit:
            maximum, window = limit
            client_ip = _client_ip(request)
            bucket = self.requests[(client_ip, request.url.path)]
            current = time.monotonic()
            if len(self.requests) > 512 and current - self.last_cleanup >= 60:
                for key, requests in list(self.requests.items()):
                    if not requests or current - requests[-1] >= 60:
                        del self.requests[key]
                self.last_cleanup = current
            while bucket and current - bucket[0] >= window:
                bucket.popleft()
            if len(bucket) >= maximum:
                return JSONResponse(
                    status_code=429, content={"detail": "Too many requests"}
                )
            bucket.append(current)
        return await call_next(request)


def _client_ip(request: Request) -> str:
    forwarded_ip = request.headers.get("CF-Connecting-IP")
    if forwarded_ip:
        try:
            return str(ipaddress.ip_address(forwarded_ip))
        except ValueError:
            pass
    return request.client.host if request.client else "unknown"


def create_app(
    settings: Settings | None = None,
    client_activity: ClientActivityTracker | None = None,
) -> FastAPI:
    settings = settings or Settings.for_directory(Path(__file__).resolve().parents[1])
    database = Database(settings.database_path)
    client_activity = client_activity or ClientActivityTracker()
    app = FastAPI(title="Echelon Death Monitor", docs_url=None, redoc_url=None)
    app.add_middleware(RateLimitMiddleware)
    app.state.settings = settings
    app.state.database = database
    app.state.client_activity = client_activity

    def get_authenticated_user(request: Request) -> str:
        authorization = request.headers.get("Authorization", "")
        scheme, separator, api_key = authorization.partition(" ")
        if not separator or scheme.lower() != "bearer" or not api_key.strip():
            raise HTTPException(status_code=401, detail="Invalid or expired API key")
        discord_id = database.validate_api_key(api_key.strip())
        if discord_id is None:
            raise HTTPException(status_code=401, detail="Invalid or expired API key")
        request.state.discord_id = discord_id
        return discord_id

    @app.post("/auth/simple")
    async def simple_auth(auth: SimpleAuth, request: Request):
        discord_id = auth.discord_id.strip()
        if not discord_id:
            raise HTTPException(status_code=400, detail="Discord ID cannot be blank")

        if not database.is_authorised(discord_id):
            raise HTTPException(status_code=403, detail="Discord ID is not authorised")

        api_key = database.issue_api_key(discord_id)
        if api_key is None:
            raise HTTPException(status_code=403, detail="Could not issue API key")

        request.state.discord_id = discord_id
        return {"api_key": api_key, "discord_id": discord_id}

    @app.post("/auth/validate")
    async def validate_api_key(
        _discord_id: str = Depends(get_authenticated_user),
    ):
        return {"status": "ok"}

    @app.middleware("http")
    async def log_request(request: Request, call_next):
        started = time.perf_counter()
        client_ip = _client_ip(request)
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        except Exception:
            logger.exception(
                "Request failed: client_ip=%s method=%s path=%s",
                client_ip,
                request.method,
                request.url.path,
            )
            raise
        finally:
            duration_ms = (time.perf_counter() - started) * 1000
            discord_id = getattr(request.state, "discord_id", None)
            if discord_id and request.url.path != "/auth/validate":
                client_activity.record(
                    discord_id=discord_id,
                    client_ip=client_ip,
                    api_call=f"{request.method} {request.url.path}",
                    status_code=status_code,
                    heartbeat=request.url.path == "/deathcheck",
                )
            logger.info(
                "client_ip=%s method=%s path=%s status=%d duration_ms=%.1f",
                client_ip,
                request.method,
                request.url.path,
                status_code,
                duration_ms,
            )

    @app.post("/deathcheck")
    async def deathcheck(
        request: Request,
        discord_id: str = Depends(get_authenticated_user),
    ):
        authorization = request.headers["Authorization"]
        api_key = authorization.partition(" ")[2].strip()
        if database.validate_api_key(api_key, touch_heartbeat=True) != discord_id:
            raise HTTPException(status_code=401, detail="Invalid or expired API key")
        return {"status": "ok"}

    @app.post("/deathreport")
    async def deathreport(
        request: Request,
        victim: str = Form("", max_length=128),
        killer: str = Form("", max_length=128),
        death_time: str = Form("", max_length=64),
        screenshot: UploadFile = File(...),
        discord_id: str = Depends(get_authenticated_user),
    ):
        try:
            image = await screenshot.read(MAX_SCREENSHOT_BYTES + 1)
        finally:
            await screenshot.close()
        if len(image) > MAX_SCREENSHOT_BYTES:
            raise HTTPException(status_code=413, detail="Screenshot exceeds 5 MB")
        if not image.startswith(b"\x89PNG\r\n\x1a\n"):
            raise HTTPException(status_code=415, detail="Screenshot must be a PNG")

        logger.info(
            "Death report received: victim=%s, killer=%s, discord_id=%s",
            victim.strip(),
            killer.strip(),
            discord_id,
        )

        try:
            authorization = request.headers["Authorization"]
            discord_time = _format_discord_timestamp(death_time)
            report_data = {
                "content": (
                    f"**Death Report**\nVictim: {victim.strip()}\n"
                    f"Killer: {killer.strip()}\nTime: {discord_time}"
                ),
            }
            files = {"file": ("death_screenshot.png", image, "image/png")}
            response = requests.post(
                REPORT_RELAY_URL,
                headers={"Authorization": authorization},
                data=report_data,
                files=files,
                timeout=15,
            )
            response.raise_for_status()
            logger.info("Death report delivered through Cloudflare relay.")
        except (requests.ConnectionError, requests.Timeout) as exc:
            logger.error("Cloudflare report relay is unreachable (%s)", type(exc).__name__)
            try:
                recovery_readme = _write_relay_recovery_instructions(
                    settings.database_path.parent
                )
            except OSError:
                logger.exception("Could not write Cloudflare relay recovery instructions.")
                detail = (
                    "Death report relay is unreachable; recovery instructions "
                    "could not be written"
                )
            else:
                logger.error("Relay recovery instructions: %s", recovery_readme)
                detail = (
                    "Death report relay is unreachable; see server-side "
                    "CloudflareWorker/README.md"
                )
            raise HTTPException(status_code=502, detail=detail) from exc
        except requests.RequestException as exc:
            logger.error("Cloudflare report relay failed (%s)", type(exc).__name__)
            raise HTTPException(
                status_code=502, detail="Discord webhook delivery failed"
            ) from exc

        return {"status": "submitted"}

    return app
