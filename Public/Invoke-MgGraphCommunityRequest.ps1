function Invoke-MgGraphCommunityRequest {
    <#
    .SYNOPSIS
        Calls a Microsoft Graph endpoint using the current MgGraphCommunity session.

    .DESCRIPTION
        A pure-PowerShell drop-in for Invoke-MgGraphRequest. Sends a request to
        Microsoft Graph using the access token from the most recent
        Connect-MgGraphCommunity call.

        Features:
          - Auto-prepends the active environment's Graph host for relative URIs
            ('/me' becomes 'https://graph.microsoft.com/v1.0/me').
          - -Beta swaps /v1.0 -> /beta for relative URIs.
          - Proactive refresh: if the access token expires within 5 minutes, the
            cached refresh token is used to silently re-acquire BEFORE the call.
          - Reactive refresh: on HTTP 401, attempts one silent refresh and retries.
          - On HTTP 429, honors the Retry-After header and retries.
          - On HTTP 504 Gateway Timeout, sleeps 60 seconds and retries once.
          - -FollowPagination walks @odata.nextLink and returns combined values.
          - Default headers added via Add-MgGraphCommunityDefaultHeader are merged
            automatically. Per-call -Headers override defaults.
          - Surfaces Microsoft Graph error.code / error.message as PowerShell errors.

        Requires Connect-MgGraphCommunity to have established a session first.

    .PARAMETER Method
        HTTP method. Defaults to GET.

    .PARAMETER Uri
        Full URL (https://graph.microsoft.com/...) or a relative path
        ('/me', 'users?$top=5').

    .PARAMETER Body
        Request body. Objects are serialized as JSON; strings are sent as-is.

    .PARAMETER Headers
        Per-call HTTP headers. Merged on top of any default headers; per-call wins.

    .PARAMETER OutputType
        'PSObject' (default) parses JSON into PowerShell objects.
        'Hashtable' returns ConvertFrom-Json -AsHashtable.
        'HttpResponse' returns the raw response object.

    .PARAMETER FollowPagination
        Auto-follow @odata.nextLink and merge .value arrays across pages.

    .PARAMETER Beta
        Use the /beta endpoint instead of /v1.0 when expanding a relative URI.

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Uri '/me'

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Uri '/users?$top=5' -Beta

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Uri '/users' -FollowPagination

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Method POST -Uri '/groups' -Body @{
            displayName     = 'Marketing'
            mailEnabled     = $false
            mailNickname    = 'marketing'
            securityEnabled = $true
        }
    #>
    [CmdletBinding()]
    [Alias('Invoke-MgcRequest')]
    param(
        [ValidateSet('GET','POST','PUT','PATCH','DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory, Position = 0)]
        [string]$Uri,

        [object]$Body,

        [hashtable]$Headers,

        [ValidateSet('PSObject','Hashtable','HttpResponse')]
        [string]$OutputType = 'PSObject',

        [switch]$FollowPagination,

        [switch]$Beta
    )

    if (-not $script:MgcActiveSession) {
        throw "Not connected. Run Connect-MgGraphCommunity first."
    }

    # ---- Proactive token refresh ----
    # If the access token expires within 5 minutes, refresh before the call.
    if ($script:MgcActiveSession.ExpiresOn -and $script:MgcActiveSession.Tokens.refresh_token) {
        $remainingMin = ($script:MgcActiveSession.ExpiresOn - (Get-Date).ToUniversalTime()).TotalMinutes
        if ($remainingMin -le 5) {
            Write-Verbose ("Access token expires in {0:N1} min — refreshing proactively." -f $remainingMin)
            try {
                $newTokens = Invoke-MgcRefreshTokenAuth `
                    -LoginEndpoint $script:MgcActiveSession.Authority.Login `
                    -TenantSegment $script:MgcActiveSession.TenantSegment `
                    -ClientId      $script:MgcActiveSession.ClientId `
                    -RefreshToken  $script:MgcActiveSession.Tokens.refresh_token `
                    -Scopes        $script:MgcActiveSession.Scopes
                $script:MgcActiveSession.Tokens    = $newTokens
                $script:MgcActiveSession.ExpiresOn = Get-MgcTokenExpiry -Tokens $newTokens
                Save-MgcTokenCache -Key $script:MgcActiveSession.CacheKey -Tokens $newTokens -Persist:$script:MgcActiveSession.Persist
            } catch {
                Write-Verbose "Proactive refresh failed (will rely on reactive 401 retry): $_"
            }
        }
    }

    # Resolve relative URIs against the active environment
    $resolvedUri = if ($Uri -match '^https?://') {
        $Uri
    } else {
        $apiVer  = if ($Beta) { 'beta' } else { 'v1.0' }
        $cleaned = $Uri.TrimStart('/')
        "{0}/{1}/{2}" -f $script:MgcActiveSession.Authority.GraphResource, $apiVer, $cleaned
    }

    # Build the request closure (so we can call it multiple times for retries)
    $sendRequest = {
        param([string]$accessToken)

        $mergedHeaders = @{
            'Authorization' = "Bearer $accessToken"
            'Content-Type'  = 'application/json'
        }
        # Session-wide default headers (set via Add-MgGraphCommunityDefaultHeader)
        if ($script:MgcDefaultHeaders) {
            foreach ($k in $script:MgcDefaultHeaders.Keys) { $mergedHeaders[$k] = $script:MgcDefaultHeaders[$k] }
        }
        # Per-call -Headers override defaults
        if ($Headers) {
            foreach ($k in $Headers.Keys) { $mergedHeaders[$k] = $Headers[$k] }
        }

        $params = @{
            Uri     = $resolvedUri
            Method  = $Method
            Headers = $mergedHeaders
        }

        if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
            $params['Body'] = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        }

        # Invoke-MgcHttpRequest abstracts -SkipHttpErrorCheck differences across
        # PS 5.1 vs 7.x and returns a uniform { StatusCode; Headers; Content } object.
        Invoke-MgcHttpRequest -Parameters $params
    }

    # ---- First attempt ----
    $attempt = & $sendRequest -accessToken $script:MgcActiveSession.Tokens.access_token

    # ---- Retry on 401: reactive refresh once if possible ----
    if ($attempt.StatusCode -eq 401 -and $script:MgcActiveSession.Tokens.refresh_token) {
        Write-Verbose "401 from Graph — attempting silent token refresh."
        try {
            $newTokens = Invoke-MgcRefreshTokenAuth `
                -LoginEndpoint $script:MgcActiveSession.Authority.Login `
                -TenantSegment $script:MgcActiveSession.TenantSegment `
                -ClientId      $script:MgcActiveSession.ClientId `
                -RefreshToken  $script:MgcActiveSession.Tokens.refresh_token `
                -Scopes        $script:MgcActiveSession.Scopes
            $script:MgcActiveSession.Tokens    = $newTokens
            $script:MgcActiveSession.ExpiresOn = Get-MgcTokenExpiry -Tokens $newTokens
            Save-MgcTokenCache -Key $script:MgcActiveSession.CacheKey -Tokens $newTokens -Persist:$script:MgcActiveSession.Persist
            $attempt = & $sendRequest -accessToken $newTokens.access_token
        } catch {
            Write-Verbose "Reactive refresh failed: $_"
        }
    }

    # ---- Retry on 429: respect Retry-After ----
    if ($attempt.StatusCode -eq 429) {
        $wait = 5
        if ($attempt.Headers -and $attempt.Headers['Retry-After']) {
            try { $wait = [int]([array]$attempt.Headers['Retry-After'])[0] } catch { }
        }
        Write-Verbose "429 throttled by Graph — sleeping $wait seconds before retry."
        Start-Sleep -Seconds $wait
        $attempt = & $sendRequest -accessToken $script:MgcActiveSession.Tokens.access_token
    }

    # ---- Retry on 504: Graph gateway timeout ----
    if ($attempt.StatusCode -eq 504) {
        Write-Verbose "504 Gateway Timeout from Graph — sleeping 60 seconds and retrying once."
        Start-Sleep -Seconds 60
        $attempt = & $sendRequest -accessToken $script:MgcActiveSession.Tokens.access_token
    }

    # ---- Error handling ----
    if ($attempt.StatusCode -ge 400) {
        $msg = "HTTP $($attempt.StatusCode) from $resolvedUri"
        try {
            if ($attempt.Content) {
                $errBody = $attempt.Content | ConvertFrom-Json -ErrorAction Stop
                if ($errBody.error) {
                    $msg = "Graph error $($attempt.StatusCode) [$($errBody.error.code)]: $($errBody.error.message)"
                }
            }
        } catch { }
        throw $msg
    }

    if ($OutputType -eq 'HttpResponse') { return $attempt }

    # Parse JSON response
    $contentType = $null
    if ($attempt.Headers) { $contentType = $attempt.Headers['Content-Type'] }
    $isJson = $contentType -and ($contentType -join ' ') -match 'json'
    $raw    = $attempt.Content

    if (-not $raw) { return $null }
    if (-not $isJson) { return $raw }

    # ConvertFrom-Json -AsHashtable is PS 6+; on PS 5.1 we convert PSObject -> Hashtable manually.
    $parsed = if ($OutputType -eq 'Hashtable') {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $raw | ConvertFrom-Json -AsHashtable
        } else {
            $raw | ConvertFrom-Json | ConvertTo-MgcHashtable
        }
    } else {
        $raw | ConvertFrom-Json
    }

    # ---- Pagination ----
    # Works whether $parsed is a Hashtable (PS 5.1 fallback) or a PSCustomObject.
    if ($FollowPagination -and $parsed.value -and $parsed.'@odata.nextLink') {
        $all = @($parsed.value)
        $next = $parsed.'@odata.nextLink'
        while ($next) {
            $page = Invoke-MgGraphCommunityRequest -Method GET -Uri $next -OutputType $OutputType
            if ($page.value) { $all += $page.value }
            $next = $page.'@odata.nextLink'
        }
        return $all
    }

    return $parsed
}
