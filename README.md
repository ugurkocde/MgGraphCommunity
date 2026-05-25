<p align="center">
  <img src="assets/banner.svg" alt="MgGraphCommunity — A drop-in for Connect-MgGraph. No WAM. No MSAL. No SDK black box." width="100%">
</p>

<h1 align="center">MgGraphCommunity</h1>

<p align="center">
  A community-maintained, WAM-free drop-in alternative to <code>Connect-MgGraph</code>.
</p>

<p align="center">
  <a href="https://github.com/ugurkocde/MgGraphCommunity/actions/workflows/test.yml"><img alt="Tests" src="https://img.shields.io/github/actions/workflow/status/ugurkocde/MgGraphCommunity/test.yml?branch=main&label=tests&logo=github&style=flat-square"></a>
  <a href="https://www.powershellgallery.com/packages/MgGraphCommunity"><img alt="PowerShell Gallery version" src="https://img.shields.io/powershellgallery/v/MgGraphCommunity?color=2b6cb0&label=PSGallery&logo=powershell&logoColor=white&style=flat-square"></a>
  <a href="https://www.powershellgallery.com/packages/MgGraphCommunity"><img alt="PowerShell Gallery downloads" src="https://img.shields.io/powershellgallery/dt/MgGraphCommunity?color=4c9a2a&label=downloads&logo=powershell&logoColor=white&style=flat-square"></a>
  <a href="https://github.com/ugurkocde/MgGraphCommunity/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/ugurkocde/MgGraphCommunity?color=6c757d&style=flat-square"></a>
  <a href="https://learn.microsoft.com/powershell/scripting/install/installing-powershell"><img alt="PowerShell 7+" src="https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white&style=flat-square"></a>
</p>

> Same flows. Working interactive. Safer-by-default cache. No SDK black box.

## Quick start

```powershell
Install-Module MgGraphCommunity -Scope CurrentUser
Connect-MgGraphCommunity
Invoke-MgGraphCommunityRequest -Method GET -Uri "https://graph.microsoft.com/beta/me"
```

That's it. One install. Browser opens, you sign in, you call Graph. **No `Microsoft.Graph.*` modules required.**

> Use **double quotes** around the URI as a habit — Graph IDs use OData single quotes (`('user@contoso.com')`) which would otherwise close a single-quoted PowerShell string early.

> Already have `Microsoft.Graph.Authentication` installed? Your `Get-MgUser`, `Invoke-MgGraphRequest`, etc. keep working too — we hand off the token opportunistically.

## Why this exists

Starting in `Microsoft.Graph` v2.34, the SDK made the **Windows Account Manager (WAM)** the default broker for interactive sign-in on Windows. WAM is on by default on current Windows builds, and as a result `Connect-MgGraph` no longer behaves the way many admins rely on:

- Secondary / service accounts not registered on the local device fail or require full credentials (email + password + MFA) on every call.
- The classic interactive authorization-code flow (system browser, loopback redirect) is unreachable from the SDK's interactive path.
- For admins managing multiple tenants from one workstation, this is a real productivity and security regression.

**There was no announcement from Microsoft about this change.** No blog post, no release-notes call-out, no migration guide — it landed quietly and admins discovered it by way of broken workflows.

The most reliable record of what changed, why, and how the community and Microsoft engineers have been discussing it is this single GitHub issue:

> **<https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3481#issuecomment-3687499347>**

If you want context on the problem this module exists to solve, start there.

## What it does

`MgGraphCommunity` ships a single cmdlet, `Connect-MgGraphCommunity`, that supports every flow `Connect-MgGraph` supports — implemented as pure PowerShell against the Microsoft identity platform v2 endpoints. After acquiring a token it hands it to `Connect-MgGraph -AccessToken`, so all existing `Microsoft.Graph.*` cmdlets keep working unchanged.

| Flow                 | How to invoke                                               |
|----------------------|-------------------------------------------------------------|
| Interactive (PKCE)   | `Connect-MgGraphCommunity` *(default — no WAM)*             |
| Device Code          | `Connect-MgGraphCommunity -UseDeviceCode`                   |
| Client Secret        | `Connect-MgGraphCommunity -ClientSecretCredential $cred`    |
| Certificate (X509)   | `Connect-MgGraphCommunity -Certificate $cert`               |
| Certificate (Thumb)  | `Connect-MgGraphCommunity -CertificateThumbprint '...'`     |
| Certificate (Name)   | `Connect-MgGraphCommunity -CertificateName 'CN=...'`        |
| Access Token (BYO)   | `Connect-MgGraphCommunity -AccessToken $secure`             |
| Managed Identity     | `Connect-MgGraphCommunity -Identity`                        |

Sovereign clouds: pass `-Environment Global|USGov|USGovDoD|China`.

## Comparison

How MgGraphCommunity stacks up against the closest alternatives. This is the honest version — picking your tool should be a decision, not a sales pitch.

| | **Microsoft.Graph SDK** | **MSGraphRequest** | **MgGraphCommunity** |
|---|---|---|---|
| **What it is** | Official Microsoft SDK with typed cmdlets per endpoint | Community general-purpose Graph client | Auth + thin `Invoke` wrapper, drop-in for `Connect-MgGraph` |
| **WAM-free interactive sign-in (Windows)** | ❌ broken in v2.34+ | ✅ | ✅ |
| **Pure PowerShell** | ❌ depends on MSAL DLL | ✅ | ✅ |
| **Required modules** | none (per module) | none | **none** |
| **Auth flows** | All | All | All (Interactive, DeviceCode, ClientSecret, Certificate ×3, AccessToken, ManagedIdentity) |
| **Loopback listener safety** | n/a (MSAL) | **blocks forever** on `GetContext()` | async with 5-min timeout |
| **CSRF `state` validation** | inside MSAL | ✅ | ✅ |
| **Token cache default** | DPAPI via MSAL, no opt-out | in-memory only | **in-memory by default, opt-in DPAPI** |
| **Sovereign clouds at request layer** | ✅ | ❌ hardcoded `graph.microsoft.com` | ✅ Global / USGov / USGovDoD / China |
| **URI input** | full URL or relative | `-Resource` + `-APIVersion` (no full URL accepted) | full URL, relative path, or `-Beta` shortcut |
| **Pagination** | manual | **always on** | opt-in `-FollowPagination` |
| **Proactive token refresh** | ✅ (MSAL) | ✅ (10 min) | ✅ (5 min) |
| **Auto-retry on 401** | ✅ (MSAL) | n/a (proactive) | ✅ |
| **Throttling (429) retry** | ✅ | ✅ | ✅ |
| **Gateway timeout (504) retry** | ❌ | ✅ (60 s) | ✅ (60 s) |
| **Sticky session headers** | ❌ | ✅ `Add-AuthenticationHeaderItem` | ✅ `Add-MgGraphCommunityDefaultHeader` |
| **Graph error surfacing** | ✅ | ✅ | ✅ |
| **Typed cmdlets per endpoint** (`Get-MgUser`, etc.) | ✅ | ❌ | ❌ |
| **Compiled assemblies** | yes (MSAL) | none | none |
| **Cold start** | slow (MSAL load) | fast | fast |
| **Maturity** | official, years of development | community, ~5 years in production | community, brand new |

### When to pick which

- **Microsoft.Graph SDK** — pick when you want typed cmdlets per endpoint (`Get-MgUser`, `New-MgGroup`, ...), your interactive sign-in isn't broken (Linux/macOS, or you don't mind WAM), and you accept the always-on persistent token cache.
- **MSGraphRequest** — pick when you're already using it. The team has 5+ years of production trust; for most workloads it's solid. Just be aware that interactive listener blocks forever and sovereign clouds aren't supported in the request layer.
- **MgGraphCommunity** — pick when you want the smallest possible install (`Install-Module MgGraphCommunity` and nothing else), WAM-free interactive on Windows, dynamic scopes per call, sovereign-cloud support at every layer, and the safer-by-default in-memory cache posture. URIs match what you copy from the Graph Explorer browser network tab — no `-Resource` splitting required.

If you also need a permission-scanning tool with its own GUI, look at [M365Permissions](https://github.com/jflieben/M365Permissions) — different scope, but the same project philosophy.

## Requirements

- PowerShell 7.0 or later
- **That's it.** No `Microsoft.Graph.*` modules, no MSAL, no anything else.
- If `Microsoft.Graph.Authentication` happens to be installed in your session we hand off the token to `Connect-MgGraph` so existing SDK-based scripts (`Get-MgUser`, `Invoke-MgGraphRequest`, etc.) keep working — but this is purely a convenience, never required.

## Install (from this repo)

```powershell
git clone https://github.com/ugurkocde/MgGraphCommunity.git
Import-Module ./MgGraphCommunity/MgGraphCommunity.psd1
```

PowerShell Gallery publish coming after live smoke-testing.

## Usage

```powershell
# Basic interactive sign-in
Connect-MgGraphCommunity

# Specific tenant + Intune scopes
Connect-MgGraphCommunity `
    -TenantId 'contoso.onmicrosoft.com' `
    -Scopes   'User.Read','DeviceManagementConfiguration.Read.All','DeviceManagementManagedDevices.Read.All'

# Re-consent (e.g. when adding scopes)
Connect-MgGraphCommunity -Scopes 'NewScope.Read.All' -ForceConsent

# Persist refresh token to disk (silent re-auth across sessions)
Connect-MgGraphCommunity -PersistRefreshToken

# Call Graph endpoints directly (no SDK needed)
Invoke-MgGraphCommunityRequest -Method GET -Uri '/me'                    # relative URI (defaults to /v1.0)
Invoke-MgGraphCommunityRequest -Method GET -Uri '/me' -Beta              # /beta endpoint
Invoke-MgGraphCommunityRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'
Invoke-MgGraphCommunityRequest -Method GET -Uri '/users' -FollowPagination   # walks @odata.nextLink, returns all pages

# Create something
Invoke-MgGraphCommunityRequest -Method POST -Uri '/groups' -Body @{
    displayName     = 'Marketing'
    mailEnabled     = $false
    mailNickname    = 'marketing'
    securityEnabled = $true
}

# Short alias if you don't want to type the full name
Invoke-MgcRequest -Uri '/me'

# Tip: when a URL contains OData single quotes (most Graph IDs do), wrap the URI in
# double quotes so PowerShell doesn't terminate your string at the first single quote.
Invoke-MgGraphCommunityRequest -Method GET -Uri "/users('admin@contoso.com')"
Invoke-MgGraphCommunityRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('e81b1566-f49f-42df-bdc9-40c91a0eda25')"

# Sticky headers for the session (useful for ConsistencyLevel, Prefer, etc.)
Add-MgGraphCommunityDefaultHeader -Name 'ConsistencyLevel' -Value 'eventual'
Invoke-MgGraphCommunityRequest -Uri "/users?\$count=true&\$filter=startswith(displayName,'A')"
# Or via aliases
Add-MgcHeader 'Prefer' 'odata.maxpagesize=100'
Get-MgcHeader        # list everything currently sticky
Remove-MgcHeader 'Prefer'

# If you also have Microsoft.Graph.Authentication installed, the official cmdlets also work
Get-MgUser -Top 5
Invoke-MgGraphRequest -Method GET -Uri '/me'

# Disconnect (also clears in-memory cache)
Disconnect-MgGraphCommunity

# Disconnect + delete on-disk persisted refresh tokens
Disconnect-MgGraphCommunity -ClearCache
```

## Token cache & security posture

By default, the only place a refresh token lives is **in memory**, scoped to the PowerShell session. Close the shell and it's gone.

- `-PersistRefreshToken` opts in to disk persistence: DPAPI-encrypted on Windows (`%LOCALAPPDATA%\MgGraphCommunity\tokens.json`), restricted-permission JSON on macOS/Linux (`~/.local/share/MgGraphCommunity/tokens.json`).
- The cache key includes ClientId, TenantId, Authority, and ParameterSet, so multiple identities and flows coexist.
- `-NoCache` skips both layers for one call.
- `Disconnect-MgGraphCommunity -ClearCache` wipes the persisted file.

This is intentionally more conservative than Microsoft's SDK, which persists tokens via MSAL by default with no opt-out flag.

## Bring your own app registration

Pass `-ClientId` and `-TenantId` (and optionally `-RedirectPort`):

```powershell
Connect-MgGraphCommunity `
    -ClientId     '00000000-0000-0000-0000-000000000000' `
    -TenantId     'contoso.onmicrosoft.com' `
    -RedirectPort 1985
```

App reg setup:

1. Register a new application in Entra ID.
2. **Authentication → Add a platform → Mobile and desktop applications**: add `http://localhost` (or a specific `http://localhost:PORT`, in which case pass `-RedirectPort PORT`).
3. **API permissions**: add the delegated Graph scopes you need and grant admin consent if required.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Inspired by the OAuth Auth Code + PKCE loopback patterns in [MSGraphRequest](https://www.powershellgallery.com/packages/MSGraphRequest), [M365Permissions](https://github.com/jflieben/M365Permissions), and Mark Orr's [Entra-PIM](https://github.com/markorr321/Entra-PIM).
