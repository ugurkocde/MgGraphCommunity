function Add-MgGraphCommunityDefaultHeader {
    <#
    .SYNOPSIS
        Adds (or updates) a default HTTP header that is sent on every subsequent
        Invoke-MgGraphCommunityRequest call.

    .DESCRIPTION
        Useful for headers you want sticky for the whole session, e.g.:
            Add-MgGraphCommunityDefaultHeader -Name 'ConsistencyLevel' -Value 'eventual'

        Per-call -Headers on Invoke-MgGraphCommunityRequest take precedence over
        default headers when keys collide.

        Default headers are cleared by Disconnect-MgGraphCommunity.

    .PARAMETER Name
        Header name (case-insensitive).

    .PARAMETER Value
        Header value.

    .EXAMPLE
        Add-MgGraphCommunityDefaultHeader -Name ConsistencyLevel -Value eventual

    .EXAMPLE
        Add-MgcHeader Prefer 'odata.maxpagesize=100'
    #>
    [CmdletBinding()]
    [Alias('Add-MgcHeader')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory, Position = 1)][string]$Value
    )

    if (-not $script:MgcDefaultHeaders) {
        $script:MgcDefaultHeaders = @{}
    }
    $script:MgcDefaultHeaders[$Name] = $Value
}
