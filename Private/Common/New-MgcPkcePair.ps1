function New-MgcPkcePair {
    <#
    .SYNOPSIS
        Generates a PKCE (RFC 7636) code verifier + S256 challenge pair.
    .OUTPUTS
        [pscustomobject] with .Verifier and .Challenge (base64url, unpadded)
    #>
    [CmdletBinding()]
    param()

    # Cross-version safe: use Create()+GetBytes / ComputeHash instead of PS 7.1+
    # static methods [RandomNumberGenerator]::Fill / [SHA256]::HashData (.NET 5+).
    $verifierBytes = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($verifierBytes) } finally { $rng.Dispose() }
    $verifier = [Convert]::ToBase64String($verifierBytes).TrimEnd('=').Replace('+','-').Replace('/','_')

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($verifier))
    } finally {
        $sha.Dispose()
    }
    $challenge = [Convert]::ToBase64String($hash).TrimEnd('=').Replace('+','-').Replace('/','_')

    return [pscustomobject]@{
        Verifier  = $verifier
        Challenge = $challenge
        Method    = 'S256'
    }
}
