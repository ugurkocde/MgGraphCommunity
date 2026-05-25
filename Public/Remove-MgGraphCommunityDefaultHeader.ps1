function Remove-MgGraphCommunityDefaultHeader {
    <#
    .SYNOPSIS
        Removes a default HTTP header previously added with Add-MgGraphCommunityDefaultHeader.

    .PARAMETER Name
        Header name to remove.

    .EXAMPLE
        Remove-MgGraphCommunityDefaultHeader -Name 'ConsistencyLevel'

    .EXAMPLE
        Remove-MgcHeader Prefer
    #>
    [CmdletBinding()]
    [Alias('Remove-MgcHeader')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name
    )

    if ($script:MgcDefaultHeaders -and $script:MgcDefaultHeaders.ContainsKey($Name)) {
        $script:MgcDefaultHeaders.Remove($Name)
    }
}
