function Save-MgcTokenCache {
    <#
    .SYNOPSIS
        Stores tokens for a given cache key. In-memory by default; opt-in to disk.

    .PARAMETER Key
        Cache key, typically "{authority}|{clientId}|{tenantId}".

    .PARAMETER Tokens
        Token response object (must include refresh_token to be worth caching).

    .PARAMETER Persist
        If set, additionally write the entry to disk (DPAPI on Windows, chmod 600 elsewhere).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][object]$Tokens,
        [switch]$Persist
    )

    # In-memory store (always)
    $script:MgcMemoryCache[$Key] = $Tokens

    if (-not $Persist) { return }
    if (-not $Tokens.refresh_token) { return }

    $cacheDir  = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'MgGraphCommunity'
    $cacheFile = Join-Path $cacheDir 'tokens.json'

    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    # Persist the refresh token + minimal metadata only. The access token is
    # short-lived and never needed across sessions, so it stays off disk.
    $persistable = [pscustomobject]@{
        refresh_token = $Tokens.refresh_token
        token_type    = $Tokens.token_type
        scope         = $Tokens.scope
    }
    $payload = $persistable | ConvertTo-Json -Compress -Depth 5

    # Cross-version safe: Test-MgcIsWindows replaces $IsWindows (PS 6+ only).
    $onWindows = Test-MgcIsWindows
    if ($onWindows) {
        $secure    = ConvertTo-SecureString -String $payload -AsPlainText -Force
        $encrypted = ConvertFrom-SecureString -SecureString $secure
        $entry     = [pscustomobject]@{ encrypted = $true;  data = $encrypted; saved = (Get-Date).ToString('o') }
    } else {
        $entry     = [pscustomobject]@{ encrypted = $false; data = $payload;   saved = (Get-Date).ToString('o') }
    }

    $cache = @{}
    if (Test-Path $cacheFile) {
        try {
            $existing = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $existing.PSObject.Properties) { $cache[$prop.Name] = $prop.Value }
        } catch {
            Write-Verbose "Existing cache unreadable, starting fresh: $_"
        }
    }
    $cache[$Key] = $entry

    # On non-Windows the file holds the refresh token in plaintext, so restrict
    # permissions BEFORE the payload is written (a write-then-chmod leaves a
    # window where the default umask applies). Warn loudly if that fails.
    if (-not $onWindows) {
        $permsOk = $true
        try {
            & chmod 700 $cacheDir
            if ($LASTEXITCODE -ne 0) { $permsOk = $false }
            if (-not (Test-Path $cacheFile)) {
                New-Item -ItemType File -Path $cacheFile -Force | Out-Null
            }
            & chmod 600 $cacheFile
            if ($LASTEXITCODE -ne 0) { $permsOk = $false }
        } catch {
            $permsOk = $false
        }
        if (-not $permsOk) {
            Write-Warning "Could not restrict permissions on '$cacheFile'. The persisted refresh token may be readable by other local users."
        }
    }

    $cache | ConvertTo-Json -Depth 6 | Set-Content -Path $cacheFile -NoNewline -Encoding UTF8
}
