# Changelog

All notable changes to MgGraphCommunity are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-05-25

The module now runs on Windows PowerShell 5.1 in addition to PowerShell 7+.

### Added
- Windows PowerShell 5.1 support. Manifest declares `PowerShellVersion = '5.1'` and `CompatiblePSEditions = @('Desktop','Core')`.
- TLS 1.2 is auto-enabled on PowerShell 5.1 at module load (PS 5.1 still defaults to TLS 1.0/1.1 on most systems, which Graph rejects).
- New cross-version helpers: `Invoke-MgcHttpRequest` (abstracts `-SkipHttpErrorCheck`), `ConvertFrom-MgcSecureString` (BSTR marshal pattern for plaintext), `ConvertTo-MgcHashtable` (PS 5.1 fallback for `ConvertFrom-Json -AsHashtable`), `Test-MgcIsWindows` (replaces `$IsWindows`).

### Changed
- Replaced PS 7-only constructs throughout the codebase:
  - Null-coalescing (`??`) → first-non-empty helper in `Set-MgcConnectionContext`.
  - `[SHA256]::HashData`, `[SHA1]::HashData`, `[RandomNumberGenerator]::Fill` (PS 7.1+ static methods on .NET 5+) → `Create() + ComputeHash` / `Create() + GetBytes` (work on .NET Framework 4.x).
  - `ConvertFrom-SecureString -AsPlainText` → `ConvertFrom-MgcSecureString`.
  - `ConvertFrom-Json -AsHashtable` → falls back to `ConvertTo-MgcHashtable` on PS 5.1.
  - `Invoke-WebRequest -SkipHttpErrorCheck` → routed through `Invoke-MgcHttpRequest`.
  - `$IsWindows` → `Test-MgcIsWindows`.

### Notes
- All existing tests still pass on PowerShell 7+. The cross-version refactor is purely additive at the API level.

## [1.2.1] - 2026-05-25

### Fixed
- `Invoke-MgGraphCommunityRequest` crashed on PowerShell 7.4+ with `Cannot convert argument "bytes" ... to type System.Byte[]`. On PowerShell 7.4+, `Invoke-WebRequest`'s `Content` property is a string for text/JSON responses, not a byte array — calling `[Encoding]::UTF8.GetString($content)` blew up. The cmdlet now detects the shape of `Content` and handles both byte[] (PS 7.1–7.3) and string (PS 7.4+) responses. Same fix applied to the error-body parsing path.

## [1.2.0] - 2026-05-25

Hardens the request layer and cleans up the connect UX.

### Fixed
- `Invoke-MgGraphCommunityRequest` no longer uses `-StatusCodeVariable`, which was PowerShell 7.4+ only and broke the cmdlet on PS 7.0–7.3. Status is now read directly from the response object. Works on PowerShell 7.1+.

### Changed
- `Connect-MgGraphCommunity` no longer returns the context object to the pipeline. `-NoWelcome` now produces a truly silent connect. Use `Get-MgGraphCommunityContext` to retrieve the active connection details.
- Manifest `PowerShellVersion` bumped from `7.0` to `7.1` to honestly reflect the .NET 5+ static-method usage in PKCE/SHA-256 helpers.

### Added
- **Proactive token refresh.** When `Invoke-MgGraphCommunityRequest` runs, if the access token expires within 5 minutes, it refreshes silently before the call (in addition to the reactive 401-retry path that already existed). Eliminates the one wasted 401 in long-running scripts.
- **HTTP 504 Gateway Timeout retry.** Graph occasionally returns 504 under load; the cmdlet now sleeps 60 seconds and retries once.
- **Default headers**: `Add-MgGraphCommunityDefaultHeader`, `Remove-MgGraphCommunityDefaultHeader`, `Get-MgGraphCommunityDefaultHeader`. Set sticky headers for the session (e.g. `ConsistencyLevel: eventual`) without repeating `-Headers` on every call. Short aliases: `Add-MgcHeader`, `Remove-MgcHeader`, `Get-MgcHeader`. Per-call `-Headers` override defaults; default headers are cleared by `Disconnect-MgGraphCommunity`.
- New private helper `Get-MgcTokenExpiry` extracts the JWT `exp` claim (with `expires_in` fallback) and is used by both the proactive-refresh path and the active-session bookkeeping.

## [1.1.0] - 2026-05-25

The module is now fully self-contained — no required modules.

### Added
- **`Invoke-MgGraphCommunityRequest`** — a pure-PowerShell drop-in for `Invoke-MgGraphRequest`. Supports relative URIs (`/me`), full URLs, `-Beta`, `-FollowPagination` (walks `@odata.nextLink`), custom `-Body` (auto-JSON), custom `-Headers`, and `-OutputType PSObject|Hashtable|HttpResponse`.
- Auto-refresh on HTTP 401 (uses cached refresh token, retries once).
- Throttling support: honors `Retry-After` on HTTP 429.
- Clean error surfacing: Graph `error.code` and `error.message` are extracted into the PowerShell error.
- Short alias **`Invoke-MgcRequest`** for the new cmdlet.

### Changed
- **`Microsoft.Graph.Authentication` is no longer a required dependency.** Removed from `RequiredModules` in the manifest. `Install-Module MgGraphCommunity` installs nothing else now.
- SDK handoff is now opportunistic: if `Microsoft.Graph.Authentication` is installed in the session we still call `Connect-MgGraph -AccessToken` so existing SDK-based scripts continue to work. If it isn't installed, we silently skip the handoff — `Invoke-MgGraphCommunityRequest` works regardless.
- README quick start updated to use `Invoke-MgGraphCommunityRequest` instead of the SDK.

## [1.0.0] - 2026-05-25

Initial community release. Drop-in alternative to `Connect-MgGraph` with full flow parity, fixing the WAM-broken interactive sign-in.

### Added
- `Connect-MgGraphCommunity` with parameter sets for every flow `Connect-MgGraph` exposes:
  - Interactive (default) — Authorization Code + PKCE via system browser and loopback listener
  - DeviceCode (`-UseDeviceCode`)
  - ClientSecret (`-ClientSecretCredential`)
  - Certificate (`-Certificate`, `-CertificateThumbprint`, `-CertificateName`)
  - AccessToken (`-AccessToken`)
  - Managed Identity (`-Identity`, optional `-ManagedIdentityClientId`) — IMDS, App Service, and Azure Arc
- `Disconnect-MgGraphCommunity` (optionally `-ClearCache`)
- `Get-MgGraphCommunityContext` returning the active connection context
- `-Environment Global|USGov|USGovDoD|China` for sovereign clouds
- `-PersistRefreshToken` opt-in disk cache (DPAPI on Windows, `chmod 600` JSON elsewhere)
- In-memory token cache by default — no credentials written to disk unless explicitly opted in
- Silent refresh-token flow when a cached refresh token exists
- Pester smoke tests for PKCE generation, scope resolution, authority resolution, JWT decode, and cache round-trip
- Hands the access token to `Connect-MgGraph -AccessToken` so all `Microsoft.Graph.*` cmdlets keep working

### Notes
- Replaces the earlier standalone script (previously under `Connect-MgGraphViaBrowser/`), which has been removed in favor of the module structure.
- Not yet published to PowerShell Gallery — install from this repository via `Import-Module`. Gallery publish planned after live smoke-testing.
