# Granado Espada M Automation

Windows automation scripts for assigning ships to trade routes in Granado Espada M. The AutoHotkey scripts use Windows OCR to find game UI text before clicking, and pause their input while the game window is not active.

## Scripts

| Repository file | Purpose |
| --- | --- |
| `GEM_Helper.ahk` | Generic automation script. Run it with a function name and arguments, e.g. `GEM_Helper.exe sendShips 1`. `sendShips 1` sends ships 1 and 3 on the first route; `sendShips 2` sends ships 1 and 3 to Lupala (13 hours) and ship 2 to Unguja (15 hours). |
| `GameOCR.ps1` | Helper used by the AutoHotkey script to capture the screen and recognize UI text with Windows OCR. Keep it in the same folder as the `.ahk` script. |
| `GEMlaunch1.xml`, `GEMlaunch2ndShips.xml` | Windows Task Scheduler task templates for launching the compiled `GEM_Helper.exe` (with `sendShips 1` and `sendShips 2`). |

## Requirements

- Windows with a compatible Windows OCR language installed.
- Granado Espada M running and displaying its UI on the primary monitor.
- For normal use, download the latest [release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest). AutoHotkey is not required to run the released `.exe` files.
- [AutoHotkey v2](https://www.autohotkey.com/) is only needed for development or to run the `.ahk` source scripts.

## Usage

1. Download `GEM_Helper.exe` and `GameOCR.ps1` from the [latest release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest).
2. Keep `GameOCR.ps1` beside the executable you want to run.
3. Start Granado Espada M and wait until it is ready, then launch `GEM_Helper.exe sendShips 1` or `GEM_Helper.exe sendShips 2` (or `AutoHotkey64.exe GEM_Helper.ahk sendShips 1` from source). AutoHotkey does not need to be installed.

The script exits if the game process is not running. During automation, it waits for the game window to become active before continuing. Before sending each ship it needs the game to be idle (showing auto combat, waiting or moving); if not, a tooltip at the mouse shows it is waiting, and the script exits after 5 minutes without the game becoming idle. The ship slots and destinations are set in `sendShips` in `GEM_Helper.ahk`; edit and recompile them to change the routes.

Debug mode is currently on by default: every OCR read saves an annotated screenshot to `%TEMP%\GameOCR_debug.png` (pass `--no-debug` to turn it off, e.g. `GEM_Helper.exe sendShips 1 --no-debug`). Red lines show what was found: thin boxes for every recognized word, dashed boxes with a similarity percentage for near-match candidates, thick boxes for exact matches, and crosshair lines with coordinates at the point that will be clicked. `GameOCR.ps1` also accepts `-DebugMode` and `-DebugImageFile` directly.

These scripts send keyboard and mouse input to the game. Use them only when the game is in the expected state, and avoid interacting with the computer while a script is running.

## Scheduled tasks

The XML files are sanitized Task Scheduler templates that run the compiled executable with `sendShips 1` or `sendShips 2` as the argument. They omit the exporting account and use `%USERPROFILE%` for the executable path. Before importing a task, confirm `GEM_Helper.exe` and `GameOCR.ps1` are in `%USERPROFILE%\Documents\My Games\Granado Espada M`, and select your Windows account in Task Scheduler. AutoHotkey is not needed. The first-batch task runs at noon every day except Tuesday, which is usually reserved for scheduled maintenance; the second-batch task runs daily at 9 PM. Adjust the trigger times or paths if needed.

## Releases

Download the executable and `GameOCR.ps1` from the [latest GitHub release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest). Releases are built from version tags and include the executable and the helper file. AutoHotkey is only needed to develop or run the `.ahk` source scripts.

## Repository contents

The task XML templates have been stripped of account names, account SIDs, local absolute paths, and export timestamps. Use the `.ahk` sources if you want to review or change the automation.
