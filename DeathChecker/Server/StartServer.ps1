$ErrorActionPreference = "Stop"
$serverDirectory = $PSScriptRoot
Set-Location -LiteralPath $serverDirectory

if (-not (Test-Path -LiteralPath ".env")) {
    throw "Create Server\.env from Server\.env.example and fill in the Discord settings first."
}

$pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($pythonLauncher) {
    $pythonCommand = "py"
    $pythonArguments = @("-3")
} else {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw "Python 3.11 or later is required. Install Python and try again."
    }
    $pythonCommand = $python.Source
    $pythonArguments = @()
}

$versionOutput = & $pythonCommand @pythonArguments -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ($LASTEXITCODE -ne 0) {
    throw "Could not run Python. Install Python 3.11 or later."
}
$version = [version]$versionOutput
if ($version -lt [version]"3.11") {
    throw "Python 3.11 or later is required; found $version."
}

& $pythonCommand @pythonArguments -m pip install -r "requirements.txt"
if ($LASTEXITCODE -ne 0) {
    throw "Dependency installation failed."
}

Write-Host "Starting Echelon Death Monitor at http://127.0.0.1:8000"
Write-Host "Keep this window open. Press Ctrl+C to stop the server."
& $pythonCommand @pythonArguments -m uvicorn "main:create_app" --factory --host "127.0.0.1" --port 8000
