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
   .\StartServer.cmd
   ```

   The batch launcher keeps its PowerShell window open for errors and runs the script with a process-scoped execution-policy bypass. The server installs its dependencies into the selected existing Python installation and listens on `127.0.0.1:8000`. Double-click `StartServer.cmd` to launch it from Explorer.
3. In `DeathChecker\Client`, copy `config.example.json` to `config.json` and calibrate `deathScreenCrop` as `[left, top, width, height]` fractions of the game window. On first start, the client asks for a Discord ID if none is already saved or configured. It stores the ID in `%LOCALAPPDATA%\EchelonDeathMonitor\discord-id.txt` and reuses it on later starts. When the death screen does not show a victim name, this ID is used as the report's victim.
4. With Granado Espada M running, start the client from PowerShell 7:

   ```powershell
   .\Start.ps1
   ```

   The client requests administrator permission through Windows UAC so it can capture a game running elevated. Press `P` to pause/resume monitoring or `Q` to quit. The client removes its temporary screenshot after each check.

The sample crop is unset and OCR labels/keywords may need tuning for the actual game UI. Verify capture and OCR against a real death screen before relying on notifications. The client only attempts a game-window capture and does not fall back to desktop capture.

For local testing with a saved image, set `testScreenshotPath` to its absolute path. This bypasses game-window capture, but still exercises OCR, death-screen parsing, authentication, and report delivery to the configured local server. Clear it to return to live game capture.

## Security and data handling

The current `/auth/simple` flow automatically uses the saved Discord ID and stores the resulting API key, encrypted with Windows DPAPI, in a per-ID file under `%LOCALAPPDATA%\EchelonDeathMonitor`. It does not verify ownership of that Discord account; this is not Discord OAuth. The server binds to loopback and is intended for local testing only. Do not expose it to the internet or configure a remote client to use it.

The server stores authorized IDs and hashed API keys in its local SQLite database. It does not persist death reports; it forwards report text and the screenshot to the configured Discord webhook and returns an error if delivery is unavailable. Keep `Server/.env` private. Local configuration and database files are excluded by this module's `.gitignore`.

The death screen's `MM/DD HH:MM` time is interpreted in the server machine's local timezone and assigned the nearest matching year, then sent as a Discord full-date timestamp (`<t:...:F>`). Discord renders that timestamp in each viewer's local timezone.

After a successful webhook delivery, the client stores a hash of the current death report under `%LOCALAPPDATA%\EchelonDeathMonitor`. It skips the same death screen on later checks and clears the state after it observes a non-death screen, allowing a later death to be reported.

## Tests

From `DeathChecker\Server`, install development requirements into the same Python installation and run:

```powershell
py -3 -m pip install -r .\requirements-dev.txt
py -3 -m pytest .\tests
```
