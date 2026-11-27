function Send-DeathMonitorHeartbeat {
    param(
        [Parameter(Mandatory)][string]$ServerUrl,
        [Parameter(Mandatory)][string]$ApiKey
    )

    try {
        $response = Invoke-WebRequest `
            -Uri "$($ServerUrl.TrimEnd('/'))/deathcheck" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $ApiKey" } `
            -TimeoutSec 15 `
            -SkipHttpErrorCheck
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Error = $null
        }
    } catch {
        return [pscustomobject]@{
            StatusCode = 0
            Error = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function Send-DeathMonitorHeartbeat
