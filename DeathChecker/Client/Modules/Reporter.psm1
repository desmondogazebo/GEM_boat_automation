function Send-DeathReport {
    param(
        [Parameter(Mandatory)][string]$ServerUrl,
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][string]$ScreenshotPath
    )

    $response = Invoke-WebRequest `
        -Uri "$($ServerUrl.TrimEnd('/'))/deathreport" `
        -Method Post `
        -Headers @{ Authorization = "Bearer $ApiKey" } `
        -Form @{
            victim = $Report.Victim
            killer = $Report.Killer
            death_time = $Report.DeathTime
            screenshot = Get-Item -LiteralPath $ScreenshotPath
        } `
        -TimeoutSec 30 `
        -SkipHttpErrorCheck
    return [int]$response.StatusCode
}

Export-ModuleMember -Function Send-DeathReport
