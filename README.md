# Granado Espada M Automation

Windows automation scripts for assigning ships to trade routes in Granado Espada M. The AutoHotkey scripts use Windows OCR to find game UI text before clicking, and pause their input while the game window is not active.

## Scripts

| Repository file | Purpose |
| --- | --- |
| `1batch.ahk` | Runs the first-batch route flow for ship slots 1 and 3. The ship 2 call is currently commented out. |
| `2batch.ahk` | Assigns ship slots 1 and 3 to Lupala (13 hours), and slot 2 to Unguja (15 hours). |
| `GameOCR.ps1` | Helper used by both AutoHotkey scripts to capture the screen and recognize UI text with Windows OCR. Keep it in the same folder as the `.ahk` scripts. |
| `GEMlaunch1.xml`, `GEMlaunch2ndShips.xml` | Windows Task Scheduler task templates for launching the compiled `1batch.exe` and `2batch.exe`. |

## Requirements

- Windows with a compatible Windows OCR language installed.
- Granado Espada M running and displaying its UI on the primary monitor.
- For normal use, download the latest [release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest). AutoHotkey is not required to run the released `.exe` files.
- [AutoHotkey v2](https://www.autohotkey.com/) is only needed for development or to run the `.ahk` source scripts.

## Usage

1. Download `1batch.exe`, `2batch.exe`, and `GameOCR.ps1` from the [latest release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest).
2. Keep `GameOCR.ps1` beside the executable you want to run.
3. Start Granado Espada M and wait until it is ready, then launch `1batch.exe` or `2batch.exe`. AutoHotkey does not need to be installed.

The script exits if the game process is not running. During automation, it waits for the game window to become active before continuing. It also exits unless the game is idle (showing auto combat, waiting or moving). The ship slots and destinations are set near the top of each `.ahk` source script; edit and recompile them to change the routes.

These scripts send keyboard and mouse input to the game. Use them only when the game is in the expected state, and avoid interacting with the computer while a script is running.

## Scheduled tasks

The XML files are sanitized Task Scheduler templates that run the compiled executables. They omit the exporting account and use `%USERPROFILE%` for the executable path. Before importing a task, confirm `1batch.exe`, `2batch.exe` and `GameOCR.ps1` are in `%USERPROFILE%\Documents\My Games\Granado Espada M`, and select your Windows account in Task Scheduler. AutoHotkey is not needed. The first-batch task runs at noon every day except Tuesday, which is usually reserved for scheduled maintenance; the second-batch task runs daily at 9 PM. Adjust the trigger times or paths if needed.

## Releases

Download the executables and `GameOCR.ps1` from the [latest GitHub release](https://github.com/desmondogazebo/GEM_boat_automation/releases/latest). Releases are built from version tags and include both executables and the helper file. AutoHotkey is only needed to develop or run the `.ahk` source scripts.

## Repository contents

The task XML templates have been stripped of account names, account SIDs, local absolute paths, and export timestamps. Use the `.ahk` sources if you want to review or change the automation.
