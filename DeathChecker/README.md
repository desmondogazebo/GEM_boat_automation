# GEM Death Checker

This standalone module monitors the Granado Espada M game window, checks a configured crop with Tesseract OCR, and sends a detected death report and screenshot to a Discord webhook through a local FastAPI server.

## Requirements

- Windows
- Python 3.11 or later
- PowerShell 7 or later for the client
- Tesseract OCR installed and available as `tesseract` on `PATH`

## Run locally

1. In `DeathChecker\Server`, copy `.env.example` to `.env` and set `DISCORD_WEBHOOK_URL` if notifications are wanted.
2. From that directory, authorize your Discord ID and start the server:

   ```powershell
   py -3 .\manage_users.py add YOUR_DISCORD_ID
   .\StartServer.ps1
   ```

   The server creates its virtual environment, installs its dependencies, and listens on `127.0.0.1:8000`.
3. In `DeathChecker\Client`, copy `config.example.json` to `config.json`. Set your Discord ID and calibrate `deathScreenCrop` as `[left, top, width, height]` fractions of the game window.
4. With Granado Espada M running, start the client from PowerShell 7:

   ```powershell
   .\Start.ps1
   ```

   Press `P` to pause/resume monitoring or `Q` to quit. The client removes its temporary screenshot after each check.

The sample crop is unset and OCR labels/keywords may need tuning for the actual game UI. Verify capture and OCR against a real death screen before relying on notifications. The client only attempts a game-window capture and does not fall back to desktop capture.

## Security and data handling

The current `/auth/simple` flow issues an API key to anyone who knows an authorized Discord ID; it does not verify ownership of that Discord account. The server binds to loopback and is intended for local testing only. Do not expose it to the internet or configure a remote client to use it.

The server stores authorized IDs and hashed API keys in its local SQLite database. It does not persist death reports; when configured, it forwards report text and the screenshot to the Discord webhook. Keep `Server/.env` private. Local configuration, database, and virtual-environment files are excluded by this module's `.gitignore`.

## Tests

From `DeathChecker\Server`, install development requirements in the server virtual environment and run:

```powershell
.\.venv\Scripts\python.exe -m pip install -r .\requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest .\tests
```
