# Daily Ship Helper

Daily Ship Helper automates the ship trade-route workflow in Granado Espada M. It uses Windows OCR to find game labels before clicking and pauses its input whenever the game is not the active window.

## Requirements

- Windows 10 or later
- Granado Espada M running with its UI on the primary monitor
- Python 3.11 or later for first-run creation of the adjacent `.venv`
- The Windows OCR language recognizer for the game's displayed language

The helper has no third-party Python packages. Its C# launcher creates `.venv` beside the executable on first use and runs the bundled Python script from that environment. OCR uses the built-in Windows PowerShell 5.1 and Windows OCR APIs.

## Build and run

For a prebuilt launcher, download `DailyShipHelper.exe` from the
[latest release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest).
To build it locally, run from PowerShell in this folder:

```powershell
.\BuildDailyShipHelper.ps1
.\DailyShipHelper.exe sendShips 1
```

The executable requests administrator permission through Windows UAC so it can send input to the game. Keep the game on the primary monitor and wait until it is ready before starting a batch. On first launch, the helper creates `.venv`; this can take a short time.

Commands:

- `DailyShipHelper.exe sendShips 1` sends ships 1 and 3 on the first available route.
- `DailyShipHelper.exe sendShips 2` sends ship 1 to Lupala, ship 2 to Unguja, and ship 3 to Lupala.

Debug OCR is enabled by default and writes an annotated screenshot to `%TEMP%\GameOCR_debug.png` after each OCR read. Add `--no-debug` to disable it:

```powershell
.\DailyShipHelper.exe sendShips 1 --no-debug
```

The helper waits up to five minutes for the game to be idle before assigning each ship. It waits for the game window to become active before sending input and does not count inactive time toward its short delays. Avoid using the mouse or keyboard while a batch is running.

## Route behavior and limitations

The default batch uses the first available route. The second batch scrolls the route list before choosing Lupala or Unguja. Trade confirmation is selected by finding the exact `Cancel` label and clicking 290 pixels to the right of its center. That offset assumes the existing dialog layout and may need adjustment for a different game UI scale or display resolution. The helper stops if the label is missing, ambiguous, or the click would fall outside the primary monitor.

## Source files

- `GEM_Helper.py` contains the automation logic.
- `GameOCR.ps1` captures the primary-monitor screen region and uses built-in Windows OCR.
- `DailyShipHelperLauncher.cs` provisions the adjacent `.venv`, extracts the bundled source, and starts Python.
- `DailyShipHelperLauncher.manifest` makes Windows request administrator approval.
- `BuildDailyShipHelper.ps1` builds the self-extracting launcher.
