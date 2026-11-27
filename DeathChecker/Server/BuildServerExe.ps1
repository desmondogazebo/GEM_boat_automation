$ErrorActionPreference = "Stop"

$serverDirectory = $PSScriptRoot
$outputPath = Join-Path $serverDirectory "EchelonDeathMonitorServer.exe"
$workDirectory = Join-Path $env:TEMP ("EchelonDeathMonitorBuild-" + [Guid]::NewGuid().ToString("N"))
$bundleDirectory = Join-Path $workDirectory "bundle"
$moduleDirectory = Join-Path $serverDirectory "Modules"
$bundlePath = Join-Path $workDirectory "server-runtime.zip"
$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "The .NET Framework C# compiler was not found."
}

$moduleRoot = (Resolve-Path -LiteralPath $moduleDirectory).Path
New-Item -ItemType Directory -Path (Join-Path $bundleDirectory "Modules") -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
try {
    Get-ChildItem -LiteralPath $moduleRoot -Filter "*.py" -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($moduleRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
        $destination = Join-Path (Join-Path $bundleDirectory "Modules") $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination
    }
    Copy-Item -LiteralPath (Join-Path $serverDirectory "requirements.txt") -Destination $bundleDirectory
    Compress-Archive -Path (Join-Path $bundleDirectory "*") -DestinationPath $bundlePath -CompressionLevel Optimal

    $compilerArguments = @(
        "/nologo",
        "/target:exe",
        "/platform:anycpu",
        "/optimize+",
        "/out:$outputPath",
        "/reference:System.IO.Compression.dll",
        "/resource:$bundlePath,EchelonDeathMonitorServer.Bundle.zip",
        (Join-Path $serverDirectory "ServerExeLauncher.cs")
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The server executable build failed with exit code $LASTEXITCODE."
    }

    Write-Host "Built $outputPath"
} finally {
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force
    }
}
