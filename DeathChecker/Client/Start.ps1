$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or later is required. Start this script from pwsh."
}
$configPath = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Copy config.example.json to config.json and set serverUrl and gameProcessNames."
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$serverUri = [Uri]$config.serverUrl
if ($serverUri.Scheme -ne "https" -and
    -not ($serverUri.Scheme -eq "http" -and $serverUri.Host -eq "127.0.0.1")) {
    throw "serverUrl must use HTTPS, or HTTP on 127.0.0.1 for local testing."
}
if (-not $config.gameProcessNames -or $config.gameProcessNames.Count -eq 0) {
    throw "Configure at least one GE M process name."
}

$moduleDirectory = Join-Path $PSScriptRoot "Modules"
Import-Module (Join-Path $moduleDirectory "Authentication.psm1") -Force
Import-Module (Join-Path $moduleDirectory "Heartbeat.psm1") -Force
Import-Module (Join-Path $moduleDirectory "GameDetector.psm1") -Force
Import-Module (Join-Path $moduleDirectory "WindowCapture.psm1") -Force
Import-Module (Join-Path $moduleDirectory "DeathDetector.psm1") -Force
Import-Module (Join-Path $moduleDirectory "OCRProcessor.psm1") -Force
Import-Module (Join-Path $moduleDirectory "Reporter.psm1") -Force

& (Join-Path $moduleDirectory "Monitor.ps1") -Config $config
