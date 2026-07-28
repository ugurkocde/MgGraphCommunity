function Get-MgcAppDataDir {
    <#
    .SYNOPSIS
        Returns the MgGraphCommunity per-user data directory (config, token cache).
    #>
    [CmdletBinding()]
    param()

    return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'MgGraphCommunity')
}
