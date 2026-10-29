
param(
    [int]$X = 750,
    [int]$Y = 700,
    [int]$Width = 430,
    [int]$Height = 40,
    [string]$OutputFile = "$env:TEMP\GameOCR.txt",
    [string]$TargetText = "",
    [int]$TargetIndex = 1,
    [switch]$ReturnAllMatches
)

$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Runtime.WindowsRuntime

    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime]

    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -eq $engine) {
        throw "No compatible Windows OCR language is installed."
    }

    $awaiter = [WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq "GetAwaiter" -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -like "IAsyncOperation*"
        } |
        Select-Object -First 1

    if ($null -eq $awaiter) {
        throw "Could not initialise Windows OCR async support."
    }

    function Wait-WinRT($Operation, [Type]$ResultType) {
        $awaiter.MakeGenericMethod($ResultType).
            Invoke($null, @($Operation)).GetResult()
    }

    function Get-CharacterSimilarity([string]$Left, [string]$Right) {
        $previous = [int[]]::new($Right.Length + 1)
        for ($column = 0; $column -le $Right.Length; $column++) {
            $previous[$column] = $column
        }

        for ($row = 1; $row -le $Left.Length; $row++) {
            $current = [int[]]::new($Right.Length + 1)
            $current[0] = $row

            for ($column = 1; $column -le $Right.Length; $column++) {
                $cost = if ($Left[$row - 1] -eq $Right[$column - 1]) { 0 } else { 1 }
                $current[$column] = [math]::Min(
                    [math]::Min($current[$column - 1] + 1, $previous[$column] + 1),
                    $previous[$column - 1] + $cost
                )
            }

            $previous = $current
        }

        $length = [math]::Max($Left.Length, $Right.Length)
        if ($length -eq 0) {
            return 1.0
        }

        return 1.0 - ($previous[$Right.Length] / $length)
    }

    $imagePath = "$env:TEMP\GameOCR.png"

    $bitmap = [System.Drawing.Bitmap]::new($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.CopyFromScreen(
            $X, $Y, 0, 0,
            [System.Drawing.Size]::new($Width, $Height)
        )
        $bitmap.Save($imagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    $file = Wait-WinRT `
        ([Windows.Storage.StorageFile]::GetFileFromPathAsync($imagePath)) `
        ([Windows.Storage.StorageFile])

    $stream = Wait-WinRT `
        ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) `
        ([Windows.Storage.Streams.IRandomAccessStream])

    $decoder = Wait-WinRT `
        ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) `
        ([Windows.Graphics.Imaging.BitmapDecoder])

    $softwareBitmap = Wait-WinRT `
        ($decoder.GetSoftwareBitmapAsync()) `
        ([Windows.Graphics.Imaging.SoftwareBitmap])

    $result = Wait-WinRT `
        ($engine.RecognizeAsync($softwareBitmap)) `
        ([Windows.Media.Ocr.OcrResult])

    if ([string]::IsNullOrWhiteSpace($TargetText)) {
        [System.IO.File]::WriteAllText(
            $OutputFile,
            $result.Text,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    else {
        $normalizedTarget = [regex]::Replace($TargetText, '[^\p{L}\p{N}]', '').ToLowerInvariant()
        $targetLength = $normalizedTarget.Length
        $ocrMatches = [System.Collections.Generic.List[object]]::new()
        $ocrNearMatches = [System.Collections.Generic.List[object]]::new()
        $maximumCandidateLength = $targetLength * 2

        foreach ($line in $result.Lines) {
            $words = @($line.Words)

            for ($start = 0; $start -lt $words.Count; $start++) {
                $candidate = ""

                for ($end = $start; $end -lt $words.Count; $end++) {
                    $candidate += [regex]::Replace(
                        $words[$end].Text,
                        '[^\p{L}\p{N}]',
                        ''
                    ).ToLowerInvariant()

                    if ($candidate.Length -gt $maximumCandidateLength) {
                        break
                    }

                    $isExactMatch = $candidate -eq $normalizedTarget
                    $similarity = Get-CharacterSimilarity $candidate $normalizedTarget
                    $isNearMatch = !$isExactMatch -and $similarity -gt 0.5

                    if ($isExactMatch -or $isNearMatch) {
                        $matchedWords = $words[$start..$end]
                        $left = ($matchedWords | ForEach-Object { $_.BoundingRect.X } | Measure-Object -Minimum).Minimum
                        $top = ($matchedWords | ForEach-Object { $_.BoundingRect.Y } | Measure-Object -Minimum).Minimum
                        $right = ($matchedWords | ForEach-Object {
                            $_.BoundingRect.X + $_.BoundingRect.Width
                        } | Measure-Object -Maximum).Maximum
                        $bottom = ($matchedWords | ForEach-Object {
                            $_.BoundingRect.Y + $_.BoundingRect.Height
                        } | Measure-Object -Maximum).Maximum

                        $bounds = [pscustomobject]@{
                            X = [math]::Floor($X + $left)
                            Y = [math]::Floor($Y + $top)
                            Width = [math]::Ceiling($right) - [math]::Floor($left)
                            Height = [math]::Ceiling($bottom) - [math]::Floor($top)
                        }
                        if ($isExactMatch) {
                            $ocrMatches.Add($bounds)
                        }
                        else {
                            $ocrNearMatches.Add([pscustomobject]@{
                                Bounds = $bounds
                                Similarity = $similarity
                            })
                        }
                        if ($isExactMatch) {
                            break
                        }
                    }
                }
            }
        }

        $sortedMatches = @($ocrMatches | Sort-Object `
            @{ Expression = { $_.Y }; Ascending = $true }, `
            @{ Expression = { $_.X }; Ascending = $true })

        if ($sortedMatches.Count -eq 0 -and $ocrNearMatches.Count -gt 0) {
            $bestSimilarity = ($ocrNearMatches | Measure-Object -Property Similarity -Maximum).Maximum
            $bestBoundsByPosition = @{}
            foreach ($nearMatch in $ocrNearMatches) {
                if ($nearMatch.Similarity -ne $bestSimilarity) {
                    continue
                }

                $bounds = $nearMatch.Bounds
                $key = "$($bounds.X)|$($bounds.Y)|$($bounds.Width)|$($bounds.Height)"
                $bestBoundsByPosition[$key] = $bounds
            }

            if ($bestBoundsByPosition.Count -eq 1) {
                $sortedMatches = @($bestBoundsByPosition.Values | Sort-Object `
                    @{ Expression = { $_.Y }; Ascending = $true }, `
                    @{ Expression = { $_.X }; Ascending = $true })
            }
        }

        if ($ReturnAllMatches -and $sortedMatches.Count -gt 0) {
            $output = ($sortedMatches | ForEach-Object {
                "$($_.X)|$($_.Y)|$($_.Width)|$($_.Height)"
            }) -join "`n"
            [System.IO.File]::WriteAllText(
                $OutputFile,
                $output,
                [System.Text.UTF8Encoding]::new($false)
            )
        }
        elseif ($TargetIndex -gt $sortedMatches.Count) {
            [System.IO.File]::WriteAllText(
                $OutputFile,
                "NOT_FOUND",
                [System.Text.UTF8Encoding]::new($false)
            )
        }
        else {
            $match = $sortedMatches[$TargetIndex - 1]
            [System.IO.File]::WriteAllText(
                $OutputFile,
                "$($match.X)|$($match.Y)|$($match.Width)|$($match.Height)",
                [System.Text.UTF8Encoding]::new($false)
            )
        }
    }

    $stream.Dispose()
}
catch {
    [System.IO.File]::WriteAllText(
        $OutputFile,
        "OCR_ERROR: $($_.Exception.Message)",
        [System.Text.UTF8Encoding]::new($false)
    )
    exit 1
}
