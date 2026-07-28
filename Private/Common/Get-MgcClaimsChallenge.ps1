function Get-MgcClaimsChallenge {
    <#
    .SYNOPSIS
        Extracts and decodes the claims challenge from a WWW-Authenticate header.

    .DESCRIPTION
        Continuous Access Evaluation revocations surface as HTTP 401 with a
        WWW-Authenticate header of the form:

            Bearer realm="", authorization_uri="...", error="insufficient_claims",
            claims="eyJhY2Nlc3NfdG9rZW4iOnsibmJmIjp7ImVzc2VudGlhbCI6dHJ1ZSwgLi4u"

        The claims value is Base64-encoded JSON. This helper returns the decoded
        JSON string, or $null when the header carries no claims challenge (an
        ordinary expired-token 401).

    .PARAMETER WwwAuthenticate
        The WWW-Authenticate header value(s) from the 401 response.

    .OUTPUTS
        [string] Decoded claims JSON, or $null.
    #>
    [CmdletBinding()]
    param(
        [object]$WwwAuthenticate
    )

    if (-not $WwwAuthenticate) { return $null }
    $header = ([array]$WwwAuthenticate) -join ' '

    if ($header -notmatch 'claims="([^"]+)"') { return $null }
    $encoded = $Matches[1]

    try {
        # Entra pads its Base64, but tolerate unpadded values too.
        $padded = $encoded.Replace('-','+').Replace('_','/')
        switch ($padded.Length % 4) {
            2 { $padded += '==' }
            3 { $padded += '=' }
        }
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded))
        $null = $json | ConvertFrom-Json   # validate it decodes to JSON
        return $json
    } catch {
        Write-Verbose "WWW-Authenticate claims value did not decode to JSON: $_"
        return $null
    }
}
