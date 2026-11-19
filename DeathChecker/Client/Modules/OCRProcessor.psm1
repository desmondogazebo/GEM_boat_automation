function Get-GameScreenshotText {
    param(
        [Parameter(Mandatory)][string]$ScreenshotPath,
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$Language
    )

    $command = Get-Command $Executable -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Tesseract OCR was not found. Install it and add it to PATH."
    }
    $text = & $command.Source $ScreenshotPath "stdout" "-l" $Language "--psm" "6" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Tesseract OCR failed with exit code $LASTEXITCODE."
    }
    return ($text -join [Environment]::NewLine)
}

function ConvertFrom-DeathScreenText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]$FieldLabels
    )

    $patterns = @{
        Victim = "^\s*$([Regex]::Escape([string]$FieldLabels.victim))\s*:\s*(.+?)\s*$"
        Killer = "^\s*$([Regex]::Escape([string]$FieldLabels.killer))\s*:\s*(.+?)\s*$"
        DeathTime = "^\s*$([Regex]::Escape([string]$FieldLabels.deathTime))\s*:\s*(.+?)\s*$"
    }
    $values = @{}
    foreach ($line in ($Text -split "\r?\n")) {
        foreach ($field in $patterns.Keys) {
            if ($line -match $patterns[$field]) {
                $values[$field] = $Matches[1].Trim()
            }
        }
    }
    if (-not $values.Victim -or -not $values.Killer -or -not $values.DeathTime) {
        return $null
    }
    return [pscustomobject]@{
        Victim = $values.Victim
        Killer = $values.Killer
        DeathTime = $values.DeathTime
    }
}

Export-ModuleMember -Function Get-GameScreenshotText, ConvertFrom-DeathScreenText
