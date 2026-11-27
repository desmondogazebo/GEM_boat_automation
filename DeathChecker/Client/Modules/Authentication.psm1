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
        $response = Invoke-WebRequest `
            -Uri "$($ServerUrl.TrimEnd('/'))/auth/simple" `
            -Method Post `
            -ContentType "application/json" `
            -Body (@{ discord_id = $DiscordId } | ConvertTo-Json) `
            -TimeoutSec 15 `
            -SkipHttpErrorCheck
    } catch {
        throw "Authentication request failed: $($_.Exception.Message)"
    }

    $statusCode = [int]$response.StatusCode
    $body = $null
    if ($response.Content) {
        try {
            $body = ConvertFrom-Json -InputObject $response.Content -ErrorAction Stop
        } catch {
            if ($statusCode -eq 200) {
                throw "Authentication server returned invalid JSON."
            }
        }
    }

    if ($statusCode -eq 403) {
        $detail = if ($body) { [string]$body.detail } else { "" }
        if ($detail -eq "Discord ID is not authorised") {
            throw "Discord ID is not authorised in the server database."
        }
        if (-not $detail) {
            $detail = "the server denied the request"
        }
        throw "Authentication was denied by the server database: $detail"
    }
    if ($statusCode -ne 200) {
        $detail = if ($body) { [string]$body.detail } else { "" }
        if (-not $detail) {
            $detail = "HTTP $statusCode"
        }
        throw "Authentication failed ($detail)."
    }

    if (-not $body.api_key -or $body.discord_id -ne $DiscordId) {
        throw "The server returned an invalid authentication result."
    }

    return @{
        ApiKey = $body.api_key
        DiscordId = $body.discord_id
    }
}

Export-ModuleMember -Function Get-StoredApiKey, Save-StoredApiKey, Remove-StoredApiKey, Invoke-SimpleAuthentication
