param([string]$ConfigPath)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    throw "Launch DeathCheckerClient.exe so it can provide the side-by-side config path."
}
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or later is required by the client runtime."
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $pwshPath = Join-Path $PSHOME "pwsh.exe"
    if (-not (Test-Path -LiteralPath $pwshPath)) {
        throw "Could not locate PowerShell 7 to request administrator permissions."
    }
    Write-Host "Requesting administrator permission to capture the game window."
    Start-Process `
        -FilePath $pwshPath `
        -Verb RunAs `
        -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            ('"{0}"' -f $PSCommandPath),
            "-ConfigPath",
            ('"{0}"' -f $ConfigPath)
        )
    exit
}

$configPath = $ConfigPath
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Client config was not found beside the executable: $configPath"
}

$loadedConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($loadedConfig -isnot [pscustomobject]) {
    throw "config.json must contain a JSON object."
}

$discordId = ([string]$loadedConfig.discordId).Trim()
$monitorIntervalMinutes = 30.0
if ($null -ne $loadedConfig.monitorIntervalMinutes) {
    try {
        $monitorIntervalMinutes = [double]$loadedConfig.monitorIntervalMinutes
    } catch {
        throw "monitorIntervalMinutes must be a positive number."
    }
}
if ([double]::IsNaN($monitorIntervalMinutes) -or
    [double]::IsInfinity($monitorIntervalMinutes) -or
    $monitorIntervalMinutes -le 0) {
    throw "monitorIntervalMinutes must be a positive number."
}
$allowedConfigProperties = @("monitorIntervalMinutes", "discordId")
$configNeedsSave = @(Compare-Object @($loadedConfig.PSObject.Properties.Name) $allowedConfigProperties).Count -gt 0
if ($null -eq $loadedConfig.monitorIntervalMinutes -or
    [double]$loadedConfig.monitorIntervalMinutes -ne $monitorIntervalMinutes -or
    ([string]$loadedConfig.discordId).Trim() -cne $discordId) {
    $configNeedsSave = $true
}
$config = [pscustomobject][ordered]@{
    monitorIntervalMinutes = $monitorIntervalMinutes
    discordId = $discordId
}
if ($configNeedsSave) {
    $config | ConvertTo-Json |
        Set-Content -LiteralPath $configPath -Encoding utf8
}
$serverUrl = "https://deathcheck.desmond-zheng.com"
$serverUri = [Uri]$serverUrl
if ($serverUri.Scheme -ne "https" -and
    -not ($serverUri.Scheme -eq "http" -and $serverUri.Host -eq "127.0.0.1")) {
    throw "The code-defined serverUrl must use HTTPS, or HTTP on 127.0.0.1 for local testing."
}

if ([string]::IsNullOrWhiteSpace($discordId)) {
    Write-Host "Discord ID is required in config.json. Add an authorized ID; the client will close in 5 seconds." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}
if ($discordId -notmatch '^\d{17,20}$') {
    Write-Host "Discord ID in config.json must be a 17- to 20-digit numeric ID. The client will close in 5 seconds." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

$moduleDirectory = Join-Path $PSScriptRoot "Modules"
Import-Module (Join-Path $moduleDirectory "Authentication.psm1") -Force
try {
    $authentication = Invoke-SimpleAuthentication -ServerUrl $serverUrl -DiscordId $discordId
    Save-StoredApiKey -DiscordId $discordId -ApiKey $authentication.ApiKey
} catch {
    Write-Host "Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "The client will close in 5 seconds."
    Start-Sleep -Seconds 5
    exit 1
}

Import-Module (Join-Path $moduleDirectory "Heartbeat.psm1") -Force
Import-Module (Join-Path $moduleDirectory "GameDetector.psm1") -Force
Import-Module (Join-Path $moduleDirectory "WindowCapture.psm1") -Force
Import-Module (Join-Path $moduleDirectory "DeathDetector.psm1") -Force
Import-Module (Join-Path $moduleDirectory "OCRProcessor.psm1") -Force
Import-Module (Join-Path $moduleDirectory "Reporter.psm1") -Force

$clientSettings = [pscustomobject]@{
    serverUrl = $serverUrl
    discordId = $discordId
    gameProcessNames = @("Granado Espada M", "GranadoEspadaM")
    deathScreenCrop = $null
    monitorIntervalMinutes = $config.monitorIntervalMinutes
    heartbeatIntervalMinutes = 15
    deathKeywords = @("Resurrect at Monument")
    fieldLabels = [pscustomobject]@{
        victim = "Victim"
        killer = "Killer"
        deathTime = "Death time"
    }
}

& (Join-Path $moduleDirectory "Monitor.ps1") -Config $clientSettings
