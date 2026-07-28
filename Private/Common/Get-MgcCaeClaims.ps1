function Get-MgcCaeClaims {
    <#
    .SYNOPSIS
        Builds the OAuth 'claims' parameter for Continuous Access Evaluation (CAE).

    .DESCRIPTION
        With no arguments, returns the client-capabilities claims JSON that opts a
        token request into CAE ({"access_token":{"xms_cc":{"values":["CP1"]}}}).
        CP1 tells Entra ID this client can handle claims challenges, which in turn
        yields long-lived, revocable access tokens.

        When -ChallengeClaims is supplied (the decoded claims JSON from a Graph 401
        WWW-Authenticate claims challenge), the xms_cc capability is merged into the
        challenge's access_token object so the retry both satisfies the challenge
        and stays CAE-capable.

    .PARAMETER ChallengeClaims
        Decoded claims JSON from a claims challenge (see Get-MgcClaimsChallenge).

    .OUTPUTS
        [string] Compact claims JSON for the 'claims' form/query parameter.
    #>
    [CmdletBinding()]
    param(
        [string]$ChallengeClaims
    )

    if (-not $ChallengeClaims) {
        return '{"access_token":{"xms_cc":{"values":["CP1"]}}}'
    }

    try {
        $parsed = $ChallengeClaims | ConvertFrom-Json
        if (-not $parsed.PSObject.Properties['access_token']) {
            $parsed | Add-Member -NotePropertyName access_token -NotePropertyValue ([pscustomobject]@{})
        }
        if (-not $parsed.access_token.PSObject.Properties['xms_cc']) {
            $parsed.access_token | Add-Member -NotePropertyName xms_cc `
                -NotePropertyValue ([pscustomobject]@{ values = @('CP1') })
        }
        return ($parsed | ConvertTo-Json -Depth 10 -Compress)
    } catch {
        # Unparseable challenge: send it untouched rather than dropping it.
        Write-Verbose "Claims challenge JSON merge failed, using challenge as-is: $_"
        return $ChallengeClaims
    }
}
