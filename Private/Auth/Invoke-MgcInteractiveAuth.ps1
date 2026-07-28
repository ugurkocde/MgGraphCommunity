function Invoke-MgcInteractiveAuth {
    <#
    .SYNOPSIS
        OAuth 2.0 Authorization Code + PKCE via system browser and a loopback listener.

    .DESCRIPTION
        - Starts an HttpListener on an OS-assigned (or user-specified) loopback port,
          retrying with a fresh port if another process wins the bind race.
        - Generates a PKCE pair and a crypto-random state value.
        - Opens the user's default browser to the /authorize endpoint.
        - Waits (async with 5-min timeout) for the redirect callback; stray local
          requests (favicon.ico, preconnects) are answered with 404 and ignored.
        - Validates the state parameter to defend against CSRF.
        - Exchanges the authorization code + verifier for tokens at /token.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','',
        Justification = 'Interactive flow - user-visible progress.')]
    param(
        [Parameter(Mandatory)][string]$LoginEndpoint,
        [Parameter(Mandatory)][string]$TenantSegment,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string[]]$Scopes,
        [int]    $RedirectPort,
        [switch] $ForceConsent
    )

    # Bind the listener BEFORE building the authorize URL. An OS-assigned port can
    # be grabbed by another process between probing it and binding the listener,
    # so retry with a fresh port. A user-specified port gets one attempt and a
    # clear error (the app registration may require that exact redirect URI).
    $autoPort        = (-not $RedirectPort -or $RedirectPort -le 0)
    $maxBindAttempts = if ($autoPort) { 5 } else { 1 }
    $listener        = $null
    for ($bindAttempt = 1; $bindAttempt -le $maxBindAttempts; $bindAttempt++) {
        if ($autoPort) { $RedirectPort = Get-MgcFreePort }
        $candidate = [System.Net.HttpListener]::new()
        $candidate.Prefixes.Add("http://localhost:$RedirectPort/")
        try {
            $candidate.Start()
            $listener = $candidate
            break
        } catch {
            $candidate.Close()
            if ($bindAttempt -eq $maxBindAttempts) {
                throw "Could not start the loopback listener on http://localhost:$RedirectPort/ : $($_.Exception.Message)"
            }
        }
    }
    $redirectUri = "http://localhost:$RedirectPort/"

    try {
        $pkce = New-MgcPkcePair
        # CSRF state from the same crypto RNG as the PKCE verifier (a GUID is not
        # contractually a CSPRNG).
        $stateBytes = [byte[]]::new(16)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($stateBytes) } finally { $rng.Dispose() }
        $state = [Convert]::ToBase64String($stateBytes).TrimEnd('=').Replace('+','-').Replace('/','_')

        # CAE opt-in: advertise the CP1 client capability so Entra issues
        # long-lived, revocable access tokens (claims challenges handled in
        # Invoke-MgGraphCommunityRequest).
        $caeClaims = Get-MgcCaeClaims

        $authParams = [ordered]@{
            client_id             = $ClientId
            response_type         = 'code'
            redirect_uri          = $redirectUri
            response_mode         = 'query'
            scope                 = ($Scopes -join ' ')
            state                 = $state
            code_challenge        = $pkce.Challenge
            code_challenge_method = $pkce.Method
            claims                = $caeClaims
            prompt                = $(if ($ForceConsent) { 'consent' } else { 'select_account' })
        }

        $query   = ($authParams.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$([Uri]::EscapeDataString([string]$_.Value))"
        }) -join '&'
        $authUrl = "$LoginEndpoint/$TenantSegment/oauth2/v2.0/authorize?$query"

        Write-Host "Opening browser for sign-in (listening on $redirectUri)..." -ForegroundColor Cyan
        Start-Process $authUrl | Out-Null

        # Wait for the OAuth callback within an overall 5-minute deadline.
        # Stray local requests (favicon.ico, browser preconnects) get a 404 and
        # do not consume the flow.
        $deadline = [DateTime]::UtcNow.AddMinutes(5)
        $ctx = $null
        while (-not $ctx) {
            $remaining = $deadline - [DateTime]::UtcNow
            if ($remaining -le [TimeSpan]::Zero) { throw "Authentication timed out after 5 minutes." }
            $ctxTask = $listener.GetContextAsync()
            if (-not $ctxTask.Wait($remaining)) { throw "Authentication timed out after 5 minutes." }
            $candidateCtx = $ctxTask.Result
            if ($candidateCtx.Request.QueryString['code'] -or $candidateCtx.Request.QueryString['error']) {
                $ctx = $candidateCtx
            } else {
                $candidateCtx.Response.StatusCode = 404
                $candidateCtx.Response.Close()
            }
        }

        $code          = $ctx.Request.QueryString['code']
        $err           = $ctx.Request.QueryString['error']
        $errDesc       = $ctx.Request.QueryString['error_description']
        $returnedState = $ctx.Request.QueryString['state']
        $stateValid    = ($returnedState -eq $state)

        $successHtml = "<html><body style='font-family:Segoe UI,sans-serif;text-align:center;padding-top:80px;'><h2>Authentication Successful</h2><p>You can close this window and return to PowerShell.</p></body></html>"
        $errorHtml   = "<html><body style='font-family:Segoe UI,sans-serif;text-align:center;padding-top:80px;color:#c0392b;'><h2>Authentication Failed</h2><p>$([System.Net.WebUtility]::HtmlEncode($errDesc))</p></body></html>"

        $html  = if ($code -and $stateValid) { $successHtml } else { $errorHtml }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $ctx.Response.ContentType    = 'text/html'
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()

        if (-not $stateValid) { throw "OAuth state mismatch - possible CSRF. Aborting." }
        if (-not $code) { throw "Authorization failed: $err - $errDesc" }

        $body = @{
            client_id     = $ClientId
            grant_type    = 'authorization_code'
            code          = $code
            redirect_uri  = $redirectUri
            code_verifier = $pkce.Verifier
            scope         = ($Scopes -join ' ')
            claims        = $caeClaims
        }
        return Invoke-MgcTokenEndpoint -Url "$LoginEndpoint/$TenantSegment/oauth2/v2.0/token" -Body $body
    }
    finally {
        $listener.Stop()
        $listener.Close()
    }
}
