import json
import ipaddress
import logging
import secrets
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode, urlsplit

import requests
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.middleware.base import BaseHTTPMiddleware

from config import Settings
from database import Database

logger = logging.getLogger("echelon")

MAX_SCREENSHOT_BYTES = 5 * 1024 * 1024


class SimpleAuth(BaseModel):
    discord_id: str = Field(min_length=1, max_length=64)


class RateLimitMiddleware(BaseHTTPMiddleware):
    LIMITS = {
        "/auth/simple": (10, 60),
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


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    database = Database(settings.database_path)
    app = FastAPI(title="Echelon Death Monitor", docs_url=None, redoc_url=None)
    app.add_middleware(RateLimitMiddleware)
    app.state.settings = settings
    app.state.database = database

    def get_authenticated_user(request: Request) -> str:
        authorization = request.headers.get("Authorization", "")
        scheme, separator, api_key = authorization.partition(" ")
        if not separator or scheme.lower() != "bearer" or not api_key.strip():
            raise HTTPException(status_code=401, detail="Invalid or expired API key")
        discord_id = database.validate_api_key(api_key.strip())
        if discord_id is None:
            raise HTTPException(status_code=401, detail="Invalid or expired API key")
        return discord_id

    @app.post("/auth/simple")
    async def simple_auth(auth: SimpleAuth):
        discord_id = auth.discord_id.strip()
        if not discord_id:
            raise HTTPException(status_code=400, detail="Discord ID cannot be blank")

        if not database.is_authorised(discord_id):
            raise HTTPException(status_code=403, detail="Discord ID is not authorised")

        api_key = database.issue_api_key(discord_id)
        if api_key is None:
            raise HTTPException(status_code=403, detail="Could not issue API key")

        return {"api_key": api_key, "discord_id": discord_id}

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
        victim: str = Form(..., max_length=128),
        killer: str = Form(..., max_length=128),
        death_time: str = Form(..., max_length=64),
        screenshot: UploadFile = File(...),
        discord_id: str = Depends(get_authenticated_user),
    ):
        if not victim.strip() or not killer.strip() or not death_time.strip():
            raise HTTPException(status_code=422, detail="Report fields cannot be blank")
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

        # Post to Discord webhook if configured
        if settings.discord_webhook_url:
            try:
                webhook_data = {
                    "content": f"**Death Report**\nVictim: {victim.strip()}\nKiller: {killer.strip()}\nTime: {death_time.strip()}",
                }
                files = {"file": ("death_screenshot.png", image, "image/png")}
                response = requests.post(
                    settings.discord_webhook_url,
                    data=webhook_data,
                    files=files,
                    timeout=10,
                )
                response.raise_for_status()
                logger.info("Webhook posted successfully: %s", response.status_code)
            except Exception as e:
                logger.error("Webhook post failed: %s", e)
                # Don't fail the report if webhook fails; server still accepted it

        return {"status": "submitted"}

    return app


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(create_app, host="127.0.0.1", port=8000, factory=True)
