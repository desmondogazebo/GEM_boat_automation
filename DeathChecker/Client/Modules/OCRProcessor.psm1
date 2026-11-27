function Get-GameScreenshotText {
    param(
        [Parameter(Mandatory)][string]$ScreenshotPath
    )

    if (-not (Test-Path -LiteralPath $ScreenshotPath -PathType Leaf)) {
        throw "Screenshot was not found: $ScreenshotPath"
    }

    $windowsPowerShell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw "Windows PowerShell 5.1, required to access built-in Windows OCR, was not found."
    }

    Add-Type -AssemblyName System.Drawing
    $fullScreenshotPath = [IO.Path]::GetFullPath($ScreenshotPath)
    $image = [Drawing.Bitmap]::FromFile($fullScreenshotPath)
    $imagePaths = [Collections.Generic.List[string]]::new()
    $temporaryPaths = [Collections.Generic.List[string]]::new()
    $null = $imagePaths.Add($fullScreenshotPath)
    try {
        # OCR UI text in focused regions because the busy game background can
        # hide it when the entire window is processed at once.
        $regions = @(
            @{ Left = 0.33; Top = 0.09; Width = 0.36; Height = 0.14 },
            @{ Left = 0.29; Top = 0.64; Width = 0.40; Height = 0.09 },
            @{
                Left = 0.285
                Top = 0.82
                Width = 0.215
                Height = 0.085
                Scale = 5
            }
        )
        foreach ($region in $regions) {
            $x = [int][Math]::Round($image.Width * $region.Left)
            $y = [int][Math]::Round($image.Height * $region.Top)
            $width = [int][Math]::Round($image.Width * $region.Width)
            $height = [int][Math]::Round($image.Height * $region.Height)
            $scale = if ($region.Scale) { [int]$region.Scale } else { 3 }
            $crop = $image.Clone(
                [Drawing.Rectangle]::new($x, $y, $width, $height),
                [Drawing.Imaging.PixelFormat]::Format24bppRgb
            )
            $scaled = [Drawing.Bitmap]::new($width * $scale, $height * $scale)
            $graphics = [Drawing.Graphics]::FromImage($scaled)
            $path = Join-Path ([IO.Path]::GetTempPath()) (
                "echelon-ocr-{0}.png" -f [Guid]::NewGuid().ToString("N")
            )
            try {
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.DrawImage($crop, 0, 0, $scaled.Width, $scaled.Height)
                $null = $temporaryPaths.Add($path)
                $scaled.Save($path, [Drawing.Imaging.ImageFormat]::Png)
                $null = $imagePaths.Add($path)
            } finally {
                $graphics.Dispose()
                $scaled.Dispose()
                $crop.Dispose()
            }
        }

        $nativeOcrScript = @'
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Media.Ocr, ContentType=WindowsRuntime]

$script:asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq "AsTask" -and
        $_.IsGenericMethod -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } |
    Select-Object -First 1
if (-not $script:asTaskMethod) {
    throw "Windows Runtime async interop is unavailable."
}

function Wait-WindowsRuntimeOperation {
    param($Operation, [Type]$ResultType)

    $task = $script:asTaskMethod.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    try {
        $task.Wait()
    } catch {
        $details = ($task.Exception.Flatten().InnerExceptions |
            ForEach-Object { $_.Message }) -join " "
        if (-not $details) {
            $details = $_.Exception.Message
        }
        throw "Windows OCR operation failed: $details"
    }
    return $task.Result
}

$language = [Windows.Globalization.Language]::new("en-US")
if (-not [Windows.Media.Ocr.OcrEngine]::IsLanguageSupported($language)) {
    $availableLanguages = @(
        [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages |
            ForEach-Object { $_.LanguageTag }
    ) -join ", "
    if (-not $availableLanguages) {
        $availableLanguages = "none"
    }
    throw "Windows OCR language 'en-US' is not installed. Available OCR languages: $availableLanguages. Add the English OCR language feature in Windows Settings."
}

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
if (-not $engine) {
    throw "Windows could not create its built-in en-US OCR recognizer."
}

$imagePaths = ConvertFrom-Json -InputObject $env:ECHELON_DEATHCHECKER_OCR_IMAGE_PATHS -ErrorAction Stop
$texts = [Collections.Generic.List[string]]::new()
foreach ($path in $imagePaths) {
    $stream = $null
    $bitmap = $null
    try {
        $file = Wait-WindowsRuntimeOperation `
            ([Windows.Storage.StorageFile]::GetFileFromPathAsync([string]$path)) `
            ([Windows.Storage.StorageFile])
        $stream = Wait-WindowsRuntimeOperation `
            ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) `
            ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Wait-WindowsRuntimeOperation `
            ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) `
            ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Wait-WindowsRuntimeOperation `
            ($decoder.GetSoftwareBitmapAsync()) `
            ([Windows.Graphics.Imaging.SoftwareBitmap])
        $recognized = Wait-WindowsRuntimeOperation `
            ($engine.RecognizeAsync($bitmap)) `
            ([Windows.Media.Ocr.OcrResult])
        $recognizedLines = @($recognized.Lines | ForEach-Object { [string]$_.Text })
        $null = $texts.Add($recognizedLines -join [Environment]::NewLine)
    } catch {
        throw "Windows OCR failed for '$path': $($_.Exception.Message)"
    } finally {
        if ($bitmap) {
            $bitmap.Dispose()
        }
        if ($stream) {
            $stream.Dispose()
        }
    }
}

ConvertTo-Json -InputObject $texts.ToArray() -Compress
'@
        $encodedScript = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($nativeOcrScript)
        )
        $environmentVariable = "ECHELON_DEATHCHECKER_OCR_IMAGE_PATHS"
        $previousImagePaths = [Environment]::GetEnvironmentVariable($environmentVariable, "Process")
        $hadPreviousImagePaths = Test-Path -LiteralPath "Env:\$environmentVariable"
        try {
            [Environment]::SetEnvironmentVariable(
                $environmentVariable,
                (ConvertTo-Json -InputObject $imagePaths.ToArray() -Compress),
                "Process"
            )
            $nativeOutput = & $windowsPowerShell `
                -NoLogo `
                -NoProfile `
                -NonInteractive `
                -EncodedCommand $encodedScript 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $details = ($nativeOutput | ForEach-Object { [string]$_ }) -join " "
                throw "Windows OCR failed: $details"
            }

            $json = ($nativeOutput -join [Environment]::NewLine).Trim()
            try {
                $recognizedTexts = @(ConvertFrom-Json -InputObject $json -ErrorAction Stop)
            } catch {
                throw "Windows OCR returned invalid output: $($_.Exception.Message)"
            }
            if ($recognizedTexts.Count -ne $imagePaths.Count) {
                throw "Windows OCR returned $($recognizedTexts.Count) results for $($imagePaths.Count) images."
            }
            return ($recognizedTexts -join [Environment]::NewLine)
        } finally {
            if ($hadPreviousImagePaths) {
                [Environment]::SetEnvironmentVariable(
                    $environmentVariable,
                    $previousImagePaths,
                    "Process"
                )
            } else {
                Remove-Item -LiteralPath "Env:\$environmentVariable" -ErrorAction SilentlyContinue
            }
        }
    } finally {
        foreach ($path in $temporaryPaths) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force
            }
        }
        $image.Dispose()
    }
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
    $victim = if ($values.Victim) {
        $values.Victim
    } elseif ($DiscordId) {
        $DiscordId
    } else {
        ""
    }

    return [pscustomobject]@{
        Victim = $victim
        Killer = [string]$values.Killer
        DeathTime = [string]$values.DeathTime
    }
}

Export-ModuleMember -Function Get-GameScreenshotText, ConvertFrom-DeathScreenText
