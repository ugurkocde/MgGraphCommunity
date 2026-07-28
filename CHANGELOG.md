# Changelog

All notable changes to MgGraphCommunity are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-07-28

Resilience and parity release. Prepares for Microsoft's announced change to the default delegated-auth app ([msgraph-sdk-powershell #3629](https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3629)) and matches the CAE and sovereign cloud support the official SDK shipped in v2.36.0/v2.37.0. Fully backward compatible.

### Added
- **`New-MgGraphCommunityAppRegistration`** (alias `New-MgcApp`). Creates a single-tenant public client app registration ready for this module's WAM-free Interactive and DeviceCode flows (`signInAudience AzureADMyOrg`, `isFallbackPublicClient`, `http://localhost` loopback redirect, no pre-configured permissions, dynamic consent). Requires an active connection with the delegated `Application.ReadWrite.All` scope. `-AddWamRedirectUri` additionally registers the WAM broker redirect so the same app works with the official SDK; `-SetAsDefault` persists the new ClientId as this module's default.
- **`Set-MgGraphCommunityDefaultClientId`** (alias `Set-MgcDefaultClientId`). Persists a ClientId (in `config.json` next to the token cache) that `Connect-MgGraphCommunity` uses as its default for the Interactive and DeviceCode flows. Precedence: explicit `-ClientId` > saved default > built-in Microsoft client ID. `-Clear` removes the saved value.
- **Continuous Access Evaluation (CAE).** The delegated flows (Interactive, DeviceCode, silent refresh) now advertise the `CP1` client capability via the OAuth `claims` parameter, so Entra ID issues long-lived, revocable access tokens. When Graph answers 401 with a CAE claims challenge (`WWW-Authenticate ... claims="..."`), `Invoke-MgGraphCommunityRequest` decodes the challenge, silently re-acquires a token carrying those claims (merged with `CP1`), and retries the request exactly once; if silent re-acquisition fails, a clear reconnect error is thrown. Persisted cache entries record the CAE capability. App-only flows are unchanged: CAE for workload identities is a separate, narrower Microsoft feature that requires resource-side configuration.
- **Sovereign clouds** `BleuCloud` (France), `DelosCloud` (Germany) and `GovSGCloud` (Singapore) on `-Environment`. Endpoint values mirror the official SDK source (v2.36.0, PR #3523); these clouds are not live-tested by this project. The built-in first-party ClientId may not exist in sovereign clouds; pass `-ClientId` with a local app registration there.

## [1.4.0] - 2026-06-23

Feature release. Bundles the v1.3.1 bug fixes and security hardening (see below) plus new capabilities. New cmdlets and parameters; fully backward compatible.

### Added
- **Graph `$batch` support.** `Invoke-MgGraphCommunityBatch` (alias `Invoke-MgcBatch`) combines up to 20 requests per call into Microsoft Graph's JSON `$batch` endpoint. Larger sets are split into consecutive batches automatically. Throttled (HTTP 429) sub-responses are retried, honoring each sub-response's `Retry-After`. Returns one `{ id, status, headers, body }` object per submitted request, in submitted order. Supports `-Beta` and `dependsOn` sequencing.
- **Multi-connection switching.** `Connect-MgGraphCommunity` now registers every connection it establishes. `Select-MgGraphCommunityContext` (alias `Select-MgcContext`) switches the active connection by `-TenantId`, `-ClientId`, `-Index`, or `-CacheKey` without re-authenticating; `Get-MgGraphCommunityContext -ListAvailable` enumerates all live connections with an `IsActive` flag. The SDK handoff re-points at the newly active token on switch.
- **Binary upload/download** on `Invoke-MgGraphCommunityRequest`: `-InputFilePath` sends a file's raw bytes (uploads, e.g. `PUT .../photo/$value`), `-OutputFilePath` streams the raw response body to disk (downloads), and `-ContentType` sets the request media type (non-JSON bodies are sent as-is). Downloads read from `RawContentStream`, so they are binary-safe on PowerShell 5.1 and 7.x alike.
- **`-MaxRetry`** on `Invoke-MgGraphCommunityRequest` (default 3). Transient errors (429 / 503 / 504) are retried with backoff; `Retry-After` is honored when present.
- **Correlation IDs.** Every request now sends a `client-request-id`. Graph's `request-id` and `client-request-id` are included in thrown error messages so support tickets are actionable.

### Changed
- **Relative URIs now default to the `/beta` endpoint** instead of `/v1.0`. Beta exposes more of the Graph surface, which is what most of this module's audience reaches for. Pass `-V1` on `Invoke-MgGraphCommunityRequest` / `Invoke-MgGraphCommunityBatch` for the stable `/v1.0` endpoint; absolute URLs are unaffected (they carry their own version). The `-Beta` switch is retained for backward compatibility and now matches the default.
- Transient-error handling consolidated into a single bounded retry loop. Previously HTTP 429 and 504 were each retried exactly once and 503 was not retried; now all three retry up to `-MaxRetry` times with backoff.
- The AccessToken (BYO) flow derives its lifetime from the access token's JWT `exp` claim instead of assuming 3600 seconds. Opaque (non-JWT) tokens still fall back to 3600.

### Build
- PSScriptAnalyzer now runs in CI against `PSScriptAnalyzerSettings.psd1` (fails the build on Error-severity findings).

## [1.3.1] - 2026-06-09

Bug fixes and security hardening from a pre-announcement full review. No new cmdlets or parameters.

### Fixed
- **Certificate auth was broken in non-UTC timezones.** `New-MgcClientAssertion` computed the `nbf`/`exp` claims by round-tripping the Unix epoch through local time, skewing both by the machine's UTC offset (for example -1h in Central Europe, +5h US Eastern, -9h Japan). Entra ID rejected the assertion as expired or not yet valid for any offset beyond its clock-skew tolerance. The calculation was also locale-sensitive (`[double]::Parse` under comma-decimal cultures). Timestamps are now computed directly from a UTC epoch, timezone- and culture-safe.
- **Stray local requests no longer abort interactive sign-in.** A `favicon.ico` request or browser preconnect hitting the loopback listener before the OAuth callback used to consume the one `GetContext` call and fail the flow with a state mismatch. The listener now answers anything without `code`/`error` with HTTP 404 and keeps waiting (still within the overall 5-minute deadline).
- **Loopback port bind race.** The OS-assigned port from `Get-MgcFreePort` could be taken by another process before the `HttpListener` bound it. Auto-assigned ports now retry with a fresh port (up to 5 attempts); a user-specified `-RedirectPort` still gets exactly one attempt and a clear error.
- **`-FollowPagination` edge cases.** Pagination now keys on the presence of the `value` property instead of its truthiness: an empty first page with an `@odata.nextLink` is followed instead of silently dropped, and a single-page collection returns the same merged-array shape as a multi-page result.
- HTTP error responses on PowerShell 5.1 now dispose the response stream reliably (previously leaked if reading the error body threw).

### Security
- **Persisted cache stores the refresh token only.** The short-lived access token is no longer written to disk; the cache entry holds `refresh_token`, `token_type`, and `scope`. Existing cache files keep working.
- **Permissions before payload on macOS/Linux.** The cache file is created and restricted (`chmod 700` directory, `chmod 600` file) before the refresh token is written, removing the window where the default umask applied. If permissions cannot be restricted, the module now emits a visible warning instead of a verbose-only message.
- **CSRF `state` from a cryptographic RNG.** The interactive flow's `state` value now uses `RandomNumberGenerator` (same source as the PKCE verifier) instead of a GUID.
- **`Authorization` header cannot be clobbered.** The session bearer token is applied after default and per-call headers, and `Add-MgGraphCommunityDefaultHeader` rejects the name `Authorization`.
- **Azure Arc challenge path validation.** The file path from the Arc IMDS `WWW-Authenticate` header is only read if it resolves inside the Arc agent's tokens directory, ends in `.key`, and is small - matching the hardened Azure Identity SDK behavior.

### Changed
- Module load fails fast with a clear message on .NET Framework < 4.6 (Windows PowerShell 5.1 on Windows 7 / Server 2008 R2). The module's crypto and time APIs (`DateTimeOffset.FromUnixTimeSeconds`, `RSA.SignData`) require 4.6, which ships with Windows 10 / Server 2016 and newer.
- The browser result page now reflects the `state` validation result instead of only the presence of a `code`.
- Token cache file I/O uses explicit UTF-8.

## [1.3.0] - 2026-05-25

The module now runs on Windows PowerShell 5.1 in addition to PowerShell 7+.

### Added
- Windows PowerShell 5.1 support. Manifest declares `PowerShellVersion = '5.1'` and `CompatiblePSEditions = @('Desktop','Core')`.
- TLS 1.2 is auto-enabled on PowerShell 5.1 at module load (PS 5.1 still defaults to TLS 1.0/1.1 on most systems, which Graph rejects).
- New cross-version helpers: `Invoke-MgcHttpRequest` (abstracts `-SkipHttpErrorCheck`), `ConvertFrom-MgcSecureString` (BSTR marshal pattern for plaintext), `ConvertTo-MgcHashtable` (PS 5.1 fallback for `ConvertFrom-Json -AsHashtable`), `Test-MgcIsWindows` (replaces `$IsWindows`).

### Changed
- Replaced PS 7-only constructs throughout the codebase:
  - Null-coalescing (`??`) -> first-non-empty helper in `Set-MgcConnectionContext`.
  - `[SHA256]::HashData`, `[SHA1]::HashData`, `[RandomNumberGenerator]::Fill` (PS 7.1+ static methods on .NET 5+) -> `Create() + ComputeHash` / `Create() + GetBytes` (work on .NET Framework 4.x).
  - `ConvertFrom-SecureString -AsPlainText` -> `ConvertFrom-MgcSecureString`.
  - `ConvertFrom-Json -AsHashtable` -> falls back to `ConvertTo-MgcHashtable` on PS 5.1.
  - `Invoke-WebRequest -SkipHttpErrorCheck` -> routed through `Invoke-MgcHttpRequest`.
  - `$IsWindows` -> `Test-MgcIsWindows`.

### Notes
- All existing tests still pass on PowerShell 7+. The cross-version refactor is purely additive at the API level.

## [1.2.1] - 2026-05-25

### Fixed
- `Invoke-MgGraphCommunityRequest` crashed on PowerShell 7.4+ with `Cannot convert argument "bytes" ... to type System.Byte[]`. On PowerShell 7.4+, `Invoke-WebRequest`'s `Content` property is a string for text/JSON responses, not a byte array. Calling `[Encoding]::UTF8.GetString($content)` blew up. The cmdlet now detects the shape of `Content` and handles both byte[] (PS 7.1-7.3) and string (PS 7.4+) responses. Same fix applied to the error-body parsing path.

## [1.2.0] - 2026-05-25

Hardens the request layer and cleans up the connect UX.

### Fixed
- `Invoke-MgGraphCommunityRequest` no longer uses `-StatusCodeVariable`, which was PowerShell 7.4+ only and broke the cmdlet on PS 7.0-7.3. Status is now read directly from the response object. Works on PowerShell 7.1+.

### Changed
- `Connect-MgGraphCommunity` no longer returns the context object to the pipeline. `-NoWelcome` now produces a truly silent connect. Use `Get-MgGraphCommunityContext` to retrieve the active connection details.
- Manifest `PowerShellVersion` bumped from `7.0` to `7.1` to honestly reflect the .NET 5+ static-method usage in PKCE/SHA-256 helpers.

### Added
- **Proactive token refresh.** When `Invoke-MgGraphCommunityRequest` runs, if the access token expires within 5 minutes, it refreshes silently before the call (in addition to the reactive 401-retry path that already existed). Eliminates the one wasted 401 in long-running scripts.
- **HTTP 504 Gateway Timeout retry.** Graph occasionally returns 504 under load; the cmdlet now sleeps 60 seconds and retries once.
- **Default headers**: `Add-MgGraphCommunityDefaultHeader`, `Remove-MgGraphCommunityDefaultHeader`, `Get-MgGraphCommunityDefaultHeader`. Set sticky headers for the session (e.g. `ConsistencyLevel: eventual`) without repeating `-Headers` on every call. Short aliases: `Add-MgcHeader`, `Remove-MgcHeader`, `Get-MgcHeader`. Per-call `-Headers` override defaults; default headers are cleared by `Disconnect-MgGraphCommunity`.
- New private helper `Get-MgcTokenExpiry` extracts the JWT `exp` claim (with `expires_in` fallback) and is used by both the proactive-refresh path and the active-session bookkeeping.

## [1.1.0] - 2026-05-25

The module is now fully self-contained, with no required modules.

### Added
- **`Invoke-MgGraphCommunityRequest`**: a pure-PowerShell drop-in for `Invoke-MgGraphRequest`. Supports relative URIs (`/me`), full URLs, `-Beta`, `-FollowPagination` (walks `@odata.nextLink`), custom `-Body` (auto-JSON), custom `-Headers`, and `-OutputType PSObject|Hashtable|HttpResponse`.
- Auto-refresh on HTTP 401 (uses cached refresh token, retries once).
- Throttling support: honors `Retry-After` on HTTP 429.
- Clean error surfacing: Graph `error.code` and `error.message` are extracted into the PowerShell error.
- Short alias **`Invoke-MgcRequest`** for the new cmdlet.

### Changed
- **`Microsoft.Graph.Authentication` is no longer a required dependency.** Removed from `RequiredModules` in the manifest. `Install-Module MgGraphCommunity` installs nothing else now.
- SDK handoff is now opportunistic: if `Microsoft.Graph.Authentication` is installed in the session we still call `Connect-MgGraph -AccessToken` so existing SDK-based scripts continue to work. If it isn't installed, we silently skip the handoff, and `Invoke-MgGraphCommunityRequest` works regardless.
- README quick start updated to use `Invoke-MgGraphCommunityRequest` instead of the SDK.

## [1.0.0] - 2026-05-25

Initial community release. Drop-in alternative to `Connect-MgGraph` with full flow parity, fixing the WAM-broken interactive sign-in.

### Added
- `Connect-MgGraphCommunity` with parameter sets for every flow `Connect-MgGraph` exposes:
  - Interactive (default): Authorization Code + PKCE via system browser and loopback listener
  - DeviceCode (`-UseDeviceCode`)
  - ClientSecret (`-ClientSecretCredential`)
  - Certificate (`-Certificate`, `-CertificateThumbprint`, `-CertificateName`)
  - AccessToken (`-AccessToken`)
  - Managed Identity (`-Identity`, optional `-ManagedIdentityClientId`): IMDS, App Service, and Azure Arc
- `Disconnect-MgGraphCommunity` (optionally `-ClearCache`)
- `Get-MgGraphCommunityContext` returning the active connection context
- `-Environment Global|USGov|USGovDoD|China` for sovereign clouds
- `-PersistRefreshToken` opt-in disk cache (DPAPI on Windows, `chmod 600` JSON elsewhere)
- In-memory token cache by default; no credentials written to disk unless explicitly opted in
- Silent refresh-token flow when a cached refresh token exists
- Pester smoke tests for PKCE generation, scope resolution, authority resolution, JWT decode, and cache round-trip
- Hands the access token to `Connect-MgGraph -AccessToken` so all `Microsoft.Graph.*` cmdlets keep working

### Notes
- Replaces the earlier standalone script (previously under `Connect-MgGraphViaBrowser/`), which has been removed in favor of the module structure.
- Not yet published to PowerShell Gallery; install from this repository via `Import-Module`. Gallery publish planned after live smoke-testing.
