$ErrorActionPreference = "Stop"

$clientDirectory = $PSScriptRoot
$outputDirectory = Join-Path $clientDirectory "dist"
$workDirectory = Join-Path $env:TEMP ("DeathCheckerClientBuild-" + [Guid]::NewGuid().ToString("N"))
$bundleDirectory = Join-Path $workDirectory "bundle"
$bundlePath = Join-Path $workDirectory "client-bundle.zip"
$outputPath = Join-Path $outputDirectory "DeathCheckerClient.exe"
$manifestPath = Join-Path $clientDirectory "ClientExeLauncher.manifest"

$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "The .NET Framework C# compiler was not found."
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "The executable elevation manifest was not found."
}

New-Item -ItemType Directory -Path $bundleDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $clientDirectory "ClientRuntime.ps1") -Destination $bundleDirectory
    Copy-Item -LiteralPath (Join-Path $clientDirectory "Modules") -Destination $bundleDirectory -Recurse
    Compress-Archive -Path (Join-Path $bundleDirectory "*") -DestinationPath $bundlePath -CompressionLevel Optimal

    $compilerArguments = @(
        "/nologo",
        "/target:exe",
        "/platform:anycpu",
        "/optimize+",
        "/out:$outputPath",
        "/win32manifest:$manifestPath",
        "/reference:System.IO.Compression.dll",
        "/resource:$bundlePath,DeathCheckerClient.Bundle.zip",
        (Join-Path $clientDirectory "ClientExeLauncher.cs")
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The client executable build failed with exit code $LASTEXITCODE."
    }

    Write-Host "Built $outputPath"
} finally {
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force
    }
}
