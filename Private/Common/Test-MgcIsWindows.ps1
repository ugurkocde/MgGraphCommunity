function Test-MgcIsWindows {
    <#
    .SYNOPSIS
        Cross-version replacement for the $IsWindows automatic variable.

    .DESCRIPTION
        $IsWindows / $IsLinux / $IsMacOS were introduced in PowerShell 6.0 and don't
        exist on Windows PowerShell 5.1. This helper returns $true on PS 5.1 (which
        only runs on Windows) and otherwise falls back to the modern automatic.
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    # PS 6+ — $IsWindows is defined
    return [bool]$IsWindows
}
