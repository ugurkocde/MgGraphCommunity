function Invoke-MgcRefreshTokenAuth {
    <#
    .SYNOPSIS
        Exchanges a refresh token for a new access token (silent re-auth).

    .PARAMETER Claims
        Claims JSON for the 'claims' parameter. Defaults to the CAE client
        capability (xms_cc CP1). Callers responding to a CAE claims challenge pass
        the merged challenge claims here (see Get-MgcCaeClaims).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LoginEndpoint,
        [Parameter(Mandatory)][string]$TenantSegment,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$RefreshToken,
        [Parameter(Mandatory)][string[]]$Scopes,
        [string]$Claims
    )

    if (-not $Claims) { $Claims = Get-MgcCaeClaims }

    $body = @{
        client_id     = $ClientId
        grant_type    = 'refresh_token'
        refresh_token = $RefreshToken
        scope         = ($Scopes -join ' ')
        claims        = $Claims
    }
    return Invoke-MgcTokenEndpoint -Url "$LoginEndpoint/$TenantSegment/oauth2/v2.0/token" -Body $body
}
