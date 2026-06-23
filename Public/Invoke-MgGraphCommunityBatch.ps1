function Invoke-MgGraphCommunityBatch {
    <#
    .SYNOPSIS
        Sends multiple Microsoft Graph requests in a single $batch call.

    .DESCRIPTION
        Combines up to 20 requests per call into Microsoft Graph's JSON $batch
        endpoint, reducing round-trips. More than 20 requests are split into
        consecutive batches automatically.

        Uses the active MgGraphCommunity session (auth, proactive/reactive refresh,
        and transient-error retry are inherited from Invoke-MgGraphCommunityRequest).

        Throttled sub-responses (HTTP 429 inside the batch) are retried automatically,
        honoring each sub-response's Retry-After, up to -MaxRetry rounds.

        Returns one response object per submitted request, in submitted order:
            id      - the request id (auto-assigned 1..N if you did not set one)
            status  - the sub-request HTTP status code
            headers - the sub-response headers
            body    - the parsed sub-response body

    .PARAMETER Requests
        The requests to batch. Each item is a hashtable or object with:
            Method    (required)  GET / POST / PUT / PATCH / DELETE
            Url       (required)  relative Graph URL, e.g. '/me' or '/users/{id}'
            Id        (optional)  correlation id; auto-assigned if omitted
            Body      (optional)  request body (objects are serialized to JSON)
            Headers   (optional)  per-request headers (Content-Type added for bodies)
            DependsOn (optional)  array of ids this request must run after

    .PARAMETER Beta
        Target the /beta $batch endpoint. Beta is already the default; retained for
        backward compatibility.

    .PARAMETER V1
        Target the stable /v1.0 $batch endpoint instead of the default /beta. Takes
        precedence over -Beta if both are supplied. Note this only sets the $batch
        endpoint version; each sub-request's own relative Url is resolved by Graph
        against that same version.

    .PARAMETER MaxRetry
        Maximum retry rounds for throttled (429) sub-responses. Default 3.

    .EXAMPLE
        $responses = Invoke-MgGraphCommunityBatch -Requests @(
            @{ Method = 'GET'; Url = '/me' },
            @{ Method = 'GET'; Url = '/me/memberOf' }
        )
        $responses[0].body.displayName

    .EXAMPLE
        Invoke-MgcBatch -Requests @(
            @{ Id = 'g'; Method = 'POST'; Url = '/groups'; Body = @{ displayName = 'X'; mailEnabled = $false; mailNickname = 'x'; securityEnabled = $true } }
        )
    #>
    [CmdletBinding()]
    [Alias('Invoke-MgcBatch')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object[]]$Requests,

        [switch]$Beta,

        [switch]$V1,

        [ValidateRange(0, 10)]
        [int]$MaxRetry = 3
    )

    if (-not $script:MgcActiveSession) {
        throw "Not connected. Run Connect-MgGraphCommunity first."
    }
    if ($Requests.Count -eq 0) { return @() }

    # Normalize each input into a Graph batch sub-request, assigning a stable id.
    $getProp = {
        param($item, [string]$name)
        if ($item -is [System.Collections.IDictionary]) {
            foreach ($k in $item.Keys) { if ("$k" -eq $name) { return $item[$k] } }
            return $null
        }
        $p = $item.PSObject.Properties[$name]
        if ($p) { return $p.Value }
        return $null
    }

    $normalized = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($req in $Requests) {
        $i++
        $method = & $getProp $req 'Method'
        $url    = & $getProp $req 'Url'
        if (-not $url) { $url = & $getProp $req 'Uri' }    # tolerate Uri as an alias
        if (-not $method) { throw "Batch request #$i is missing a Method." }
        if (-not $url)    { throw "Batch request #$i is missing a Url." }

        $id = & $getProp $req 'Id'
        if (-not $id) { $id = "$i" }
        $id = "$id"

        # Graph requires relative URLs in the batch body ('/me', not the absolute host).
        $relUrl = "$url"
        $relUrl = $relUrl -replace '^https?://[^/]+/(v1\.0|beta)', ''
        if ($relUrl -notmatch '^/') { $relUrl = "/$relUrl" }

        $entry = [ordered]@{
            id     = $id
            method = "$method".ToUpperInvariant()
            url    = $relUrl
        }

        $headers = & $getProp $req 'Headers'
        $body    = & $getProp $req 'Body'
        if ($null -ne $body) {
            $entry['body'] = $body
            # Graph requires a Content-Type header whenever a body is present.
            $h = @{}
            if ($headers) { foreach ($k in $headers.Keys) { $h[$k] = $headers[$k] } }
            if (-not ($h.Keys | Where-Object { "$_" -ieq 'Content-Type' })) {
                $h['Content-Type'] = 'application/json'
            }
            $entry['headers'] = $h
        } elseif ($headers) {
            $entry['headers'] = $headers
        }

        $dependsOn = & $getProp $req 'DependsOn'
        if ($dependsOn) { $entry['dependsOn'] = @($dependsOn | ForEach-Object { "$_" }) }

        $normalized.Add([pscustomobject]@{ Id = $id; Order = $i; Entry = $entry })
    }

    # Build an ABSOLUTE $batch URL. A relative '/beta/$batch' would be re-prefixed
    # with the version segment by Invoke-MgGraphCommunityRequest (-> /beta/beta/$batch).
    # Default to /beta (more surface area); -V1 opts down to the stable endpoint.
    $apiVer      = if ($V1) { 'v1.0' } else { 'beta' }
    $batchUri    = "$($script:MgcActiveSession.Authority.GraphResource)/$apiVer/`$batch"
    $resultsById = @{}

    # Send in chunks of 20 (Graph hard limit), retrying throttled sub-requests.
    for ($start = 0; $start -lt $normalized.Count; $start += 20) {
        $end   = [Math]::Min($start + 19, $normalized.Count - 1)
        $chunk = $normalized[$start..$end]

        # Map of id -> entry for this chunk; pending starts as every entry.
        $entriesById = @{}
        foreach ($n in $chunk) { $entriesById[$n.Id] = $n.Entry }
        $pendingIds = [System.Collections.Generic.List[string]]@($chunk | ForEach-Object { $_.Id })

        $round = 0
        while ($pendingIds.Count -gt 0) {
            $payload = @{ requests = @($pendingIds | ForEach-Object { $entriesById[$_] }) }

            $resp = Invoke-MgGraphCommunityRequest -Method POST -Uri $batchUri -Body $payload
            if ($null -eq $resp -or $null -eq $resp.responses) { break }

            $throttled = [System.Collections.Generic.List[string]]@()
            $maxRetryAfter = 0
            $sawRetryAfter = $false
            foreach ($r in @($resp.responses)) {
                $rid = "$($r.id)"
                if ($r.status -eq 429 -and $round -lt $MaxRetry) {
                    $throttled.Add($rid)
                    if ($r.headers) {
                        $raVal = $r.headers.'Retry-After'
                        if ($null -ne $raVal -and "$raVal" -ne '') {
                            try { $ra = [int]([array]$raVal)[0]; $sawRetryAfter = $true; if ($ra -gt $maxRetryAfter) { $maxRetryAfter = $ra } } catch { }
                        }
                    }
                } else {
                    $resultsById[$rid] = [pscustomobject]@{
                        id      = $rid
                        status  = $r.status
                        headers = $r.headers
                        body    = $r.body
                    }
                }
            }

            if ($throttled.Count -eq 0) { break }
            $round++
            $sleep = if ($sawRetryAfter) { $maxRetryAfter } else { [int][Math]::Min(60, [Math]::Pow(2, $round) * 2) }
            Write-Verbose ("Batch: {0} sub-request(s) throttled - retry round {1}/{2} after {3}s." -f $throttled.Count, $round, $MaxRetry, $sleep)
            Start-Sleep -Seconds ([Math]::Max(0, $sleep))
            $pendingIds = $throttled
        }
    }

    # Return in submitted order. Emit a null-status placeholder for any id Graph
    # never returned, so the output stays index-aligned with the input.
    return $normalized | ForEach-Object {
        if ($resultsById.ContainsKey($_.Id)) {
            $resultsById[$_.Id]
        } else {
            [pscustomobject]@{ id = $_.Id; status = $null; headers = $null; body = $null }
        }
    }
}
