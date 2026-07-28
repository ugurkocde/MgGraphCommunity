function Set-MgGraphCommunityDefaultClientId {
    <#
    .SYNOPSIS
        Persists (or clears) the default ClientId used by Connect-MgGraphCommunity.

    .DESCRIPTION
        Saves a ClientId to config.json next to the token cache. From then on,
        Connect-MgGraphCommunity uses it as the default for the Interactive and
        DeviceCode flows instead of Microsoft's built-in client ID
        (14d82eec-204b-4c2f-b7e8-296a70dab67e). An explicit -ClientId on
        Connect-MgGraphCommunity always wins over the saved default.

        Use -Clear to remove the saved value and restore the built-in default.

        Why this exists: Microsoft has announced changes to the default app used
        for delegated authentication (msgraph-sdk-powershell issue #3629). Saving
        your own app registration's ClientId here keeps your sign-ins independent
        of that app. Create one with New-MgGraphCommunityAppRegistration.

    .PARAMETER ClientId
        The application (client) ID to persist as the default.

    .PARAMETER Clear
        Removes the saved default, restoring the built-in Microsoft client ID.

    .EXAMPLE
        Set-MgGraphCommunityDefaultClientId -ClientId '00000000-0000-0000-0000-000000000000'

    .EXAMPLE
        Set-MgGraphCommunityDefaultClientId -Clear
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('Set-MgcDefaultClientId')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Set')]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string]$ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Clear')]
        [switch]$Clear
    )

    $configDir  = Get-MgcAppDataDir
    $configFile = Join-Path $configDir 'config.json'

    if ($Clear) {
        if (-not (Test-Path $configFile)) { return }
        if (-not $PSCmdlet.ShouldProcess($configFile, 'Remove saved default ClientId')) { return }
        try {
            $config = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $config.PSObject.Properties.Remove('defaultClientId')
            if (@($config.PSObject.Properties).Count -eq 0) {
                Remove-Item -Path $configFile -Force
            } else {
                $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile -NoNewline -Encoding UTF8
            }
        } catch {
            # Unreadable config only held settings this module wrote; safe to reset.
            Remove-Item -Path $configFile -Force -ErrorAction SilentlyContinue
        }
        Write-Verbose "Default ClientId cleared; the built-in Microsoft client ID is active again."
        return
    }

    if (-not $PSCmdlet.ShouldProcess($configFile, "Save default ClientId $ClientId")) { return }

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config = [pscustomobject]@{}
    if (Test-Path $configFile) {
        try { $config = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-Verbose "Existing config unreadable, starting fresh: $_" }
    }
    if ($config.PSObject.Properties['defaultClientId']) {
        $config.defaultClientId = $ClientId
    } else {
        $config | Add-Member -NotePropertyName defaultClientId -NotePropertyValue $ClientId
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile -NoNewline -Encoding UTF8

    Write-Verbose "Saved default ClientId $ClientId. Connect-MgGraphCommunity will use it unless -ClientId is passed explicitly."
}
