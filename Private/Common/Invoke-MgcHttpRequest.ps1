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
          - StatusCode:   [int] HTTP status code
          - Headers:      hashtable of response headers
          - Content:      string (decoded UTF-8) of the response body
          - ContentBytes: [byte[]] raw response body (only when -ReturnBytes), for
                          binary-correct downloads across PS 5.1 / 7.x.

    .PARAMETER Parameters
        Hashtable of parameters to pass to Invoke-WebRequest (Uri, Method, Headers, Body, etc.).
        Do NOT set SkipHttpErrorCheck or ErrorAction - this helper manages those.

    .PARAMETER ReturnBytes
        Capture the raw response body as a [byte[]] in ContentBytes (read from
        RawContentStream, which is binary-safe on every PowerShell version, unlike
        the .Content property which is a string on PS 7.4+). On success Content is
        left $null to avoid materializing large downloads as a string; on an error
        status the bytes are also decoded into Content so the caller can surface the
        Graph error body.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Parameters,
        [switch]$ReturnBytes
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

    # RawContentStream is a MemoryStream on both PS 5.1 and 7.x and holds the
    # undecoded bytes - the only version-safe source for binary downloads.
    $streamToBytes = {
        param($resp)
        $stream = $resp.RawContentStream
        if (-not $stream) { return $null }
        try {
            $ms = New-Object System.IO.MemoryStream
            if ($stream.CanSeek) { $stream.Position = 0 }
            $stream.CopyTo($ms)
            return $ms.ToArray()
        } finally {
            if ($ms) { $ms.Dispose() }
        }
    }

    $buildResult = {
        param($resp)
        $status = [int]$resp.StatusCode
        if ($ReturnBytes) {
            $bytes   = & $streamToBytes $resp
            # Decode to string only on error so the caller can surface the Graph
            # error body; success keeps Content $null to avoid huge strings.
            $content = if ($status -ge 400 -and $bytes) { [System.Text.Encoding]::UTF8.GetString($bytes) } else { $null }
            return [pscustomobject]@{
                StatusCode   = $status
                Headers      = (& $headersToHashtable $resp.Headers)
                Content      = $content
                ContentBytes = $bytes
            }
        }
        return [pscustomobject]@{
            StatusCode   = $status
            Headers      = (& $headersToHashtable $resp.Headers)
            Content      = (& $bodyToString $resp.Content)
            ContentBytes = $null
        }
    }

    if ($useSkipFlag) {
        $Parameters['SkipHttpErrorCheck'] = $true
        $Parameters['ErrorAction']        = 'Stop'
        $resp = Invoke-WebRequest @Parameters
        return (& $buildResult $resp)
    }

    # Windows PowerShell 5.1 path: throws on 4xx/5xx, catch and extract.
    try {
        $Parameters['ErrorAction'] = 'Stop'
        $resp = Invoke-WebRequest @Parameters
        return (& $buildResult $resp)
    } catch [System.Net.WebException] {
        $errResp = $_.Exception.Response
        if (-not $errResp) { throw }

        $statusCode = [int]$errResp.StatusCode

        $body   = $null
        $stream = $null
        $reader = $null
        try {
            $stream = $errResp.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                $body = $reader.ReadToEnd()
            }
        } catch {
        } finally {
            if ($reader) { $reader.Dispose() }   # also disposes the stream
            elseif ($stream) { $stream.Dispose() }
        }

        $headers = & $headersToHashtable $errResp.Headers

        return [pscustomobject]@{
            StatusCode   = $statusCode
            Headers      = $headers
            Content      = $body
            ContentBytes = $null
        }
    }
}
