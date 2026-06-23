function Get-MgcSessionSummary {
    <#
    .SYNOPSIS
        Builds a user-facing summary object for a stored session.

    .DESCRIPTION
        Used by Get-MgGraphCommunityContext -ListAvailable and
        Select-MgGraphCommunityContext to describe a connection without exposing
        tokens. Decodes the access token JWT for identity fields when possible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session,
        [switch]$IsActive
    )

    $account = $null
    $tenant  = $Session.TenantSegment
    try {
        $claims = ConvertFrom-MgcJwt -Token $Session.Tokens.access_token
        foreach ($c in @($claims.upn, $claims.preferred_username, $claims.unique_name, $claims.app_displayname, $claims.appid)) {
            if ($c) { $account = $c; break }
        }
        if ($claims.tid) { $tenant = $claims.tid }
    } catch {
        Write-Verbose "Session summary JWT decode failed: $_"
    }

    [pscustomobject]@{
        IsActive    = [bool]$IsActive
        Account     = $account
        TenantId    = $tenant
        ClientId    = $Session.ClientId
        Environment = $Session.Authority.Environment
        FlowType    = $Session.FlowType
        ExpiresOn   = $Session.ExpiresOn
        CacheKey    = $Session.CacheKey
    }
}
