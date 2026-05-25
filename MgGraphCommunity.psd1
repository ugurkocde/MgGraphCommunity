@{
    RootModule           = 'MgGraphCommunity.psm1'
    ModuleVersion        = '1.1.0'
    GUID                 = 'a7c1f4b8-5d20-4e6e-9a3b-2e8f0d1c7b42'
    Author               = 'MgGraphCommunity contributors'
    CompanyName          = 'Community'
    Copyright            = '(c) MgGraphCommunity contributors. Licensed under MIT.'
    Description          = 'A self-contained, community-maintained drop-in alternative to Connect-MgGraph. Pure-PowerShell OAuth 2.0 flows (PKCE, device code, client credentials, certificate, managed identity, BYO token) plus its own Invoke-MgGraphCommunityRequest for calling Graph endpoints. No required dependencies. No WAM. No MSAL.'
    PowerShellVersion    = '7.0'

    # No required modules — MgGraphCommunity is fully self-contained.
    # If Microsoft.Graph.Authentication happens to be installed, we hand off
    # the access token so existing Microsoft.Graph.* cmdlets also work.

    FunctionsToExport    = @(
        'Connect-MgGraphCommunity',
        'Disconnect-MgGraphCommunity',
        'Get-MgGraphCommunityContext',
        'Invoke-MgGraphCommunityRequest'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Invoke-MgcRequest')

    PrivateData = @{
        PSData = @{
            Tags         = @('Microsoft','Graph','MgGraph','Authentication','OAuth','PKCE','Intune','Entra','EntraID','Community')
            LicenseUri   = 'https://github.com/ugurkocde/MgGraphCommunity/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/ugurkocde/MgGraphCommunity'
            ReleaseNotes = @'
1.1.0
- New: Invoke-MgGraphCommunityRequest (alias Invoke-MgcRequest) - pure-PowerShell Graph caller.
  Supports relative URIs, -Beta, -FollowPagination, auto-refresh on 401, Retry-After on 429.
- Removed Microsoft.Graph.Authentication as a RequiredModule. The module is now fully self-contained.
- SDK handoff is now opportunistic: if Microsoft.Graph.Authentication is installed we still hand
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
