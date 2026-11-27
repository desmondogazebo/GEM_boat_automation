$ErrorActionPreference = "Stop"

$helperDirectory = $PSScriptRoot
$outputPath = Join-Path $helperDirectory "DailyShipHelper.exe"
$workDirectory = Join-Path $env:TEMP ("DailyShipHelperBuild-" + [Guid]::NewGuid().ToString("N"))
$bundleDirectory = Join-Path $workDirectory "bundle"
$bundlePath = Join-Path $workDirectory "daily-ship-helper.zip"
$manifestPath = Join-Path $helperDirectory "DailyShipHelperLauncher.manifest"
$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "The .NET Framework C# compiler was not found."
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "The administrator elevation manifest was not found."
}

New-Item -ItemType Directory -Path $bundleDirectory -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $helperDirectory "GEM_Helper.py") -Destination $bundleDirectory
    Copy-Item -LiteralPath (Join-Path $helperDirectory "GameOCR.ps1") -Destination $bundleDirectory
    Compress-Archive -Path (Join-Path $bundleDirectory "*") -DestinationPath $bundlePath -CompressionLevel Optimal

    $compilerArguments = @(
        "/nologo",
        "/target:exe",
        "/platform:anycpu",
        "/optimize+",
        "/out:$outputPath",
        "/win32manifest:$manifestPath",
        "/reference:System.IO.Compression.dll",
        "/resource:$bundlePath,DailyShipHelper.Bundle.zip",
        (Join-Path $helperDirectory "DailyShipHelperLauncher.cs")
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The Daily Ship Helper executable build failed with exit code $LASTEXITCODE."
    }

    Write-Host "Built $outputPath"
} finally {
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force
    }
}
