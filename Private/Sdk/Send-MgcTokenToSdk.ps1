function Send-MgcTokenToSdk {
    <#
    .SYNOPSIS
        Opportunistically hands an access token to Microsoft.Graph.Authentication so
        Microsoft.Graph.* cmdlets work, IF the SDK is installed.

    .DESCRIPTION
        MgGraphCommunity does not require the Microsoft.Graph SDK — it ships its own
        Invoke-MgGraphCommunityRequest. But if the user happens to have
        Microsoft.Graph.Authentication installed, we hand the token to Connect-MgGraph
        so existing SDK-based scripts keep working in the same session.

        If the SDK is not installed, this function returns silently. Nothing throws,
        nothing prompts the user to install another module.

    .PARAMETER AccessToken
        Raw access token string.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText','',
        Justification = 'Connect-MgGraph requires SecureString; token already in memory as plaintext.')]
    param(
        [Parameter(Mandatory)][string]$AccessToken
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Verbose "Microsoft.Graph.Authentication not installed — skipping SDK handoff. Use Invoke-MgGraphCommunityRequest to call Graph directly."
        return $false
    }

    try {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        $secure = ConvertTo-SecureString $AccessToken -AsPlainText -Force
        Connect-MgGraph -AccessToken $secure -NoWelcome -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Verbose "SDK handoff failed (non-fatal): $_"
        return $false
    }
}
