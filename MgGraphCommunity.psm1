# Module root: dot-sources Private (load order matters) and Public (autodetect).
# Only Public functions are exported via the manifest. Supports Windows PowerShell 5.1 and PowerShell 7+.

$ErrorActionPreference = 'Stop'

# Force TLS 1.2 on Windows PowerShell 5.1, which still defaults to TLS 1.0/1.1
# (Microsoft Graph token + Graph endpoints require TLS 1.2 minimum).
if ($PSVersionTable.PSEdition -eq 'Desktop') {
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
    -Alias    @('Invoke-MgcRequest','Add-MgcHeader','Remove-MgcHeader','Get-MgcHeader')
