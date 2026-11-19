param([Parameter(Mandatory)]$Config)

$ErrorActionPreference = "Stop"
$version = "1.0.0"
$serverUrl = ([string]$Config.serverUrl).TrimEnd("/")
$monitorInterval = [TimeSpan]::FromMinutes([double]$Config.monitorIntervalMinutes)
$heartbeatInterval = [TimeSpan]::FromMinutes([double]$Config.heartbeatIntervalMinutes)
$apiKey = Get-StoredApiKey
$discordId = "Not authenticated"
$paused = $false
$reportCount = 0
$lastCheck = "Never"
$lastHeartbeat = "Never"
$gameStatus = "Unknown"
$lastFingerprint = $null
$nextCheck = Get-Date
$nextHeartbeat = Get-Date
$heartbeatRetrySeconds = 30

function Write-Status {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host "Game: $gameStatus | Monitoring: $(if ($paused) { 'Paused' } else { 'Active' })"
    Write-Host "Last check: $lastCheck | Next check: $nextCheck"
    Write-Host "Last heartbeat: $lastHeartbeat | Next heartbeat: $nextHeartbeat"
    Write-Host "Discord ID: $discordId | Reports submitted: $reportCount"
}

function Invoke-ClientAuthentication {
    if (-not $Config.discordId -or -not ([string]$Config.discordId).Trim()) {
        throw "discordId is not configured in config.json"
    }
    $discordId = ([string]$Config.discordId).Trim()
    $result = Invoke-SimpleAuthentication -ServerUrl $serverUrl -DiscordId $discordId
    Save-StoredApiKey -ApiKey $result.ApiKey
    $script:apiKey = $result.ApiKey
    $script:discordId = $result.DiscordId
    Write-Status "Authentication succeeded with Discord ID $discordId."
}

function Invoke-Heartbeat {
    if (-not $apiKey) {
        $probe = Send-DeathMonitorHeartbeat `
            -ServerUrl $serverUrl `
            -ApiKey "connection-check-not-an-api-key"
        if ($probe.StatusCode -ne 401) {
            Write-Status "Server unavailable for authentication (HTTP $($probe.StatusCode)); retrying without opening Discord."
            $script:nextHeartbeat = (Get-Date).AddSeconds($heartbeatRetrySeconds)
            $script:heartbeatRetrySeconds = [Math]::Min(300, $heartbeatRetrySeconds * 2)
            return
        }
        try {
            Invoke-ClientAuthentication
        } catch {
            Write-Status "Authentication unavailable: $($_.Exception.Message)"
            $script:nextHeartbeat = (Get-Date).AddSeconds($heartbeatRetrySeconds)
            $script:heartbeatRetrySeconds = [Math]::Min(300, $heartbeatRetrySeconds * 2)
            return
        }
    }

    $result = Send-DeathMonitorHeartbeat -ServerUrl $serverUrl -ApiKey $apiKey
    if ($result.StatusCode -eq 200) {
        $script:lastHeartbeat = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $script:nextHeartbeat = (Get-Date).Add($heartbeatInterval)
        $script:heartbeatRetrySeconds = 30
        Write-Status "Heartbeat confirmed by server."
        return
    }
    if ($result.StatusCode -eq 401) {
        Remove-StoredApiKey
        $script:apiKey = $null
        $script:discordId = "Not authenticated"
        Write-Status "API key expired or revoked; signing in again."
        try {
            Invoke-ClientAuthentication
            $retry = Send-DeathMonitorHeartbeat -ServerUrl $serverUrl -ApiKey $apiKey
            if ($retry.StatusCode -eq 200) {
                $script:lastHeartbeat = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $script:nextHeartbeat = (Get-Date).Add($heartbeatInterval)
                $script:heartbeatRetrySeconds = 30
                Write-Status "Replacement API key confirmed."
                return
            }
            if ($retry.StatusCode -eq 401) {
                Remove-StoredApiKey
                $script:apiKey = $null
                $script:discordId = "Not authenticated"
            }
            Write-Status "Replacement key was not confirmed (HTTP $($retry.StatusCode))."
        } catch {
            Write-Status "Reauthentication failed: $($_.Exception.Message)"
        }
    } else {
        Write-Status "Heartbeat failed (HTTP $($result.StatusCode)): $($result.Error)"
    }
    $script:nextHeartbeat = (Get-Date).AddSeconds($heartbeatRetrySeconds)
    $script:heartbeatRetrySeconds = [Math]::Min(300, $heartbeatRetrySeconds * 2)
}

function Invoke-GameCheck {
    $script:lastCheck = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $script:nextCheck = (Get-Date).Add($monitorInterval)
    $process = Get-GameWindow -ProcessNames @($Config.gameProcessNames)
    if (-not $process) {
        $script:gameStatus = "Not running"
        Write-Status "GE M game window not found."
        return
    }
    $script:gameStatus = "Connected ($($process.ProcessName))"

    $screenshotPath = $null
    try {
        $screenshotPath = Save-GameWindowScreenshot `
            -WindowHandle $process.MainWindowHandle `
            -DeathScreenCrop @($Config.deathScreenCrop)
        Write-Status "Captured the configured GE M death-screen crop; checking it with OCR."
        $text = Get-GameScreenshotText `
            -ScreenshotPath $screenshotPath `
            -Executable ([string]$Config.ocrExecutable) `
            -Language ([string]$Config.ocrLanguage)
        if (-not (Test-DeathScreen -OcrText $text -Keywords @($Config.deathKeywords))) {
            Write-Status "No configured death-screen marker detected."
            return
        }
        $report = ConvertFrom-DeathScreenText -Text $text -FieldLabels $Config.fieldLabels
        if (-not $report) {
            Write-Status "Death screen detected, but OCR fields were incomplete; no report sent."
            return
        }

        $fingerprint = "$($report.Victim)|$($report.Killer)|$($report.DeathTime)"
        if ($fingerprint -eq $lastFingerprint) {
            Write-Status "This death report was already submitted; skipping duplicate."
            return
        }
        Write-Status "Confirmed death detected; uploading screenshot and report."
        $statusCode = Send-DeathReport `
            -ServerUrl $serverUrl `
            -ApiKey $apiKey `
            -Report $report `
            -ScreenshotPath $screenshotPath
        if ($statusCode -eq 200) {
            $script:reportCount++
            $script:lastFingerprint = $fingerprint
            Write-Status "Death report and screenshot uploaded."
        } elseif ($statusCode -eq 401) {
            Write-Status "Report rejected because the API key expired; reauthentication is due."
            $script:nextHeartbeat = Get-Date
        } else {
            Write-Status "Death report delivery failed (HTTP $statusCode)."
        }
    } catch {
        Write-Status "Game check failed; no unverified report was sent: $($_.Exception.Message)"
    } finally {
        if ($screenshotPath -and (Test-Path -LiteralPath $screenshotPath)) {
            Remove-Item -LiteralPath $screenshotPath -Force
        }
    }
}

Write-Host "Echelon Death Monitor v$version"
Write-Host "P: pause/resume monitoring | Q: quit"
Write-Status "Client started."
while ($true) {
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true).Key
        if ($key -eq [ConsoleKey]::Q) {
            Write-Status "Client stopping; heartbeat will stop."
            break
        }
        if ($key -eq [ConsoleKey]::P) {
            $paused = -not $paused
            if (-not $paused) {
                $nextCheck = Get-Date
            }
            Write-Status "Monitoring $(if ($paused) { 'paused' } else { 'resumed' })."
        }
    }

    $now = Get-Date
    if ($now -ge $nextHeartbeat) {
        Invoke-Heartbeat
    }
    if (-not $paused -and $now -ge $nextCheck) {
        Invoke-GameCheck
    }
    Start-Sleep -Seconds 1
}
