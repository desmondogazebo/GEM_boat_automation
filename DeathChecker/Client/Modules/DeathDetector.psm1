function Test-DeathScreen {
    param(
        [Parameter(Mandatory)][string]$OcrText,
        [Parameter(Mandatory)][string[]]$Keywords
    )

    foreach ($keyword in $Keywords) {
        if ($keyword -and $OcrText.IndexOf(
            $keyword, [StringComparison]::OrdinalIgnoreCase
        ) -ge 0) {
            return $true
        }
    }
    return $false
}

Export-ModuleMember -Function Test-DeathScreen
