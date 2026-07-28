function New-MgGraphCommunityAppRegistration {
    <#
    .SYNOPSIS
        Creates an Entra ID app registration ready for WAM-free MgGraphCommunity sign-in.

    .DESCRIPTION
        Creates a single-tenant public client application via Microsoft Graph
        (POST /v1.0/applications) configured for this module's Interactive (PKCE +
        loopback) and DeviceCode flows:

            signInAudience         = AzureADMyOrg
            isFallbackPublicClient = true
            publicClient redirect  = http://localhost  (matches any loopback port)

        No Graph permissions are pre-configured; the delegated flows request scopes
        dynamically and users consent at sign-in, exactly as with the built-in
        Microsoft client ID.

        Why this exists: Microsoft has announced changes to the default app used
        for delegated authentication (msgraph-sdk-powershell issue #3629). An app
        registration you own keeps your sign-ins independent of that change.

        Requires an active MgGraphCommunity connection whose token carries the
        delegated Application.ReadWrite.All scope:

            Connect-MgGraphCommunity -Scopes 'Application.ReadWrite.All'

        After creation the app is polled until it is readable via Graph. The very
        first sign-in can still take a minute or two while Entra ID propagates the
        new app to its token service; if you see "unauthorized_client", wait and retry.

    .PARAMETER DisplayName
        Display name for the new app registration. Defaults to 'MgGraphCommunity'.

    .PARAMETER AddWamRedirectUri
        Also add the WAM broker redirect URI
        (ms-appx-web://Microsoft.AAD.BrokerPlugin/{appId}) so the same app works
        with the official Microsoft.Graph SDK's WAM sign-in. MgGraphCommunity
        itself never uses WAM.

    .PARAMETER SetAsDefault
        Persist the new app's ClientId via Set-MgGraphCommunityDefaultClientId so
        future Connect-MgGraphCommunity calls use it automatically.

    .EXAMPLE
        Connect-MgGraphCommunity -Scopes 'Application.ReadWrite.All'
        New-MgGraphCommunityAppRegistration -SetAsDefault

    .EXAMPLE
        New-MgGraphCommunityAppRegistration -DisplayName 'Contoso Graph PowerShell' -AddWamRedirectUri

    .OUTPUTS
        [pscustomobject] with ClientId, ObjectId, DisplayName, TenantId, RedirectUris, SetAsDefault.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('New-MgcApp')]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName = 'MgGraphCommunity',

        [switch]$AddWamRedirectUri,

        [switch]$SetAsDefault
    )

    if (-not $script:MgcActiveSession) {
        throw "Not connected. Run Connect-MgGraphCommunity -Scopes 'Application.ReadWrite.All' first."
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Create Entra ID app registration')) { return }

    $payload = @{
        displayName            = $DisplayName
        signInAudience         = 'AzureADMyOrg'
        isFallbackPublicClient = $true
        publicClient           = @{
            # Plain http://localhost matches any loopback port, so the flow's
            # OS-assigned redirect port needs no fixed registration.
            redirectUris = @('http://localhost')
        }
    }

    $app = $null
    try {
        $app = Invoke-MgGraphCommunityRequest -Method POST -Uri '/applications' -V1 -Body $payload
    } catch {
        if ("$_" -match 'Authorization_RequestDenied|Insufficient privileges|403') {
            throw ("Creating the app registration was denied. The current token lacks the delegated " +
                   "Application.ReadWrite.All scope (or your account cannot create app registrations). " +
                   "Reconnect with: Connect-MgGraphCommunity -Scopes 'Application.ReadWrite.All'. Details: $_")
        }
        throw
    }

    $redirectUris = @('http://localhost')
    if ($AddWamRedirectUri) {
        # The WAM broker URI embeds the appId, so it can only be added after creation.
        $redirectUris += "ms-appx-web://Microsoft.AAD.BrokerPlugin/$($app.appId)"
        $null = Invoke-MgGraphCommunityRequest -Method PATCH -Uri "/applications/$($app.id)" -V1 -Body @{
            publicClient = @{ redirectUris = $redirectUris }
        }
    }

    # Directory propagation: poll until the app is readable by appId. Readable
    # here does not guarantee the token service knows it yet, but it is the best
    # signal Graph offers.
    $ready    = $false
    $deadline = (Get-Date).AddSeconds(60)
    while (-not $ready -and (Get-Date) -lt $deadline) {
        try {
            $null  = Invoke-MgGraphCommunityRequest -Method GET -Uri "/applications(appId='$($app.appId)')" -V1
            $ready = $true
        } catch {
            Start-Sleep -Seconds 3
        }
    }
    if (-not $ready) {
        Write-Warning "App created but not yet readable via Graph after 60s. It exists; propagation is still in progress."
    }

    if ($SetAsDefault) {
        Set-MgGraphCommunityDefaultClientId -ClientId $app.appId
    }

    [pscustomobject]@{
        ClientId     = $app.appId
        ObjectId     = $app.id
        DisplayName  = $app.displayName
        TenantId     = $script:MgcContext.TenantId
        RedirectUris = $redirectUris
        SetAsDefault = [bool]$SetAsDefault
    }
}
