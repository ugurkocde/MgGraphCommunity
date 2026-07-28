# Module root: dot-sources Private (load order matters) and Public (autodetect).
# Only Public functions are exported via the manifest. Supports Windows PowerShell 5.1 and PowerShell 7+.

$ErrorActionPreference = 'Stop'

# Force TLS 1.2 on Windows PowerShell 5.1, which still defaults to TLS 1.0/1.1
# (Microsoft Graph token + Graph endpoints require TLS 1.2 minimum).
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    # PS 5.1 can run on .NET Framework 4.5.x (WMF 5.1 on Windows 7 / Server 2008 R2),
    # where DateTimeOffset.FromUnixTimeSeconds and the RSA.SignData overloads this
    # module uses do not exist. Fail fast with a clear message instead of a cryptic
    # MethodNotFoundException in the middle of an auth flow.
    if (-not [System.DateTimeOffset].GetMethod('FromUnixTimeSeconds')) {
        throw "MgGraphCommunity requires .NET Framework 4.6 or later (preinstalled on Windows 10 / Server 2016 and newer). Install .NET Framework 4.6+ or use PowerShell 7."
    }
    try {
        $current = [System.Net.ServicePointManager]::SecurityProtocol
        if (-not ($current -band [System.Net.SecurityProtocolType]::Tls12)) {
            [System.Net.ServicePointManager]::SecurityProtocol = $current -bor [System.Net.SecurityProtocolType]::Tls12
        }
    } catch {
        Write-Verbose "Failed to set TLS 1.2 (non-fatal): $_"
    }
}

# In-memory connection + token cache state, scoped to the module session.
$script:MgcContext        = $null
$script:MgcMemoryCache    = @{}
$script:MgcActiveSession  = $null   # holds tokens + refresh metadata for the live session
$script:MgcSessions       = [ordered]@{}  # all live sessions, keyed by cache key (multi-connection switching)
$script:MgcDefaultHeaders = @{}     # sticky HTTP headers for Invoke-MgGraphCommunityRequest

# Load order: Common -> Cache -> State -> Sdk -> Auth -> Public
$privateFolders = @('Common','Cache','State','Sdk','Auth')
foreach ($folder in $privateFolders) {
    $path = Join-Path $PSScriptRoot "Private/$folder"
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' -File |
            Sort-Object Name |
            ForEach-Object { . $_.FullName }
    }
}

$publicPath = Join-Path $PSScriptRoot 'Public'
$publicFiles = @()
if (Test-Path $publicPath) {
    $publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -File | Sort-Object Name
    foreach ($f in $publicFiles) { . $f.FullName }
}

Export-ModuleMember `
    -Function ($publicFiles | ForEach-Object { $_.BaseName }) `
    -Alias    @('Invoke-MgcRequest','Add-MgcHeader','Remove-MgcHeader','Get-MgcHeader','Invoke-MgcBatch','Select-MgcContext','New-MgcApp','Set-MgcDefaultClientId')
