function ConvertFrom-MgcSecureString {
    <#
    .SYNOPSIS
        Decrypts a SecureString to a plain string, cross-version safe.

    .DESCRIPTION
        PowerShell 7.0 added 'ConvertFrom-SecureString -AsPlainText' which doesn't
        exist on Windows PowerShell 5.1. This helper uses the classic Marshal BSTR
        round-trip pattern which works on every PowerShell version.

        The plaintext is briefly in unmanaged memory and then zero-freed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][securestring]$SecureString
    )

    $bstr = [System.IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}
