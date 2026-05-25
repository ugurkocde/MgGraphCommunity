@{
    RootModule           = 'MgGraphCommunity.psm1'
    ModuleVersion        = '1.3.0'
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
        'Invoke-MgGraphCommunityRequest',
        'Add-MgGraphCommunityDefaultHeader',
        'Remove-MgGraphCommunityDefaultHeader',
        'Get-MgGraphCommunityDefaultHeader'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Invoke-MgcRequest','Add-MgcHeader','Remove-MgcHeader','Get-MgcHeader')

    PrivateData = @{
        PSData = @{
            Tags         = @('Microsoft','Graph','MgGraph','Authentication','OAuth','PKCE','Intune','Entra','EntraID','Community')
            LicenseUri   = 'https://github.com/ugurkocde/MgGraphCommunity/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/ugurkocde/MgGraphCommunity'
            ReleaseNotes = @'
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
