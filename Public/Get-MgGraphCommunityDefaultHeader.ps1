function Get-MgGraphCommunityDefaultHeader {
    <#
    .SYNOPSIS
        Returns the default HTTP headers currently set for the session.

    .PARAMETER Name
        Optional. If supplied, returns the value for that header (or $null if not set).
        Without -Name, returns all default headers as Name/Value objects.

    .EXAMPLE
        Get-MgGraphCommunityDefaultHeader

    .EXAMPLE
        Get-MgcHeader ConsistencyLevel
    #>
    [CmdletBinding()]
    [Alias('Get-MgcHeader')]
    param(
        [Parameter(Position = 0)][string]$Name
    )

    if (-not $script:MgcDefaultHeaders) { return $null }

    if ($Name) {
        if ($script:MgcDefaultHeaders.ContainsKey($Name)) { return $script:MgcDefaultHeaders[$Name] }
        return $null
    }

    return @($script:MgcDefaultHeaders.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ Name = $_.Key; Value = $_.Value }
    })
}
