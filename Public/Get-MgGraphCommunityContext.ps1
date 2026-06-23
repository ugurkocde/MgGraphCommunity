function Get-MgGraphCommunityContext {
    <#
    .SYNOPSIS
        Returns the active MgGraphCommunity connection context (mirrors Get-MgContext).

    .DESCRIPTION
        With no parameters, returns the context of the currently active connection.
        With -ListAvailable, returns a summary of every live connection in this
        session (for switching with Select-MgGraphCommunityContext).

    .PARAMETER ListAvailable
        List all live connections instead of returning the active context. Each
        entry has IsActive, Account, TenantId, ClientId, Environment, FlowType,
        ExpiresOn, and CacheKey.

    .EXAMPLE
        Get-MgGraphCommunityContext

    .EXAMPLE
        Get-MgGraphCommunityContext -ListAvailable
    #>
    [CmdletBinding()]
    param(
        [switch]$ListAvailable
    )

    if (-not $ListAvailable) {
        return $script:MgcContext
    }

    if ($null -eq $script:MgcSessions -or $script:MgcSessions.Count -eq 0) { return @() }

    $activeKey = if ($script:MgcActiveSession) { $script:MgcActiveSession.CacheKey } else { $null }
    foreach ($key in $script:MgcSessions.Keys) {
        $session = $script:MgcSessions[$key]
        Get-MgcSessionSummary -Session $session -IsActive:($key -eq $activeKey)
    }
}
