# DeathChecker client

DeathChecker watches Granado Espada M for a death screen, reads its details with
Windows OCR, and sends a report to the configured DeathChecker service. The
service only accepts IDs that its operator has authorized.

## Requirements

- Windows 10 or later
- PowerShell 7 or later
- Granado Espada M
- The Windows OCR recognizer for English (`en-US`)
- Internet access to the DeathChecker service
- An authorized 17- to 20-digit Discord user ID

The service URL is built into the client. If you do not know whether your ID is
authorized, contact the person who operates your DeathChecker service. You do
not need to configure a Discord webhook, server, database, or Cloudflare
account.

## Build the client

From PowerShell 7, run:

```powershell
Set-Location .\Client
.\BuildClientExe.ps1
```

The executable is created at `Client\dist\DeathCheckerClient.exe`. The build
requires the Windows .NET Framework C# compiler.

## First launch

Launch `DeathCheckerClient.exe` once. It creates a `config.json` beside the
executable and exits. Edit that file with your authorized ID and desired
monitoring interval:

```json
{
  "monitorIntervalMinutes": 30,
  "discordId": "123456789012345678"
}
```

Then launch the executable again and approve the Windows administrator prompt.
Keep Granado Espada M running. Press `P` to pause or resume monitoring and `Q`
to quit.

The client captures the game window only. It checks for the `Resurrect at
Monument` death-screen marker; if OCR cannot read a report field, that field is
sent empty. Verify the game window and OCR language are working before relying
on notifications.

## Privacy and troubleshooting

- `config.json` is stored beside the executable and contains only the Discord
  ID and monitoring interval.
- The API key is protected with Windows DPAPI under your Windows profile.
- Temporary screenshots are removed after each check. A successful report is
  remembered so the same death screen is not reported repeatedly.
- If authentication fails, confirm the Discord ID is correct and ask the
  service operator to check that it is authorized.
- If OCR cannot read the game, confirm the English Windows OCR language
  feature is installed and the game is visible.
- If the service is unreachable, check your internet connection and try again
  later or contact the service operator.
