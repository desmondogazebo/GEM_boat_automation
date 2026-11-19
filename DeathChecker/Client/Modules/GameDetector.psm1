function Get-GameWindow {
    param([Parameter(Mandatory)][string[]]$ProcessNames)

    foreach ($name in $ProcessNames) {
        $process = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($name)) `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } |
            Select-Object -First 1
        if ($process) {
            return $process
        }
    }
    return $null
}

Export-ModuleMember -Function Get-GameWindow
