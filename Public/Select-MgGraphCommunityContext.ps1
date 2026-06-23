function Select-MgGraphCommunityContext {
    <#
    .SYNOPSIS
        Switches the active connection among the live MgGraphCommunity sessions.

    .DESCRIPTION
        Connect-MgGraphCommunity registers every connection in the session. When you
        are connected to more than one tenant or with more than one identity, use this
        to switch which one Invoke-MgGraphCommunityRequest (and the SDK handoff) uses,
        without re-authenticating.

        List the available connections with Get-MgGraphCommunityContext -ListAvailable.

    .PARAMETER TenantId
        Select the connection whose tenant (issued tid or the tenant you connected
        with) matches this value.

    .PARAMETER ClientId
        Select the connection with this application (client) id. Combine with
        -TenantId to disambiguate.

    .PARAMETER Index
        Select by 1-based position in Get-MgGraphCommunityContext -ListAvailable.

    .PARAMETER CacheKey
        Select by exact internal cache key (from the listing).

    .PARAMETER PassThru
        Return the newly active context object.

    .EXAMPLE
        Select-MgGraphCommunityContext -TenantId 'contoso.onmicrosoft.com'

    .EXAMPLE
        Get-MgGraphCommunityContext -ListAvailable
        Select-MgcContext -Index 2
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [Alias('Select-MgcContext')]
    param(
        [Parameter(ParameterSetName = 'Filter')]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Filter')]
        [string]$ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Index')]
        [int]$Index,

        [Parameter(Mandatory, ParameterSetName = 'CacheKey')]
        [string]$CacheKey,

        [switch]$PassThru
    )

    if ($null -eq $script:MgcSessions -or $script:MgcSessions.Count -eq 0) {
        throw "No active connections. Run Connect-MgGraphCommunity first."
    }

    $keys     = @($script:MgcSessions.Keys)
    $selected = $null

    switch ($PSCmdlet.ParameterSetName) {
        'CacheKey' {
            if (-not $script:MgcSessions.Contains($CacheKey)) {
                throw "No connection found with cache key '$CacheKey'. Use Get-MgGraphCommunityContext -ListAvailable."
            }
            $selected = $script:MgcSessions[$CacheKey]
        }
        'Index' {
            if ($Index -lt 1 -or $Index -gt $keys.Count) {
                throw "Index $Index is out of range (1..$($keys.Count)). Use Get-MgGraphCommunityContext -ListAvailable."
            }
            $selected = $script:MgcSessions[$keys[$Index - 1]]
        }
        'Filter' {
            if (-not $TenantId -and -not $ClientId) {
                throw "Specify -TenantId, -ClientId, -Index, or -CacheKey to select a connection."
            }
            $candidates = foreach ($key in $keys) {
                $s       = $script:MgcSessions[$key]
                $summary = Get-MgcSessionSummary -Session $s
                $tenantOk = (-not $TenantId) -or ($summary.TenantId -eq $TenantId) -or ($s.TenantSegment -eq $TenantId)
                $clientOk = (-not $ClientId) -or ($s.ClientId -eq $ClientId)
                if ($tenantOk -and $clientOk) { $s }
            }
            $candidates = @($candidates)
            if ($candidates.Count -eq 0) {
                throw "No connection matched the given criteria. Use Get-MgGraphCommunityContext -ListAvailable."
            }
            if ($candidates.Count -gt 1) {
                throw "$($candidates.Count) connections matched. Narrow it down with -ClientId / -CacheKey, or use -Index."
            }
            $selected = $candidates[0]
        }
    }

    $script:MgcActiveSession = $selected

    # Rebuild the user-visible context for the newly active connection.
    $context = Set-MgcConnectionContext `
        -Tokens      $selected.Tokens `
        -FlowType    $selected.FlowType `
        -ClientId    $selected.ClientId `
        -TenantId    $selected.TenantSegment `
        -Environment $selected.Authority.Environment `
        -Scopes      $selected.Scopes `
        -Persisted:  $selected.Persist

    # Re-point the opportunistic SDK handoff at the newly active token.
    $sdkHandoff = Send-MgcTokenToSdk -AccessToken $selected.Tokens.access_token
    $context | Add-Member -NotePropertyName SdkHandoff -NotePropertyValue $sdkHandoff -Force

    if ($PassThru) { return $context }
}
