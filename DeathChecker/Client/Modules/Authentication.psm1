function Get-ClientDataDirectory {
    $directory = Join-Path $env:LOCALAPPDATA "EchelonDeathMonitor"
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    return $directory
}

function Assert-DiscordId {
    param([Parameter(Mandatory)][string]$DiscordId)

    if ($DiscordId -notmatch '^\d{17,20}$') {
        throw "Discord ID must be a 17- to 20-digit numeric ID."
    }
}

function Get-StoredDiscordId {
    $path = Join-Path (Get-ClientDataDirectory) "discord-id.txt"
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    return (Get-Content -LiteralPath $path -Raw).Trim()
}

function Save-StoredDiscordId {
    param([Parameter(Mandatory)][string]$DiscordId)

    Assert-DiscordId -DiscordId $DiscordId
    $path = Join-Path (Get-ClientDataDirectory) "discord-id.txt"
    Set-Content -LiteralPath $path -Value $DiscordId -NoNewline -Encoding ASCII
}

function Get-KeyFilePath {
    param([Parameter(Mandatory)][string]$DiscordId)

    Assert-DiscordId -DiscordId $DiscordId
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $identityHash = [BitConverter]::ToString(
            $sha256.ComputeHash([Text.Encoding]::ASCII.GetBytes($DiscordId))
        ).Replace("-", "")
    } finally {
        $sha256.Dispose()
    }
    return (Join-Path (Get-ClientDataDirectory) "api-key-$identityHash.dat")
}

function Get-StoredApiKey {
    param([Parameter(Mandatory)][string]$DiscordId)

    $path = Get-KeyFilePath -DiscordId $DiscordId
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    try {
        $secureKey = Get-Content -LiteralPath $path -Raw | ConvertTo-SecureString
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    } catch {
        Remove-Item -LiteralPath $path -Force
        Write-Warning "Stored API key could not be decrypted and was discarded."
        return $null
    }
}

function Save-StoredApiKey {
    param(
        [Parameter(Mandatory)][string]$DiscordId,
        [Parameter(Mandatory)][string]$ApiKey
    )

    $secureKey = ConvertTo-SecureString $ApiKey -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString $secureKey
    Set-Content -LiteralPath (Get-KeyFilePath -DiscordId $DiscordId) -Value $encrypted -NoNewline
}

function Remove-StoredApiKey {
    param([Parameter(Mandatory)][string]$DiscordId)

    $path = Get-KeyFilePath -DiscordId $DiscordId
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Invoke-SimpleAuthentication {
    param([Parameter(Mandatory)][string]$ServerUrl, [Parameter(Mandatory)][string]$DiscordId)

    try {
        $response = Invoke-RestMethod `
            -Uri "$($ServerUrl.TrimEnd('/'))/auth/simple" `
            -Method Post `
            -ContentType "application/json" `
            -Body (@{ discord_id = $DiscordId } | ConvertTo-Json) `
            -TimeoutSec 15

        if (-not $response.api_key -or $response.discord_id -ne $DiscordId) {
            throw "The server returned an invalid authentication result."
        }

        return @{
            ApiKey = $response.api_key
            DiscordId = $response.discord_id
        }
    } catch {
        throw "Authentication failed: $_"
    }
}

Export-ModuleMember -Function Get-StoredDiscordId, Save-StoredDiscordId, Get-StoredApiKey, Save-StoredApiKey, Remove-StoredApiKey, Invoke-SimpleAuthentication
