@{
    RootModule           = 'MgGraphCommunity.psm1'
    ModuleVersion        = '1.2.0'
    GUID                 = 'a7c1f4b8-5d20-4e6e-9a3b-2e8f0d1c7b42'
    Author               = 'MgGraphCommunity contributors'
    CompanyName          = 'Community'
    Copyright            = '(c) MgGraphCommunity contributors. Licensed under MIT.'
    Description          = 'A self-contained, community-maintained drop-in alternative to Connect-MgGraph. Pure-PowerShell OAuth 2.0 flows (PKCE, device code, client credentials, certificate, managed identity, BYO token) plus its own Invoke-MgGraphCommunityRequest for calling Graph endpoints. No required dependencies. No WAM. No MSAL.'
    PowerShellVersion    = '7.1'

    # No required modules — MgGraphCommunity is fully self-contained.
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
