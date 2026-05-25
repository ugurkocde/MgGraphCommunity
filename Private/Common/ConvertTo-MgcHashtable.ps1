function ConvertTo-MgcHashtable {
    <#
    .SYNOPSIS
        Converts ConvertFrom-Json output to a hashtable tree, cross-version safe.

    .DESCRIPTION
        PowerShell 6.0 added `ConvertFrom-Json -AsHashtable` which doesn't exist
        in Windows PowerShell 5.1. On 5.1 we get PSCustomObjects back from
        ConvertFrom-Json; this helper walks the tree and converts to hashtables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $h = @{}
            foreach ($k in $InputObject.Keys) {
                $h[$k] = ConvertTo-MgcHashtable -InputObject $InputObject[$k]
            }
            return $h
        }

        if ($InputObject -is [System.Array] -or ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string]))) {
            return ,@($InputObject | ForEach-Object { ConvertTo-MgcHashtable -InputObject $_ })
        }

        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $h = @{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $h[$prop.Name] = ConvertTo-MgcHashtable -InputObject $prop.Value
            }
            return $h
        }

        return $InputObject
    }
}
