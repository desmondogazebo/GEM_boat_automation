# Granado Espada M Tools

This repository contains two independent Windows tools distributed together
in version-tagged releases. Their prerequisites differ:

## DeathChecker

Monitors the game for death-screen details and sends authorized reports to the
DeathChecker service. Contact me with your Discord user ID and wait for
authorization **before first use**. The client requires PowerShell 7 or later
available on `PATH`, English Windows OCR, and administrator permission, but
**does not require Python**. Setup and
troubleshooting are in [DeathChecker/README.md](./DeathChecker/README.md).

## DailyShipHelper

Automates the ship trade-route workflow using Windows OCR and game-window input.
It requires Python 3.11 or later on first run to create its adjacent `.venv`,
available through `py.exe` or `python.exe` on `PATH`, and asks for administrator
permission. Build and usage instructions are in
[DailyShipHelper/README.md](./DailyShipHelper/README.md).

Download both executables from the
[latest release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest).
Python is required for DailyShipHelper only, not for DeathCheckerClient.
