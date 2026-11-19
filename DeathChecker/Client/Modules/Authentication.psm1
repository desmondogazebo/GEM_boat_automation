function Get-KeyFilePath {
    $directory = Join-Path $env:LOCALAPPDATA "EchelonDeathMonitor"
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = Get-Acl -LiteralPath $directory
    $acl.SetAccessRuleProtection($true, $false)
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $identity,
        [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [Security.AccessControl.InheritanceFlags]::ObjectInherit,
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow
    )
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $directory -AclObject $acl
    return (Join-Path $directory "api-key.dat")
}

function Get-StoredApiKey {
    $path = Get-KeyFilePath
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
    param([Parameter(Mandatory)][string]$ApiKey)

    $secureKey = ConvertTo-SecureString $ApiKey -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString $secureKey
    Set-Content -LiteralPath (Get-KeyFilePath) -Value $encrypted -NoNewline
}

function Remove-StoredApiKey {
    $path = Get-KeyFilePath
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

Export-ModuleMember -Function Get-StoredApiKey, Save-StoredApiKey, Remove-StoredApiKey, Invoke-SimpleAuthentication
