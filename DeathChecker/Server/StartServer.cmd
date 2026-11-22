@echo off
setlocal
cd /d "%~dp0"

if not exist ".env" (
    echo Create Server\.env from Server\.env.example and configure Discord settings first.
    goto failed
)

where py >nul 2>nul
if not errorlevel 1 goto use_launcher
where python >nul 2>nul
if errorlevel 1 goto missing_python
set "PYTHON=python"
goto check_python

:use_launcher
set "PYTHON=py -3"

:check_python
%PYTHON% -c "import sys; print('Using Python', sys.version.split()[0]); raise SystemExit(0 if sys.version_info >= (3, 11) else 1)"
if errorlevel 1 goto unsupported_python

%PYTHON% -m pip install -r "requirements.txt"
if errorlevel 1 goto dependency_error

echo Starting Echelon Death Monitor at http://127.0.0.1:8000
if not exist "%USERPROFILE%\.cloudflared\config.yml" goto local_only
set "CLOUDFLARED="
where cloudflared.exe >nul 2>nul
if not errorlevel 1 set "CLOUDFLARED=cloudflared.exe"
if defined CLOUDFLARED goto start_tunnel
if exist "%ProgramFiles(x86)%\cloudflared\cloudflared.exe" set "CLOUDFLARED=%ProgramFiles(x86)%\cloudflared\cloudflared.exe"
if not defined CLOUDFLARED goto missing_cloudflared

:start_tunnel
netstat -ano -p tcp | findstr /C:"127.0.0.1:8000" | findstr /C:"LISTENING" >nul
if not errorlevel 1 goto already_running
echo Starting Cloudflare Tunnel for https://deathcheck.desmond-zheng.com
start /b "" "%CLOUDFLARED%" tunnel --config "%USERPROFILE%\.cloudflared\config.yml" run deathchecker
goto run_server

:local_only
echo No Cloudflare Tunnel configuration found; the API will be available only locally.

:run_server
netstat -ano -p tcp | findstr /C:"127.0.0.1:8000" | findstr /C:"LISTENING" >nul
if not errorlevel 1 goto already_running
echo Keep this window open. Press Ctrl+C to stop the server.
%PYTHON% -m uvicorn "main:create_app" --factory --host "127.0.0.1" --port 8000
if errorlevel 1 goto server_error
echo Server stopped.
goto finish

:already_running
echo DeathChecker API is already listening on 127.0.0.1:8000. Reusing the existing server.
echo Keep its original server window open.
goto finish

:missing_python
echo Python 3.11 or later was not found. Install Python and try again.
goto failed

:unsupported_python
echo Python 3.11 or later is required.
goto failed

:dependency_error
echo Dependency installation failed.
goto failed

:missing_cloudflared
echo Cloudflare Tunnel is configured but cloudflared.exe was not found.
goto failed

:server_error
echo The server exited with an error.
goto failed

:failed
echo.
pause
exit /b 1

:finish
echo.
pause
exit /b 0
