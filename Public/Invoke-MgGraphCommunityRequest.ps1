function Invoke-MgGraphCommunityRequest {
    <#
    .SYNOPSIS
        Calls a Microsoft Graph endpoint using the current MgGraphCommunity session.

    .DESCRIPTION
        A pure-PowerShell drop-in for Invoke-MgGraphRequest. Sends a request to
        Microsoft Graph using the access token from the most recent
        Connect-MgGraphCommunity call.

        Features:
          - Auto-prepends the active environment's Graph host for relative URIs.
            Relative URIs default to the /beta endpoint ('/me' becomes
            'https://graph.microsoft.com/beta/me'), because beta exposes more of
            the Graph surface. Use -V1 for the stable /v1.0 endpoint.
          - Proactive refresh: if the access token expires within 5 minutes, the
            cached refresh token is used to silently re-acquire BEFORE the call.
          - Reactive refresh: on HTTP 401, attempts one silent refresh and retries.
          - Transient errors (HTTP 429 / 503 / 504) are retried up to -MaxRetry times
            with backoff; Retry-After is honored when present.
          - -FollowPagination walks @odata.nextLink and returns combined values.
          - Binary I/O: -InputFilePath uploads a file's bytes; -OutputFilePath streams
            the raw response to disk; -ContentType controls the request body media type.
          - Default headers added via Add-MgGraphCommunityDefaultHeader are merged
            automatically. Per-call -Headers override defaults.
          - A client-request-id is sent on every call; on errors the Graph
            request-id / client-request-id are surfaced for support correlation.
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
        Auto-follow @odata.nextLink and return the merged .value items from all
        pages as a single array (also for single-page collection responses).

    .PARAMETER Beta
        Use the /beta endpoint when expanding a relative URI. Beta is already the
        default; this switch is retained for backward compatibility and is a no-op
        unless combined with nothing else.

    .PARAMETER V1
        Use the stable /v1.0 endpoint instead of the default /beta when expanding a
        relative URI. Ignored for absolute URLs (which carry their own version).
        Takes precedence over -Beta if both are supplied.

    .PARAMETER ContentType
        Media type for the request body. Defaults to 'application/json'. When set to
        anything other than JSON, the body is sent as-is (string or byte[]) without
        being serialized to JSON.

    .PARAMETER InputFilePath
        Path to a file whose raw bytes are sent as the request body (uploads, e.g.
        PUT .../photo/$value or an upload-session chunk). Defaults ContentType to
        'application/octet-stream' when no -ContentType is given.

    .PARAMETER OutputFilePath
        Write the raw response body to this file instead of parsing it (downloads,
        e.g. GET .../photo/$value). The response bytes are streamed binary-safe.

    .PARAMETER MaxRetry
        Maximum number of retries for transient HTTP errors (429 / 503 / 504).
        Defaults to 3. Set to 0 to disable transient-error retries.

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Uri '/me'

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Uri "/me/photo/`$value" -OutputFilePath ./me.jpg

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Method PUT -Uri "/me/photo/`$value" -InputFilePath ./me.jpg -ContentType 'image/jpeg'

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Uri '/users?$top=5'          # /beta (default)

    .EXAMPLE
        Invoke-MgGraphCommunityRequest -Uri '/users?$top=5' -V1      # stable /v1.0

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

        [switch]$Beta,

        [switch]$V1,

        [string]$ContentType,

        [string]$InputFilePath,

        [string]$OutputFilePath,

        [ValidateRange(0, 10)]
        [int]$MaxRetry = 3
    )

    if (-not $script:MgcActiveSession) {
        throw "Not connected. Run Connect-MgGraphCommunity first."
    }

    # ---- Proactive token refresh ----
    # If the access token expires within 5 minutes, refresh before the call.
    if ($script:MgcActiveSession.ExpiresOn -and $script:MgcActiveSession.Tokens.refresh_token) {
        $remainingMin = ($script:MgcActiveSession.ExpiresOn - (Get-Date).ToUniversalTime()).TotalMinutes
        if ($remainingMin -le 5) {
            Write-Verbose ("Access token expires in {0:N1} min - refreshing proactively." -f $remainingMin)
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
        # Default to /beta (more surface area); -V1 opts down to the stable endpoint.
        $apiVer  = if ($V1) { 'v1.0' } else { 'beta' }
        $cleaned = $Uri.TrimStart('/')
        "{0}/{1}/{2}" -f $script:MgcActiveSession.Authority.GraphResource, $apiVer, $cleaned
    }

    # ---- Resolve the request body and its media type ----
    $effectiveContentType = if ($ContentType)         { $ContentType }
                            elseif ($InputFilePath)    { 'application/octet-stream' }
                            else                       { 'application/json' }
    $isJsonBody = $effectiveContentType -match 'json'

    $requestBody = $null
    $hasBody     = $false
    if ($InputFilePath) {
        $resolvedInput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputFilePath)
        if (-not (Test-Path -LiteralPath $resolvedInput)) { throw "InputFilePath not found: $InputFilePath" }
        $requestBody = [System.IO.File]::ReadAllBytes($resolvedInput)
        $hasBody     = $true
    } elseif ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        # JSON bodies that aren't already a string get serialized; everything else
        # (raw string, byte[], non-JSON content type) is sent as-is.
        $requestBody = if ($isJsonBody -and -not ($Body -is [string])) {
            $Body | ConvertTo-Json -Depth 20 -Compress
        } else {
            $Body
        }
        $hasBody = $true
    }

    # One client-request-id per call (reused across retries) for support correlation.
    $clientRequestId = [guid]::NewGuid().ToString()

    # Build the request closure (so we can call it multiple times for retries)
    $sendRequest = {
        param([string]$accessToken)

        $mergedHeaders = @{
            'Content-Type'      = $effectiveContentType
            'client-request-id' = $clientRequestId
        }
        # Session-wide default headers (set via Add-MgGraphCommunityDefaultHeader)
        if ($script:MgcDefaultHeaders) {
            foreach ($k in $script:MgcDefaultHeaders.Keys) { $mergedHeaders[$k] = $script:MgcDefaultHeaders[$k] }
        }
        # Per-call -Headers override defaults
        if ($Headers) {
            foreach ($k in $Headers.Keys) { $mergedHeaders[$k] = $Headers[$k] }
        }
        # Always last: neither default nor per-call headers may replace the
        # session's bearer token (hashtable keys are case-insensitive).
        $mergedHeaders['Authorization'] = "Bearer $accessToken"

        $params = @{
            Uri     = $resolvedUri
            Method  = $Method
            Headers = $mergedHeaders
        }

        if ($hasBody) { $params['Body'] = $requestBody }

        # Invoke-MgcHttpRequest abstracts -SkipHttpErrorCheck differences across
        # PS 5.1 vs 7.x and returns a uniform { StatusCode; Headers; Content } object.
        # -ReturnBytes captures binary-safe bytes for file downloads.
        if ($OutputFilePath) {
            Invoke-MgcHttpRequest -Parameters $params -ReturnBytes
        } else {
            Invoke-MgcHttpRequest -Parameters $params
        }
    }

    # ---- First attempt ----
    $attempt = & $sendRequest -accessToken $script:MgcActiveSession.Tokens.access_token

    # ---- Retry on 401: reactive refresh once if possible ----
    # A plain 401 means the access token expired; a 401 whose WWW-Authenticate
    # header carries a claims challenge is a Continuous Access Evaluation event
    # (revocation, policy change). Both paths re-acquire silently exactly once,
    # the CAE path passing the challenge claims back to the token endpoint.
    if ($attempt.StatusCode -eq 401 -and $script:MgcActiveSession.Tokens.refresh_token) {
        $challengeClaims = $null
        if ($attempt.Headers) {
            $challengeClaims = Get-MgcClaimsChallenge -WwwAuthenticate $attempt.Headers['WWW-Authenticate']
        }
        if ($challengeClaims) {
            Write-Verbose "401 with CAE claims challenge - re-acquiring token with challenge claims."
        } else {
            Write-Verbose "401 from Graph - attempting silent token refresh."
        }
        try {
            $refreshParams = @{
                LoginEndpoint = $script:MgcActiveSession.Authority.Login
                TenantSegment = $script:MgcActiveSession.TenantSegment
                ClientId      = $script:MgcActiveSession.ClientId
                RefreshToken  = $script:MgcActiveSession.Tokens.refresh_token
                Scopes        = $script:MgcActiveSession.Scopes
            }
            if ($challengeClaims) {
                $refreshParams['Claims'] = Get-MgcCaeClaims -ChallengeClaims $challengeClaims
            }
            $newTokens = Invoke-MgcRefreshTokenAuth @refreshParams
            $script:MgcActiveSession.Tokens    = $newTokens
            $script:MgcActiveSession.ExpiresOn = Get-MgcTokenExpiry -Tokens $newTokens
            Save-MgcTokenCache -Key $script:MgcActiveSession.CacheKey -Tokens $newTokens -Persist:$script:MgcActiveSession.Persist
            $attempt = & $sendRequest -accessToken $newTokens.access_token
        } catch {
            if ($challengeClaims) {
                throw "Continuous Access Evaluation re-authentication failed. Run Connect-MgGraphCommunity to sign in again. Details: $_"
            }
            Write-Verbose "Reactive refresh failed: $_"
        }
    }

    # ---- Retry transient errors (429 / 503 / 504) with backoff ----
    # Honors Retry-After when present (429 / 503); otherwise exponential backoff
    # capped at 60s (504 rarely carries Retry-After).
    $retry = 0
    while (($attempt.StatusCode -in 429, 503, 504) -and ($retry -lt $MaxRetry)) {
        $retry++
        $wait = $null
        if ($attempt.Headers -and $attempt.Headers['Retry-After']) {
            try { $wait = [int]([array]$attempt.Headers['Retry-After'])[0] } catch { $wait = $null }
        }
        if ($null -eq $wait) { $wait = [int][Math]::Min(60, [Math]::Pow(2, $retry) * 2) }
        $wait = [Math]::Max(0, $wait)
        Write-Verbose ("HTTP {0} from Graph - retry {1}/{2} after {3}s." -f $attempt.StatusCode, $retry, $MaxRetry, $wait)
        Start-Sleep -Seconds $wait
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
        # Surface correlation IDs for Graph support tickets.
        $corr = @()
        if ($attempt.Headers) {
            if ($attempt.Headers['request-id'])        { $corr += "request-id: $(($attempt.Headers['request-id'] -join ' '))" }
            if ($attempt.Headers['client-request-id']) { $corr += "client-request-id: $(($attempt.Headers['client-request-id'] -join ' '))" }
        }
        if ($corr.Count -eq 0) { $corr += "client-request-id: $clientRequestId" }
        $msg += " (" + ($corr -join '; ') + ")"
        throw $msg
    }

    # ---- Binary download: stream raw bytes to disk ----
    if ($OutputFilePath) {
        $fullOut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFilePath)
        $bytes   = if ($null -ne $attempt.ContentBytes) { $attempt.ContentBytes } else { [byte[]]@() }
        [System.IO.File]::WriteAllBytes($fullOut, $bytes)
        return (Get-Item -LiteralPath $fullOut)
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
    # Keyed on the PRESENCE of .value (an empty first page is still a collection),
    # so -FollowPagination always returns the merged items, even for one page.
    if ($FollowPagination) {
        $hasValue = if ($parsed -is [System.Collections.IDictionary]) {
            $parsed.Contains('value')
        } else {
            $null -ne $parsed.PSObject.Properties['value']
        }
        if ($hasValue) {
            $all  = @($parsed.value)
            $next = $parsed.'@odata.nextLink'
            while ($next) {
                $page = Invoke-MgGraphCommunityRequest -Method GET -Uri $next -OutputType $OutputType
                if ($page.value) { $all += $page.value }
                $next = $page.'@odata.nextLink'
            }
            return $all
        }
    }

    return $parsed
}
