# DeathChecker client

DeathChecker watches Granado Espada M for a death screen, reads its details with
Windows OCR, and sends a report to the configured DeathChecker service. The
service only accepts IDs that its operator has authorized.

## Important: authorization before first use

Before using `DeathCheckerClient.exe`, contact me with your 17- to 20-digit
Discord user ID and wait for me to confirm that it has been authorized. The
client cannot self-register; first use will fail until I add your ID to the
service.

## Requirements

- Windows 10 or later
- PowerShell 7 or later installed and available on `PATH`
- Granado Espada M
- The Windows OCR recognizer for English (`en-US`)
- Internet access to the DeathChecker service
- A Discord user ID authorized by me before first use
- Administrator permission when prompted

Python is not required for DeathCheckerClient. The service URL is built into
the client. You do not need to configure a Discord webhook, server, database,
or Cloudflare account.

## Download

Download `DeathCheckerClient.exe` from the
[latest release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest).
The release also includes DailyShipHelper; their prerequisites are different.

## Build the client

To build the client yourself, run from PowerShell 7 in the `DeathChecker`
directory:

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

Only after I confirm your ID is authorized, launch the executable again and
approve the Windows administrator prompt. Keep Granado Espada M running. Press
`P` to pause or resume monitoring and `Q` to quit.

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
- If authentication fails, confirm the Discord ID is correct and contact me
  to verify that it has been authorized.
- If OCR cannot read the game, confirm the English Windows OCR language
  feature is installed and the game is visible.
- If the service is unreachable, check your internet connection and try again
  later or contact the service operator.
