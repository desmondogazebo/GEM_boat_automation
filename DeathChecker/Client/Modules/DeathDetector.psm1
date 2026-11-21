function Test-DeathScreen {
    param(
        [Parameter(Mandatory)][string]$OcrText,
        [Parameter(Mandatory)][string[]]$Keywords
    )

    foreach ($keyword in $Keywords) {
        if ($keyword -and $OcrText.IndexOf(
            $keyword, [StringComparison]::OrdinalIgnoreCase
        ) -ge 0) {
            return $true
        }
    }
    return $false
}

function Get-DeathFingerprint {
    param([Parameter(Mandatory)]$Report)

    $value = "$($Report.Victim)|$($Report.Killer)|$($Report.DeathTime)"
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String(
            $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))
        )
    } finally {
        $sha256.Dispose()
    }
}

function Get-StoredDeathFingerprint {
    $path = Join-Path $env:LOCALAPPDATA "EchelonDeathMonitor\last-death-state.dat"
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    return (Get-Content -LiteralPath $path -Raw).Trim()
}

function Save-DeathFingerprint {
    param([Parameter(Mandatory)][string]$Fingerprint)

    $directory = Join-Path $env:LOCALAPPDATA "EchelonDeathMonitor"
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $path = Join-Path $directory "last-death-state.dat"
    Set-Content -LiteralPath $path -Value $Fingerprint -NoNewline -Encoding ASCII
}

function Clear-DeathFingerprint {
    $path = Join-Path $env:LOCALAPPDATA "EchelonDeathMonitor\last-death-state.dat"
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

Export-ModuleMember -Function Test-DeathScreen, Get-DeathFingerprint, Get-StoredDeathFingerprint, Save-DeathFingerprint, Clear-DeathFingerprint
