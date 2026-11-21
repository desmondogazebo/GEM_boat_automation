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

    $results = [Collections.Generic.List[string]]::new()
    $text = & $command.Source $ScreenshotPath "stdout" "-l" $Language "--psm" "6" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Tesseract OCR failed with exit code $LASTEXITCODE."
    }
    $results.Add(($text -join [Environment]::NewLine))

    Add-Type -AssemblyName System.Drawing
    $image = [Drawing.Bitmap]::FromFile($ScreenshotPath)
    try {
        # OCR the title and timestamp bands separately; busy combat backgrounds
        # can hide these lines when the entire game window is processed at once.
        $regions = @(
            @{ Left = 0.33; Top = 0.09; Width = 0.36; Height = 0.14 },
            @{ Left = 0.29; Top = 0.64; Width = 0.40; Height = 0.09 }
        )
        foreach ($region in $regions) {
            $x = [int][Math]::Round($image.Width * $region.Left)
            $y = [int][Math]::Round($image.Height * $region.Top)
            $width = [int][Math]::Round($image.Width * $region.Width)
            $height = [int][Math]::Round($image.Height * $region.Height)
            $crop = $image.Clone(
                [Drawing.Rectangle]::new($x, $y, $width, $height),
                [Drawing.Imaging.PixelFormat]::Format24bppRgb
            )
            $scaled = [Drawing.Bitmap]::new($width * 3, $height * 3)
            $graphics = [Drawing.Graphics]::FromImage($scaled)
            $path = Join-Path ([IO.Path]::GetTempPath()) (
                "echelon-ocr-{0}.png" -f [Guid]::NewGuid().ToString("N")
            )
            try {
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.DrawImage($crop, 0, 0, $scaled.Width, $scaled.Height)
                $scaled.Save($path, [Drawing.Imaging.ImageFormat]::Png)
                $regionText = & $command.Source $path "stdout" "-l" $Language "--psm" "7" 2>$null
                if ($LASTEXITCODE -ne 0) {
                    throw "Tesseract OCR failed with exit code $LASTEXITCODE."
                }
                $results.Add(($regionText -join [Environment]::NewLine))
            } finally {
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Force
                }
                $graphics.Dispose()
                $scaled.Dispose()
                $crop.Dispose()
            }
        }
    } finally {
        $image.Dispose()
    }

    return ($results -join [Environment]::NewLine)
}

function ConvertFrom-DeathScreenText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]$FieldLabels,
        [string]$DiscordId = ""
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

        if (-not $values.Killer -and $line -match '^\s*Defeated\s+by\s+(.+?)\s*[.!]?\s*$') {
            $values.Killer = $Matches[1].Trim()
        }
        if (-not $values.DeathTime -and $line -match '^\s*Team\s+Annihilation\s+Time\s*:\s*(.+?)\s*$') {
            $values.DeathTime = $Matches[1].Trim()
        }
    }
    if (-not $values.Killer -or -not $values.DeathTime) {
        return $null
    }
    $victim = if ($values.Victim) {
        $values.Victim
    } elseif ($DiscordId) {
        $DiscordId
    } else {
        "Unknown"
    }

    return [pscustomobject]@{
        Victim = $victim
        Killer = $values.Killer
        DeathTime = $values.DeathTime
    }
}

Export-ModuleMember -Function Get-GameScreenshotText, ConvertFrom-DeathScreenText
