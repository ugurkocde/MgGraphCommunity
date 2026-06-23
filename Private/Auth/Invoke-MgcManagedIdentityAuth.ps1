function Invoke-MgcManagedIdentityAuth {
    <#
    .SYNOPSIS
        Acquires a token via Azure Managed Identity.

    .DESCRIPTION
        Detects the runtime in this order:
          1. App Service / Functions / Container Apps (IDENTITY_ENDPOINT + IDENTITY_HEADER)
          2. Azure Arc (IMDS_ENDPOINT)
          3. IMDS - default Azure VM endpoint (169.254.169.254)

        For each, requests a token for the Graph resource. User-assigned identity is
        selected via -ManagedIdentityClientId.

        Returns a token response object normalized to the standard shape
        (access_token, expires_in, token_type, refresh_token=$null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GraphResource,
        [string]$ManagedIdentityClientId
    )

    $resource = $GraphResource
    $apiVer   = '2018-02-01'

    # 1. App Service / Functions / Container Apps
    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
        $uri = "$($env:IDENTITY_ENDPOINT)?resource=$([Uri]::EscapeDataString($resource))&api-version=2019-08-01"
        if ($ManagedIdentityClientId) {
            $uri += "&client_id=$([Uri]::EscapeDataString($ManagedIdentityClientId))"
        }
        $resp = Invoke-RestMethod -Uri $uri -Headers @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER } -Method GET
        return [pscustomobject]@{
            access_token  = $resp.access_token
            expires_in    = if ($resp.expires_in) { [int]$resp.expires_in } else { 3500 }
            token_type    = if ($resp.token_type) { $resp.token_type } else { 'Bearer' }
            refresh_token = $null
        }
    }

    # 2. Azure Arc
    if ($env:IMDS_ENDPOINT -and $env:IDENTITY_ENDPOINT) {
        $uri = "$($env:IDENTITY_ENDPOINT)?resource=$([Uri]::EscapeDataString($resource))&api-version=2019-11-01"
        $first = Invoke-MgcHttpRequest -Parameters @{
            Uri     = $uri
            Headers = @{ Metadata = 'true' }
            Method  = 'GET'
        }
        # Arc returns 401 + WWW-Authenticate header pointing at a challenge file
        if ($first.StatusCode -eq 401) {
            $authHeader = $first.Headers['WWW-Authenticate']
            if ($authHeader -match 'Basic realm=(.+)') {
                $challengePath = $Matches[1].Trim()
                # Only read the Arc agent's expected challenge location: a small
                # .key file inside the agent's Tokens directory. Anything else in
                # the header must not coerce us into disclosing arbitrary files.
                $expectedDir = if (Test-MgcIsWindows) {
                    Join-Path $env:ProgramData 'AzureConnectedMachineAgent\Tokens'
                } else {
                    '/var/opt/azcmagent/tokens'
                }
                $resolvedPath = [System.IO.Path]::GetFullPath($challengePath)
                $expectedPrefix = [System.IO.Path]::GetFullPath($expectedDir).TrimEnd('\','/') + [System.IO.Path]::DirectorySeparatorChar
                if (-not $resolvedPath.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
                    [System.IO.Path]::GetExtension($resolvedPath) -ne '.key') {
                    throw "Azure Arc challenge path '$challengePath' is outside the expected Arc tokens directory - refusing to read it."
                }
                $challengeFile = Get-Item -LiteralPath $resolvedPath
                if ($challengeFile.Length -gt 4096) {
                    throw "Azure Arc challenge file is unexpectedly large - refusing to read it."
                }
                $secret = Get-Content -LiteralPath $resolvedPath -Raw
                $resp = Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true'; Authorization = "Basic $secret" } -Method GET
                return [pscustomobject]@{
                    access_token  = $resp.access_token
                    expires_in    = if ($resp.expires_in) { [int]$resp.expires_in } else { 3500 }
                    token_type    = if ($resp.token_type) { $resp.token_type } else { 'Bearer' }
                    refresh_token = $null
                }
            }
        }
        throw "Azure Arc managed identity challenge failed."
    }

    # 3. IMDS (Azure VM)
    $imds = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$apiVer&resource=$([Uri]::EscapeDataString($resource))"
    if ($ManagedIdentityClientId) {
        $imds += "&client_id=$([Uri]::EscapeDataString($ManagedIdentityClientId))"
    }
    $resp = Invoke-RestMethod -Uri $imds -Headers @{ Metadata = 'true' } -Method GET -TimeoutSec 10
    return [pscustomobject]@{
        access_token  = $resp.access_token
        expires_in    = if ($resp.expires_in) { [int]$resp.expires_in } else { 3500 }
        token_type    = if ($resp.token_type) { $resp.token_type } else { 'Bearer' }
        refresh_token = $null
    }
}
