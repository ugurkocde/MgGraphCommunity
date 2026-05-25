function Invoke-MgcHttpRequest {
    <#
    .SYNOPSIS
        Issues an HTTP request and returns a uniform response regardless of PS version.

    .DESCRIPTION
        PowerShell 7 added 'Invoke-WebRequest -SkipHttpErrorCheck' which suppresses
        the exception on 4xx/5xx and returns the response object. Windows PowerShell 5.1
        doesn't have that switch - it always throws on HTTP errors, and the response is
        available only via $_.Exception.Response (with a different shape).

        This helper unifies both behaviors. Returns a PSCustomObject with:
          - StatusCode: [int] HTTP status code
          - Headers:    hashtable of response headers
          - Content:    string (decoded UTF-8) of the response body

    .PARAMETER Parameters
        Hashtable of parameters to pass to Invoke-WebRequest (Uri, Method, Headers, Body, etc.).
        Do NOT set SkipHttpErrorCheck or ErrorAction - this helper manages those.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Parameters
    )

    $useSkipFlag = $PSVersionTable.PSVersion.Major -ge 7

    # PS 5.1's Invoke-WebRequest defaults to IE-based parsing which is slow + brittle.
    if (-not $useSkipFlag) {
        $Parameters['UseBasicParsing'] = $true
    }

    $bodyToString = {
        param($c)
        if ($null -eq $c) { return $null }
        if ($c -is [byte[]]) {
            if ($c.Length -eq 0) { return $null }
            return [System.Text.Encoding]::UTF8.GetString($c)
        }
        return [string]$c
    }

    $headersToHashtable = {
        param($h)
        $out = @{}
        if ($null -eq $h) { return $out }
        # PS 7 headers may be IDictionary-like or WebHeaderCollection
        if ($h -is [System.Collections.IDictionary]) {
            foreach ($k in $h.Keys) { $out[$k] = $h[$k] }
        } elseif ($h.AllKeys) {
            foreach ($k in $h.AllKeys) { $out[$k] = $h[$k] }
        }
        return $out
    }

    if ($useSkipFlag) {
        $Parameters['SkipHttpErrorCheck'] = $true
        $Parameters['ErrorAction']        = 'Stop'
        $resp = Invoke-WebRequest @Parameters

        return [pscustomobject]@{
            StatusCode = [int]$resp.StatusCode
            Headers    = (& $headersToHashtable $resp.Headers)
            Content    = (& $bodyToString $resp.Content)
        }
    }

    # Windows PowerShell 5.1 path: throws on 4xx/5xx, catch and extract.
    try {
        $Parameters['ErrorAction'] = 'Stop'
        $resp = Invoke-WebRequest @Parameters
        return [pscustomobject]@{
            StatusCode = [int]$resp.StatusCode
            Headers    = (& $headersToHashtable $resp.Headers)
            Content    = (& $bodyToString $resp.Content)
        }
    } catch [System.Net.WebException] {
        $errResp = $_.Exception.Response
        if (-not $errResp) { throw }

        $statusCode = [int]$errResp.StatusCode

        $body = $null
        try {
            $stream = $errResp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $body = $reader.ReadToEnd()
            $reader.Dispose()
            $stream.Dispose()
        } catch { }

        $headers = & $headersToHashtable $errResp.Headers

        return [pscustomobject]@{
            StatusCode = $statusCode
            Headers    = $headers
            Content    = $body
        }
    }
}
