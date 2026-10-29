# Granado Espada M Automation

Windows automation scripts for assigning ships to trade routes in Granado Espada M. The AutoHotkey scripts use Windows OCR to find game UI text before clicking, and pause their input while the game window is not active.

## Scripts

| File | Purpose |
| --- | --- |
| `1batch.ahk` | Runs the first-batch route flow for ship slots 1 and 3. The ship 2 call is currently commented out. |
| `2batch.ahk` | Assigns ship slots 1 and 3 to Lupala (13 hours), and slot 2 to Unguja (15 hours). |
| `GameOCR.ps1` | Helper used by both AutoHotkey scripts to capture the screen and recognize UI text with Windows OCR. Keep it in the same folder as the `.ahk` scripts. |
| `1batch.exe`, `2batch.exe` | Precompiled launchers for the matching AutoHotkey scripts. |
| `GEMlaunch1.xml`, `GEMlaunch2ndShips.xml` | Windows Task Scheduler task templates for launching the first- and second-batch scripts. |

## Requirements

- Windows with a compatible Windows OCR language installed.
- [AutoHotkey v2](https://www.autohotkey.com/) to run the `.ahk` scripts.
- Granado Espada M running and displaying its UI on the primary monitor.

## Usage

1. Keep `GameOCR.ps1` beside the AutoHotkey script you want to run.
2. Start Granado Espada M and wait until it is ready.
3. Run `1batch.ahk` or `2batch.ahk` with AutoHotkey v2, or launch the matching precompiled `.exe`.

The script exits if the game process is not running. During automation, it waits for the game window to become active before continuing. Review the ship slots and destinations near the top of the selected script before running it.

These scripts send keyboard and mouse input to the game. Use them only when the game is in the expected state, and avoid interacting with the computer while a script is running.

## Scheduled tasks

The XML files are sanitized Task Scheduler templates. They omit the exporting account and use `%USERPROFILE%` for the script path. Before importing a task, confirm the script is in `%USERPROFILE%\Documents\My Games\Granado Espada M`, confirm AutoHotkey is installed at the path in the XML, and select your Windows account in Task Scheduler. The first-batch task runs at noon on the configured weekdays; the second-batch task runs daily at 9 PM. Adjust the trigger times or paths if needed.

## Repository contents

The task XML templates have been stripped of account names, account SIDs, local absolute paths, and export timestamps. The executables are included as convenience builds; use the `.ahk` sources if you want to review or change the automation.
