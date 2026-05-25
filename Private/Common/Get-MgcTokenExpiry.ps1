function Get-MgcTokenExpiry {
    <#
    .SYNOPSIS
        Returns the UTC expiry time of an access token.

    .DESCRIPTION
        Prefers the JWT 'exp' claim (authoritative). Falls back to expires_in
        from the token response if the JWT can't be decoded.

    .OUTPUTS
        [DateTime] UTC, or $null if neither source is usable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Tokens
    )

    if (-not $Tokens) { return $null }

    if ($Tokens.access_token) {
        try {
            $claims = ConvertFrom-MgcJwt -Token $Tokens.access_token
            if ($claims.exp) {
                return [DateTimeOffset]::FromUnixTimeSeconds([int64]$claims.exp).UtcDateTime
            }
        } catch {
            Write-Verbose "JWT decode for expiry failed: $_"
        }
    }

    if ($Tokens.expires_in) {
        return (Get-Date).ToUniversalTime().AddSeconds([int]$Tokens.expires_in)
    }

    return $null
}
