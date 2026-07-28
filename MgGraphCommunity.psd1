@{
    RootModule           = 'MgGraphCommunity.psm1'
    ModuleVersion        = '1.5.0'
    GUID                 = 'a7c1f4b8-5d20-4e6e-9a3b-2e8f0d1c7b42'
    Author               = 'MgGraphCommunity contributors'
    CompanyName          = 'Community'
    Copyright            = '(c) MgGraphCommunity contributors. Licensed under MIT.'
    Description          = 'A self-contained, community-maintained drop-in alternative to Connect-MgGraph. Pure-PowerShell OAuth 2.0 flows (PKCE, device code, client credentials, certificate, managed identity, BYO token) plus its own Invoke-MgGraphCommunityRequest for calling Graph endpoints. No required dependencies. No WAM. No MSAL.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop','Core')

    # No required modules - MgGraphCommunity is fully self-contained.
    # If Microsoft.Graph.Authentication happens to be installed, we hand off
    # the access token so existing Microsoft.Graph.* cmdlets also work.

    FunctionsToExport    = @(
        'Connect-MgGraphCommunity',
        'Disconnect-MgGraphCommunity',
        'Get-MgGraphCommunityContext',
        'Select-MgGraphCommunityContext',
        'Invoke-MgGraphCommunityRequest',
        'Invoke-MgGraphCommunityBatch',
        'Add-MgGraphCommunityDefaultHeader',
        'Remove-MgGraphCommunityDefaultHeader',
        'Get-MgGraphCommunityDefaultHeader',
        'New-MgGraphCommunityAppRegistration',
        'Set-MgGraphCommunityDefaultClientId'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Invoke-MgcRequest','Invoke-MgcBatch','Select-MgcContext','Add-MgcHeader','Remove-MgcHeader','Get-MgcHeader','New-MgcApp','Set-MgcDefaultClientId')

    PrivateData = @{
        PSData = @{
            Tags         = @('Microsoft','Graph','MgGraph','Authentication','OAuth','PKCE','Intune','Entra','EntraID','Community')
            LicenseUri   = 'https://github.com/ugurkocde/MgGraphCommunity/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/ugurkocde/MgGraphCommunity'
            ReleaseNotes = @'
1.5.0
- New: New-MgGraphCommunityAppRegistration (alias New-MgcApp) - create a ready-to-use
  single-tenant public client app registration for WAM-free sign-in, with optional
  -AddWamRedirectUri (SDK/WAM compatibility) and -SetAsDefault. Prepares for Microsoft's
  announced changes to the default delegated-auth app (msgraph-sdk-powershell #3629).
- New: Set-MgGraphCommunityDefaultClientId (alias Set-MgcDefaultClientId) - persist your
  own ClientId as the default for Connect-MgGraphCommunity; -Clear restores the built-in.
  Explicit -ClientId always wins over the saved default.
- New: Continuous Access Evaluation (CAE) support. Delegated flows (Interactive,
  DeviceCode, refresh) now advertise the CP1 client capability, so Entra ID issues
  long-lived revocable access tokens. Invoke-MgGraphCommunityRequest answers CAE claims
  challenges (401 + WWW-Authenticate claims) with a single silent re-acquisition and
  retry. Matches the official SDK's CAE support added in v2.37.0. App-only flows are
  unchanged (CAE for workload identities is a separate, narrower Microsoft feature).
- New: sovereign cloud environments BleuCloud (France), DelosCloud (Germany) and
  GovSGCloud (Singapore) on -Environment, mirroring official SDK v2.36.0 endpoints.
  Not live-tested; the built-in ClientId may not exist there, bring your own.

1.4.0
- New: Invoke-MgGraphCommunityBatch (alias Invoke-MgcBatch) - combine up to 20 Graph
  requests per $batch call, auto-chunking larger sets and auto-retrying throttled
  sub-responses. Returns one { id, status, headers, body } per request, in order.
- New: multi-connection switching. Connect now registers every connection; switch the
  active one with Select-MgGraphCommunityContext (alias Select-MgcContext) by
  -TenantId / -ClientId / -Index / -CacheKey, and enumerate them with
  Get-MgGraphCommunityContext -ListAvailable. No re-authentication required.
- New: binary I/O on Invoke-MgGraphCommunityRequest - -InputFilePath (upload file bytes),
  -OutputFilePath (stream the raw response to disk, binary-safe across PS 5.1/7.x), and
  -ContentType (send non-JSON bodies as-is). Useful for photo/$value and upload sessions.
- New: -MaxRetry on Invoke-MgGraphCommunityRequest. Transient errors (429 / 503 / 504)
  are now retried up to MaxRetry times (default 3) with backoff; Retry-After is honored.
  Previously 429 and 504 were retried once each and 503 was not retried.
- New: every request sends a client-request-id; Graph request-id / client-request-id are
  surfaced in thrown errors for support correlation.
- Change: relative URIs now default to the /beta endpoint (more Graph surface) instead of
  /v1.0. Use -V1 on Invoke-MgGraphCommunityRequest / Invoke-MgGraphCommunityBatch for the
  stable /v1.0 endpoint. -Beta is retained for compatibility and now matches the default.
- Change: the AccessToken (BYO) flow derives its lifetime from the token's JWT exp claim
  instead of assuming 3600 seconds (opaque tokens still fall back to 3600).
- Build: PSScriptAnalyzer now runs in CI (settings in PSScriptAnalyzerSettings.psd1).

1.3.1
- Fix: certificate auth (-Certificate / -CertificateThumbprint / -CertificateName) built
  client assertions with nbf/exp skewed by the machine's UTC offset, so Entra ID rejected
  them in most non-UTC timezones. Timestamps are now timezone- and culture-safe.
- Interactive flow: loopback listener retries when an OS-assigned port is grabbed in the
  bind race; stray local requests (favicon.ico, preconnects) get a 404 instead of aborting
  the sign-in; CSRF state now comes from a cryptographic RNG; the browser result page
  reflects the state check.
- Token cache: only the refresh token (plus minimal metadata) is persisted - access tokens
  no longer touch disk. On macOS/Linux, permissions (700 dir / 600 file) are applied BEFORE
  the payload is written and failures warn instead of staying silent. Explicit UTF-8 I/O.
- Request layer: the Authorization header can no longer be overwritten by default or
  per-call headers; Add-MgGraphCommunityDefaultHeader rejects 'Authorization'.
  -FollowPagination keys on the presence of .value, so empty first pages page correctly and
  single-page collections return the same merged-array shape as multi-page results.
- Managed identity (Azure Arc): the challenge-file path from WWW-Authenticate is validated
  (Arc tokens directory, .key extension, size cap) before being read.
- Module load fails fast with a clear message on .NET Framework < 4.6 (PS 5.1 on Windows 7 /
  Server 2008 R2), which the module's crypto/time APIs require.

1.3.0
- Cross-version support: module now runs on Windows PowerShell 5.1 in addition to PowerShell 7+.
  CompatiblePSEditions = Desktop, Core. PowerShellVersion = 5.1.
- Replaced PS 7-only constructs with cross-version equivalents:
  * Null-coalescing (??) -> first-non-empty helper in Set-MgcConnectionContext.
  * [SHA256]::HashData / [SHA1]::HashData / [RandomNumberGenerator]::Fill (PS 7.1+ static methods)
    replaced with Create()+ComputeHash / Create()+GetBytes that work in .NET Framework 4.x.
  * ConvertFrom-SecureString -AsPlainText replaced with Marshal BSTR round-trip.
  * ConvertFrom-Json -AsHashtable falls back to manual PSObject->Hashtable conversion on PS 5.1.
  * Invoke-WebRequest -SkipHttpErrorCheck abstracted behind new private Invoke-MgcHttpRequest
    helper that catches WebException on PS 5.1 and exposes a uniform response.
  * $IsWindows replaced with Test-MgcIsWindows helper.
- Module auto-enables TLS 1.2 on PowerShell 5.1 (PS 5.1 still defaults to TLS 1.0/1.1).

1.2.1
- Hotfix: Invoke-MgGraphCommunityRequest crashed on PowerShell 7.4+ with
  "Cannot convert ... GetString to type System.Byte[]". On PS 7.4+, Invoke-WebRequest
  returns the Content property as a string for text/JSON responses, not byte[].
  The cmdlet now handles both shapes so it works on PS 7.1 through 7.4+.

1.2.0
- Fix: removed -StatusCodeVariable usage in Invoke-MgGraphCommunityRequest. That parameter is
  PowerShell 7.4+ only and broke the cmdlet on PS 7.0-7.3. Now reads status directly from the
  response object, works on PS 7.1+.
- Change: Connect-MgGraphCommunity no longer returns the context object to the pipeline.
  -NoWelcome now produces a truly silent connect. Use Get-MgGraphCommunityContext to retrieve
  the active connection details.
- New: proactive token refresh. If the access token expires within 5 minutes,
  Invoke-MgGraphCommunityRequest refreshes silently BEFORE the call (in addition to the
  reactive 401-retry path that already existed).
- New: HTTP 504 Gateway Timeout is retried once after a 60-second sleep.
- New: Add-MgGraphCommunityDefaultHeader / Remove-MgGraphCommunityDefaultHeader /
  Get-MgGraphCommunityDefaultHeader. Set sticky session headers (e.g. ConsistencyLevel) without
  re-passing -Headers on every call. Aliases: Add-MgcHeader / Remove-MgcHeader / Get-MgcHeader.
- Manifest PowerShellVersion bumped from 7.0 to 7.1 to honestly document the .NET 5+ static-method
  usage already present in PKCE / SHA256 helpers.

1.1.0
- New: Invoke-MgGraphCommunityRequest (alias Invoke-MgcRequest) - pure-PowerShell Graph caller.
- Removed Microsoft.Graph.Authentication as a RequiredModule. The module is now fully self-contained.
- SDK handoff is opportunistic: if Microsoft.Graph.Authentication is installed we still hand
  the token to Connect-MgGraph so Microsoft.Graph.* cmdlets continue to work.

1.0.0
- Initial community release
- Interactive (PKCE + loopback), DeviceCode, ClientSecret, Certificate (X509/Thumbprint/Subject), AccessToken, ManagedIdentity flows
- Environment selection: Global, USGov, USGovDoD, China
- In-memory token cache by default; opt-in DPAPI-encrypted persistence via -PersistRefreshToken
- Pure PowerShell, no MSAL DLL hunting, no compiled C#
'@
        }
    }
}
