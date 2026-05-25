function Set-MgcConnectionContext {
    <#
    .SYNOPSIS
        Records the active connection in module-scoped state.

    .DESCRIPTION
        Builds a context object mirroring Get-MgContext shape (Account, TenantId,
        Scopes, AuthType, Environment, ExpiresOn) plus a few MgGraphCommunity-specific
        fields (FlowType, ClientId, Persisted). Decodes the access token JWT for
        identity fields when possible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Tokens,
        [Parameter(Mandatory)][string]$FlowType,
        [Parameter(Mandatory)][string]$ClientId,
        [string]$TenantId,
        [string]$Environment = 'Global',
        [string[]]$Scopes,
        [switch]$Persisted
    )

    $account     = $null
    $issuedTid   = $null
    $expiresOn   = $null
    $appName     = $null
    $tokenScopes = $null

    # Helper: first non-null/non-empty value (cross-version safe; PS 5.1 has no ??)
    $firstNonEmpty = {
        param([Parameter(ValueFromRemainingArguments)]$values)
        foreach ($v in $values) {
            if ($null -ne $v -and -not ([string]::IsNullOrEmpty([string]$v))) { return $v }
        }
        return $null
    }

    try {
        $claims      = ConvertFrom-MgcJwt -Token $Tokens.access_token
        $account     = & $firstNonEmpty $claims.upn $claims.preferred_username $claims.unique_name $claims.email
        $issuedTid   = $claims.tid
        $appName     = & $firstNonEmpty $claims.app_displayname $claims.appid
        if ($claims.exp) {
            $expiresOn = [DateTimeOffset]::FromUnixTimeSeconds([int64]$claims.exp).LocalDateTime
        }
        if ($claims.scp) { $tokenScopes = ($claims.scp -split ' ') }
        elseif ($claims.roles) { $tokenScopes = [string[]]$claims.roles }
    } catch {
        Write-Verbose "JWT decode for context failed: $_"
    }

    if (-not $expiresOn -and $Tokens.expires_in) {
        $expiresOn = (Get-Date).AddSeconds([int]$Tokens.expires_in)
    }

    $resolvedTenant = if ($issuedTid) { $issuedTid } else { $TenantId }
    $resolvedScopes = if ($tokenScopes) { $tokenScopes } else { $Scopes }

    $script:MgcContext = [pscustomobject]@{
        Account     = $account
        AppName     = $appName
        TenantId    = $resolvedTenant
        Scopes      = $resolvedScopes
        AuthType    = $FlowType
        FlowType    = $FlowType
        Environment = $Environment
        ClientId    = $ClientId
        ExpiresOn   = $expiresOn
        Persisted   = [bool]$Persisted
    }

    return $script:MgcContext
}
