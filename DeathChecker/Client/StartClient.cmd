@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 or later is required. Install it and try again.
    echo.
    pause
    exit /b 1
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0ClientRuntime.ps1"
