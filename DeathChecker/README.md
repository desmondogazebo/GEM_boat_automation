# GEM Death Checker

This standalone module monitors the Granado Espada M game window, checks it with built-in Windows OCR, and sends a detected death report and screenshot to a FastAPI server that forwards it to a Discord webhook.

## Requirements

- Windows 10 or later
- Python 3.11 or later for the server
- Windows OCR with the English (`en-US`) recognizer available
- PowerShell 7 or later for the client

## Run locally

1. In `DeathChecker\Server`, copy `.env.example` to `.env` and set `DISCORD_WEBHOOK_URL` if notifications are wanted.
2. Build and launch the server executable:

   ```powershell
   .\BuildServerExe.ps1
   .\EchelonDeathMonitorServer.exe
   ```

   On first launch, the EXE creates `.venv` beside itself and installs the server requirements there before starting the API. Python 3.11+ and internet access to install packages are required for initial setup. Packages and pip cache are kept out of the system Python and AppData. Stop the server with Ctrl+C after setup, then authorize your Discord ID and launch it again:

   ```powershell
   .\.venv\Scripts\python.exe .\manage_users.py add YOUR_DISCORD_ID
   .\EchelonDeathMonitorServer.exe
   ```

   The EXE embeds the Python server source and requirements; `.env`, `.env.example`, `.venv`, and `echelon.db` remain beside it. It will not redirect configuration or the database to AppData or another directory. If `.env` is missing, the error points to the adjacent `.env.example`. If `~\.cloudflared\config.yml` exists, it starts the configured Cloudflare Tunnel and waits for it to connect; `cloudflared.exe` must be installed separately and available on `PATH` or under `%ProgramFiles(x86)%\cloudflared`. Without that config, it runs local-only. Press Ctrl+C once to stop the API and tunnel together.
3. Keep the server window open. It shows timestamped request logs and a live table of heartbeat clients: Discord ID, IP, status, and last API call with HTTP result. The table is in-memory only, starts empty, and is repopulated by successful heartbeats; rows expire after 20 minutes or when the server exits. Close the window with Enter after stopping or when startup fails.
4. From `DeathChecker\Client`, build and launch the client once:

   ```powershell
   Set-Location ..\Client
   .\BuildClientExe.ps1
   .\dist\DeathCheckerClient.exe
   ```

   On first launch, it creates `config.json` beside the executable and exits. Set `discordId` and `monitorIntervalMinutes` in that file; those are the only persisted client settings. The Discord ID is mandatory. The client does not read a config from AppData or use a previously saved ID.
5. With Granado Espada M running, launch `.\dist\DeathCheckerClient.exe` again. The executable requests administrator permission through Windows UAC so it can capture the game window. Press `P` to pause/resume monitoring or `Q` to quit. The client removes its temporary screenshot after each check.

Server URL, game process names, heartbeat interval, marker, and field labels are defined in `ClientRuntime.ps1`. Older config files are migrated to the two-setting format at startup. The client refreshes the game window dimensions on every heartbeat and reads them again when capturing, so resizing is supported. The default server URL is `https://deathcheck.desmond-zheng.com`; for local testing, change the code-defined `$serverUrl` in `ClientRuntime.ps1`. On startup, the client authenticates the ID with the server database before monitoring. An unauthorized ID or other authentication failure is displayed, then the client closes after five seconds. When the death screen does not show a victim name, the configured ID is used as the report's victim.

The client captures the full game window and uses the Windows OCR engine through built-in Windows PowerShell 5.1; no separate OCR application is required. It checks for the English (`en-US`) recognizer and reports a clear error if that Windows OCR language feature is unavailable. The death marker `Resurrect at Monument` is defined in code. When detected, the client sends the report even if OCR misses fields; unreadable fields are sent empty. Verify capture and OCR against a real death screen before relying on notifications. The client only attempts a game-window capture and does not fall back to desktop capture.

## Server executable

`BuildServerExe.ps1` produces a single-file console launcher using the Windows .NET Framework C# compiler. The launcher extracts the embedded server source beside itself, creates `.venv` if needed, installs and verifies requirements in that environment, then starts the server with its venv interpreter. It requires a standard Python 3.11+ installation with `venv` and `pip`; no server packages need to be installed globally. Package installation disables pip's user configuration and cache, and the launcher ignores Python path overrides so packages stay isolated in `.venv`. The Cloudflare Tunnel binary and tunnel configuration remain external prerequisites when remote access is enabled.

## Client executable

The compressed self-extracting `DeathCheckerClient.exe` contains the PowerShell client and its modules. Its Windows manifest requests administrator privileges, so launching it prompts for elevation. It extracts runtime files under `%LOCALAPPDATA%\EchelonDeathMonitor\ClientApp`, but creates and reads `config.json` beside the executable. If the config is absent, it writes the two-setting default and exits so it can be edited before the next launch. It removes the obsolete AppData config and Discord-ID files from earlier versions; DPAPI-protected API keys are retained. The executable requires PowerShell 7 or later and the built-in Windows OCR `en-US` recognizer; it does not require Tesseract. The executable is a launcher, not code obfuscation.

To build it locally from PowerShell 7, run `.\BuildClientExe.ps1` in `DeathChecker\Client`. The build needs the Windows .NET Framework C# compiler and writes the elevation-enabled executable to `dist\DeathCheckerClient.exe`. Launch that executable directly; no command wrapper is needed.

## Security and data handling

Before monitoring, the client sends the configured Discord ID to `/auth/simple`; the server checks it against its authorized-user database and issues an API key only for an authorized ID. The client stores that key encrypted with Windows DPAPI in a per-ID file under `%LOCALAPPDATA%\EchelonDeathMonitor`. This flow does not verify ownership of the Discord account; anyone who knows an authorized ID can request an API key. The server binds to loopback. The default client URL uses `deathcheck.desmond-zheng.com`, but DNS alone does not make the server reachable; a correctly configured HTTPS reverse proxy or tunnel on the server device is required before remote use.

The server stores authorized IDs and hashed API keys in its local SQLite database. It does not persist death reports; it forwards report text and the screenshot to the configured Discord webhook and returns an error if delivery is unavailable. Keep `Server/.env` private. Local configuration and database files are excluded by this module's `.gitignore`.

The death screen's `MM/DD HH:MM` time is interpreted in the server machine's local timezone and assigned the nearest matching year, then sent as a Discord full-date timestamp (`<t:...:F>`). Discord renders that timestamp in each viewer's local timezone.

After a successful webhook delivery, the client stores a hash of the current death report under `%LOCALAPPDATA%\EchelonDeathMonitor`. It skips the same death screen on later checks and clears the state after it observes a non-death screen, allowing a later death to be reported.
