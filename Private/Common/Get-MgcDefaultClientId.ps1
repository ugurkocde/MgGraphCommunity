function Get-MgcDefaultClientId {
    <#
    .SYNOPSIS
        Reads the user-persisted default ClientId, if one has been saved.

    .DESCRIPTION
        Set-MgGraphCommunityDefaultClientId (or New-MgGraphCommunityAppRegistration
        -SetAsDefault) writes config.json next to the token cache. When present,
        Connect-MgGraphCommunity uses this value instead of the built-in Microsoft
        client ID, unless -ClientId is passed explicitly.

    .OUTPUTS
        [string] The saved ClientId, or $null when none is configured.
    #>
    [CmdletBinding()]
    param()

    $configFile = Join-Path (Get-MgcAppDataDir) 'config.json'
    if (-not (Test-Path $configFile)) { return $null }

    try {
        $config = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.defaultClientId -and $config.defaultClientId -match '^[0-9a-fA-F-]{36}$') {
            return [string]$config.defaultClientId
        }
        return $null
    } catch {
        Write-Verbose "Config file unreadable, ignoring: $_"
        return $null
    }
}
