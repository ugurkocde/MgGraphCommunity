#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Smoke tests - pure unit, no live tenant calls.

BeforeAll {
    $script:ModuleRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    Import-Module (Join-Path $script:ModuleRoot 'MgGraphCommunity.psd1') -Force

    # Dot-source private helpers into this test scope for direct testing
    Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Private') -Recurse -Filter '*.ps1' |
        ForEach-Object { . $_.FullName }
}

Describe 'New-MgcPkcePair' {
    It 'returns a verifier and S256 challenge of the right shape' {
        $pair = New-MgcPkcePair
        $pair.Verifier  | Should -Match '^[A-Za-z0-9\-_]+$'
        $pair.Challenge | Should -Match '^[A-Za-z0-9\-_]+$'
        $pair.Method    | Should -Be 'S256'
        $pair.Verifier.Length  | Should -BeGreaterThan 40
        $pair.Challenge.Length | Should -Be 43   # SHA-256 base64url unpadded
    }

    It 'produces a unique pair each call' {
        $a = New-MgcPkcePair
        $b = New-MgcPkcePair
        $a.Verifier | Should -Not -Be $b.Verifier
    }
}

Describe 'Resolve-MgcAuthority' {
    It 'returns Global endpoints by default' {
        $a = Resolve-MgcAuthority
        $a.Login         | Should -Be 'https://login.microsoftonline.com'
        $a.GraphResource | Should -Be 'https://graph.microsoft.com'
    }

    It 'returns USGov endpoints' {
        $a = Resolve-MgcAuthority -Environment USGov
        $a.GraphResource | Should -Be 'https://graph.microsoft.us'
    }

    It 'returns China endpoints' {
        $a = Resolve-MgcAuthority -Environment China
        $a.Login         | Should -Be 'https://login.chinacloudapi.cn'
        $a.GraphResource | Should -Be 'https://microsoftgraph.chinacloudapi.cn'
    }
}

Describe 'Resolve-MgcScopes' {
    It 'auto-prefixes bare scopes with the Graph resource URI' {
        $s = Resolve-MgcScopes -Scopes 'User.Read','Mail.Read' -GraphResource 'https://graph.microsoft.com'
        $s | Should -Contain 'https://graph.microsoft.com/User.Read'
        $s | Should -Contain 'https://graph.microsoft.com/Mail.Read'
    }

    It 'always adds offline_access' {
        $s = Resolve-MgcScopes -Scopes 'User.Read' -GraphResource 'https://graph.microsoft.com'
        $s | Should -Contain 'offline_access'
    }

    It 'passes through fully-qualified scopes unchanged' {
        $s = Resolve-MgcScopes -Scopes 'https://graph.microsoft.com/.default' -GraphResource 'https://graph.microsoft.com'
        $s | Should -Contain 'https://graph.microsoft.com/.default'
    }

    It 'passes through OIDC scopes unchanged' {
        $s = Resolve-MgcScopes -Scopes 'openid','profile' -GraphResource 'https://graph.microsoft.com'
        $s | Should -Contain 'openid'
        $s | Should -Contain 'profile'
    }

    It 'defaults to User.Read when nothing supplied' {
        $s = Resolve-MgcScopes -Scopes @() -GraphResource 'https://graph.microsoft.com'
        $s | Should -Contain 'https://graph.microsoft.com/User.Read'
    }
}

Describe 'ConvertFrom-MgcJwt' {
    It 'decodes a known payload' {
        # Hand-crafted JWT: header={alg:none}, payload={sub:abc,upn:test@x.com}, sig=
        $header  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"alg":"none","typ":"JWT"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        $payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"sub":"abc","upn":"test@example.com","tid":"tenant-guid","exp":1700000000}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        $jwt = "$header.$payload."
        $decoded = ConvertFrom-MgcJwt -Token $jwt
        $decoded.sub | Should -Be 'abc'
        $decoded.upn | Should -Be 'test@example.com'
        $decoded.tid | Should -Be 'tenant-guid'
        $decoded.exp | Should -Be 1700000000
    }

    It 'throws on a malformed token' {
        { ConvertFrom-MgcJwt -Token 'not-a-jwt' } | Should -Throw
    }
}

Describe 'Token cache round-trip (in-memory)' {
    BeforeEach { Clear-MgcTokenCache }

    It 'stores and retrieves a token by key' {
        $tokens = [pscustomobject]@{ access_token = 'AT'; refresh_token = 'RT'; expires_in = 3600 }
        Save-MgcTokenCache -Key 'k1' -Tokens $tokens
        $back = Get-MgcTokenCacheEntry -Key 'k1'
        $back.access_token  | Should -Be 'AT'
        $back.refresh_token | Should -Be 'RT'
    }

    It 'returns null for unknown keys' {
        Get-MgcTokenCacheEntry -Key 'never-saved' | Should -BeNullOrEmpty
    }

    It 'Clear-MgcTokenCache empties the in-memory store' {
        Save-MgcTokenCache -Key 'k2' -Tokens ([pscustomobject]@{ access_token = 'x' })
        Clear-MgcTokenCache
        Get-MgcTokenCacheEntry -Key 'k2' | Should -BeNullOrEmpty
    }
}

Describe 'Module loads and exports the expected surface' {
    It 'exports all public functions' {
        $m = Get-Module MgGraphCommunity
        foreach ($name in @(
            'Connect-MgGraphCommunity',
            'Disconnect-MgGraphCommunity',
            'Get-MgGraphCommunityContext',
            'Invoke-MgGraphCommunityRequest',
            'Add-MgGraphCommunityDefaultHeader',
            'Remove-MgGraphCommunityDefaultHeader',
            'Get-MgGraphCommunityDefaultHeader'
        )) {
            $m.ExportedFunctions.Keys | Should -Contain $name
        }
    }

    It 'exports all short-form aliases' {
        $m = Get-Module MgGraphCommunity
        foreach ($alias in @('Invoke-MgcRequest','Add-MgcHeader','Remove-MgcHeader','Get-MgcHeader')) {
            $m.ExportedAliases.Keys | Should -Contain $alias
        }
    }

    It 'has no required modules in the manifest' {
        $manifest = Test-ModuleManifest -Path (Join-Path $script:ModuleRoot 'MgGraphCommunity.psd1')
        $manifest.RequiredModules.Count | Should -Be 0
    }
}

Describe 'Invoke-MgGraphCommunityRequest' {
    BeforeAll {
        $m = Get-Module MgGraphCommunity
        & $m { $script:MgcActiveSession = $null }
    }

    It 'throws a clear error when no session is active' {
        { Invoke-MgGraphCommunityRequest -Uri '/me' } | Should -Throw -ExpectedMessage '*Connect-MgGraphCommunity*'
    }
}

Describe 'Default headers' {
    BeforeEach {
        $m = Get-Module MgGraphCommunity
        & $m { $script:MgcDefaultHeaders = @{} }
    }

    It 'Add and Get round-trip' {
        Add-MgGraphCommunityDefaultHeader -Name 'ConsistencyLevel' -Value 'eventual'
        Get-MgGraphCommunityDefaultHeader -Name 'ConsistencyLevel' | Should -Be 'eventual'
    }

    It 'Get without -Name returns all headers as Name/Value objects' {
        Add-MgGraphCommunityDefaultHeader -Name 'A' -Value '1'
        Add-MgGraphCommunityDefaultHeader -Name 'B' -Value '2'
        $all = Get-MgGraphCommunityDefaultHeader
        ($all | Measure-Object).Count | Should -Be 2
        ($all | Where-Object Name -EQ 'A').Value | Should -Be '1'
    }

    It 'Remove deletes the header' {
        Add-MgGraphCommunityDefaultHeader -Name 'X' -Value 'y'
        Remove-MgGraphCommunityDefaultHeader -Name 'X'
        Get-MgGraphCommunityDefaultHeader -Name 'X' | Should -BeNullOrEmpty
    }

    It 'short aliases work' {
        Add-MgcHeader 'Prefer' 'odata.maxpagesize=100'
        (Get-MgcHeader 'Prefer') | Should -Be 'odata.maxpagesize=100'
        Remove-MgcHeader 'Prefer'
        Get-MgcHeader 'Prefer' | Should -BeNullOrEmpty
    }

    It 'Add overwrites an existing value (set semantics)' {
        Add-MgGraphCommunityDefaultHeader -Name 'K' -Value 'v1'
        Add-MgGraphCommunityDefaultHeader -Name 'K' -Value 'v2'
        Get-MgGraphCommunityDefaultHeader -Name 'K' | Should -Be 'v2'
    }

    It 'refuses to set Authorization as a default header' {
        { Add-MgGraphCommunityDefaultHeader -Name 'Authorization' -Value 'Bearer x' } |
            Should -Throw -ExpectedMessage '*managed by the module*'
    }
}

Describe 'New-MgcClientAssertion' {
    BeforeAll {
        # CertificateRequest is .NET Framework 4.7.2+ / .NET Core 2+. Skip cleanly
        # where unavailable rather than failing discovery.
        $script:certReqType = 'System.Security.Cryptography.X509Certificates.CertificateRequest' -as [type]
        if ($script:certReqType) {
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $req = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
                'CN=MgcAssertionTest', $rsa,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $script:testCert = $req.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddHours(1))
        }
    }

    It 'anchors nbf/exp to real UTC Unix time (no timezone or locale skew)' {
        if (-not $script:certReqType) { Set-ItResult -Skipped -Because 'CertificateRequest unavailable on this .NET'; return }
        $assertion = New-MgcClientAssertion -ClientId 'app-id' `
            -TokenEndpoint 'https://login.microsoftonline.com/tenant/oauth2/v2.0/token' `
            -Certificate $script:testCert
        $claims  = ConvertFrom-MgcJwt -Token $assertion
        $epoch   = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
        $nowUnix = [int64]([DateTime]::UtcNow - $epoch).TotalSeconds
        [Math]::Abs($claims.nbf - $nowUnix) | Should -BeLessThan 300
        ($claims.exp - $claims.nbf)         | Should -Be 600
        $claims.aud | Should -Be 'https://login.microsoftonline.com/tenant/oauth2/v2.0/token'
        $claims.iss | Should -Be 'app-id'
    }

    It 'produces an RS256 header with a base64url x5t thumbprint' {
        if (-not $script:certReqType) { Set-ItResult -Skipped -Because 'CertificateRequest unavailable on this .NET'; return }
        $assertion = New-MgcClientAssertion -ClientId 'app-id' `
            -TokenEndpoint 'https://login.microsoftonline.com/tenant/oauth2/v2.0/token' `
            -Certificate $script:testCert
        $segments = $assertion -split '\.'
        $segments.Count | Should -Be 3
        $headerB64 = $segments[0].Replace('-','+').Replace('_','/')
        switch ($headerB64.Length % 4) { 2 { $headerB64 += '==' }; 3 { $headerB64 += '=' } }
        $header = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($headerB64)) | ConvertFrom-Json
        $header.alg | Should -Be 'RS256'
        $header.x5t | Should -Match '^[A-Za-z0-9\-_]+$'
    }
}

Describe 'Invoke-MgGraphCommunityRequest pagination' {
    BeforeAll {
        $script:m = Get-Module MgGraphCommunity
        & $script:m {
            $script:MgcActiveSession = [pscustomobject]@{
                Tokens        = [pscustomobject]@{ access_token = 'AT'; refresh_token = $null }
                ExpiresOn     = (Get-Date).ToUniversalTime().AddHours(1)
                CacheKey      = 'test-key'
                Authority     = [pscustomobject]@{ Login = 'https://login.microsoftonline.com'; GraphResource = 'https://graph.microsoft.com' }
                ClientId      = 'test-client'
                TenantSegment = 'common'
                Scopes        = @('User.Read')
                FlowType      = 'Test'
                Persist       = $false
            }
        }
    }

    AfterAll {
        & $script:m { $script:MgcActiveSession = $null }
    }

    It 'merges value arrays across pages with -FollowPagination' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            if ($Parameters['Uri'] -like '*page2*') {
                [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{"value":[{"id":3}]}' }
            } else {
                [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{"value":[{"id":1},{"id":2}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users?page2"}' }
            }
        }
        $result = Invoke-MgGraphCommunityRequest -Uri '/users' -FollowPagination
        $result.Count | Should -Be 3
        $result[2].id | Should -Be 3
    }

    It 'returns the merged array shape even for a single page (no nextLink)' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{"value":[{"id":1}]}' }
        }
        $result = @(Invoke-MgGraphCommunityRequest -Uri '/users' -FollowPagination)
        $result.Count | Should -Be 1
        $result[0].id | Should -Be 1
    }

    It 'follows nextLink even when the first page has an empty value array' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            if ($Parameters['Uri'] -like '*page2*') {
                [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{"value":[{"id":9}]}' }
            } else {
                [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{"value":[],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users?page2"}' }
            }
        }
        $result = @(Invoke-MgGraphCommunityRequest -Uri '/users' -FollowPagination)
        $result.Count | Should -Be 1
        $result[0].id | Should -Be 9
    }

    It 'does not let a custom header overwrite Authorization' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $auth = $Parameters['Headers']['Authorization']
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = ('{"echoedAuth":"' + $auth + '"}') }
        }
        $result = Invoke-MgGraphCommunityRequest -Uri '/me' -Headers @{ authorization = 'Bearer attacker' }
        $result.echoedAuth | Should -Be 'Bearer AT'
    }
}

Describe 'Module exports the v1.4.0 surface' {
    It 'exports the new functions' {
        $m = Get-Module MgGraphCommunity
        foreach ($name in @('Select-MgGraphCommunityContext','Invoke-MgGraphCommunityBatch')) {
            $m.ExportedFunctions.Keys | Should -Contain $name
        }
    }
    It 'exports the new aliases' {
        $m = Get-Module MgGraphCommunity
        foreach ($alias in @('Invoke-MgcBatch','Select-MgcContext')) {
            $m.ExportedAliases.Keys | Should -Contain $alias
        }
    }
}

Describe 'Invoke-MgGraphCommunityRequest transient retry + correlation IDs' {
    BeforeAll {
        $script:m = Get-Module MgGraphCommunity
        & $script:m {
            $script:MgcActiveSession = [pscustomobject]@{
                Tokens        = [pscustomobject]@{ access_token = 'AT'; refresh_token = $null }
                ExpiresOn     = (Get-Date).ToUniversalTime().AddHours(1)
                CacheKey      = 'test-key'
                Authority     = [pscustomobject]@{ Login = 'https://login.microsoftonline.com'; GraphResource = 'https://graph.microsoft.com' }
                ClientId      = 'test-client'
                TenantSegment = 'common'
                Scopes        = @('User.Read')
                FlowType      = 'Test'
                Persist       = $false
            }
        }
    }
    AfterAll { & $script:m { $script:MgcActiveSession = $null } }

    It 'retries 503 with Retry-After then succeeds' {
        $script:calls = 0
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $script:calls++
            if ($script:calls -eq 1) {
                [pscustomobject]@{ StatusCode = 503; Headers = @{ 'Retry-After' = '0' }; Content = '{}'; ContentBytes = $null }
            } else {
                [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{"ok":true}'; ContentBytes = $null }
            }
        }
        $r = Invoke-MgGraphCommunityRequest -Uri '/me'
        $r.ok | Should -BeTrue
        $script:calls | Should -Be 2
    }

    It 'stops retrying after -MaxRetry attempts' {
        $script:calls = 0
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $script:calls++
            [pscustomobject]@{ StatusCode = 429; Headers = @{ 'Retry-After' = '0' }; Content = '{"error":{"code":"tooManyRequests","message":"slow down"}}'; ContentBytes = $null }
        }
        { Invoke-MgGraphCommunityRequest -Uri '/me' -MaxRetry 2 } | Should -Throw
        $script:calls | Should -Be 3   # 1 initial + 2 retries
    }

    It 'includes the Graph request-id in thrown errors' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            [pscustomobject]@{ StatusCode = 403; Headers = @{ 'request-id' = 'abc-123'; 'Content-Type' = 'application/json' }; Content = '{"error":{"code":"forbidden","message":"no"}}'; ContentBytes = $null }
        }
        { Invoke-MgGraphCommunityRequest -Uri '/me' } | Should -Throw -ExpectedMessage '*request-id: abc-123*'
    }

    It 'sends a client-request-id header' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $cid = $Parameters['Headers']['client-request-id']
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = ('{"cid":"' + $cid + '"}'); ContentBytes = $null }
        }
        $r = Invoke-MgGraphCommunityRequest -Uri '/me'
        $r.cid | Should -Match '^[0-9a-fA-F-]{36}$'
    }

    It 'resolves relative URIs to /beta by default and /v1.0 with -V1' {
        $script:seenUri = $null
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $script:seenUri = $Parameters['Uri']
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{}'; ContentBytes = $null }
        }
        Invoke-MgGraphCommunityRequest -Uri '/me' | Out-Null
        $script:seenUri | Should -Be 'https://graph.microsoft.com/beta/me'
        Invoke-MgGraphCommunityRequest -Uri '/me' -V1 | Out-Null
        $script:seenUri | Should -Be 'https://graph.microsoft.com/v1.0/me'
        Invoke-MgGraphCommunityRequest -Uri '/me' -Beta | Out-Null
        $script:seenUri | Should -Be 'https://graph.microsoft.com/beta/me'
    }
}

Describe 'Invoke-MgGraphCommunityRequest binary I/O' {
    BeforeAll {
        $script:m = Get-Module MgGraphCommunity
        & $script:m {
            $script:MgcActiveSession = [pscustomobject]@{
                Tokens        = [pscustomobject]@{ access_token = 'AT'; refresh_token = $null }
                ExpiresOn     = (Get-Date).ToUniversalTime().AddHours(1)
                CacheKey      = 'test-key'
                Authority     = [pscustomobject]@{ Login = 'https://login.microsoftonline.com'; GraphResource = 'https://graph.microsoft.com' }
                ClientId      = 'test-client'
                TenantSegment = 'common'
                Scopes        = @('User.Read')
                FlowType      = 'Test'
                Persist       = $false
            }
        }
    }
    AfterAll { & $script:m { $script:MgcActiveSession = $null } }

    It 'writes raw response bytes to -OutputFilePath' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'image/png' }; Content = $null; ContentBytes = [byte[]](1,2,3,4,5) }
        }
        $out = Join-Path $TestDrive 'photo.png'
        Invoke-MgGraphCommunityRequest -Uri '/me/photo/$value' -OutputFilePath $out | Out-Null
        [System.IO.File]::ReadAllBytes($out) | Should -Be ([byte[]](1,2,3,4,5))
    }

    It 'sends a non-JSON body as-is with the given -ContentType' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            [pscustomobject]@{
                StatusCode = 200
                Headers    = @{ 'Content-Type' = 'application/json' }
                Content    = ('{"ct":"' + $Parameters['Headers']['Content-Type'] + '","body":"' + $Parameters['Body'] + '"}')
                ContentBytes = $null
            }
        }
        $r = Invoke-MgGraphCommunityRequest -Method PUT -Uri '/x' -Body 'plain-text' -ContentType 'text/plain'
        $r.ct   | Should -Be 'text/plain'
        $r.body | Should -Be 'plain-text'
    }
}

Describe 'Invoke-MgGraphCommunityBatch' {
    BeforeAll {
        $script:m = Get-Module MgGraphCommunity
        & $script:m {
            $script:MgcActiveSession = [pscustomobject]@{
                Tokens        = [pscustomobject]@{ access_token = 'AT'; refresh_token = $null }
                ExpiresOn     = (Get-Date).ToUniversalTime().AddHours(1)
                CacheKey      = 'test-key'
                Authority     = [pscustomobject]@{ Login = 'https://login.microsoftonline.com'; GraphResource = 'https://graph.microsoft.com' }
                ClientId      = 'test-client'
                TenantSegment = 'common'
                Scopes        = @('User.Read')
                FlowType      = 'Test'
                Persist       = $false
            }
        }
    }
    AfterAll { & $script:m { $script:MgcActiveSession = $null } }

    It 'auto-assigns ids and returns responses in submitted order' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $reqBody = $Parameters['Body'] | ConvertFrom-Json
            # Return responses out of order to prove we re-sort by id.
            $resps = $reqBody.requests | ForEach-Object { [pscustomobject]@{ id = $_.id; status = 200; headers = @{}; body = @{ url = $_.url } } }
            $resps = $resps | Sort-Object { [int]$_.id } -Descending
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = (@{ responses = $resps } | ConvertTo-Json -Depth 8); ContentBytes = $null }
        }
        $out = Invoke-MgGraphCommunityBatch -Requests @(
            @{ Method = 'GET'; Url = '/me' },
            @{ Method = 'GET'; Url = '/users' }
        )
        $out.Count       | Should -Be 2
        $out[0].id       | Should -Be '1'
        $out[0].body.url | Should -Be '/me'
        $out[1].id       | Should -Be '2'
        $out[1].body.url | Should -Be '/users'
    }

    It 'splits more than 20 requests into multiple batches' {
        $script:batchCalls = 0
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $script:batchCalls++
            $reqBody = $Parameters['Body'] | ConvertFrom-Json
            $reqBody.requests.Count | Should -BeLessOrEqual 20
            $resps = $reqBody.requests | ForEach-Object { [pscustomobject]@{ id = $_.id; status = 200; headers = @{}; body = @{} } }
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = (@{ responses = $resps } | ConvertTo-Json -Depth 8); ContentBytes = $null }
        }
        $requests = 1..45 | ForEach-Object { @{ Method = 'GET'; Url = "/users/$_" } }
        $out = Invoke-MgGraphCommunityBatch -Requests $requests
        $out.Count        | Should -Be 45
        $script:batchCalls | Should -Be 3   # 20 + 20 + 5
    }

    It 'retries throttled sub-responses' {
        $script:round = 0
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $script:round++
            $reqBody = $Parameters['Body'] | ConvertFrom-Json
            $resps = $reqBody.requests | ForEach-Object {
                if ($script:round -eq 1 -and $_.id -eq '2') {
                    [pscustomobject]@{ id = $_.id; status = 429; headers = @{ 'Retry-After' = '0' }; body = @{} }
                } else {
                    [pscustomobject]@{ id = $_.id; status = 200; headers = @{}; body = @{ done = $true } }
                }
            }
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = (@{ responses = $resps } | ConvertTo-Json -Depth 8); ContentBytes = $null }
        }
        $out = Invoke-MgGraphCommunityBatch -Requests @(
            @{ Method = 'GET'; Url = '/a' },
            @{ Method = 'GET'; Url = '/b' }
        )
        $out.Count | Should -Be 2
        ($out | Where-Object id -eq '2').status | Should -Be 200
        $script:round | Should -Be 2
    }

    It 'posts to a correctly-versioned absolute $batch URL (no doubled version segment)' {
        $script:seenUri = $null
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $script:seenUri = $Parameters['Uri']
            $reqBody = $Parameters['Body'] | ConvertFrom-Json
            $resps = $reqBody.requests | ForEach-Object { [pscustomobject]@{ id = $_.id; status = 200; headers = @{}; body = @{} } }
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = (@{ responses = $resps } | ConvertTo-Json -Depth 8); ContentBytes = $null }
        }
        # Default is /beta; -V1 opts down to /v1.0.
        Invoke-MgGraphCommunityBatch -Requests @(@{ Method = 'GET'; Url = '/me' }) | Out-Null
        $script:seenUri | Should -Be 'https://graph.microsoft.com/beta/$batch'
        Invoke-MgGraphCommunityBatch -V1 -Requests @(@{ Method = 'GET'; Url = '/me' }) | Out-Null
        $script:seenUri | Should -Be 'https://graph.microsoft.com/v1.0/$batch'
    }

    It 'emits a null-status placeholder for an id Graph never returns' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            # Only return a response for id 1, omit id 2 entirely.
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = (@{ responses = @([pscustomobject]@{ id = '1'; status = 200; headers = @{}; body = @{} }) } | ConvertTo-Json -Depth 8); ContentBytes = $null }
        }
        $out = Invoke-MgGraphCommunityBatch -Requests @(
            @{ Method = 'GET'; Url = '/a' },
            @{ Method = 'GET'; Url = '/b' }
        )
        $out.Count       | Should -Be 2
        $out[1].id       | Should -Be '2'
        $out[1].status   | Should -BeNullOrEmpty
    }

    It 'normalizes absolute URLs to relative in the batch body' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $reqBody = $Parameters['Body'] | ConvertFrom-Json
            $resps = $reqBody.requests | ForEach-Object { [pscustomobject]@{ id = $_.id; status = 200; headers = @{}; body = @{ seenUrl = $_.url } } }
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = (@{ responses = $resps } | ConvertTo-Json -Depth 8); ContentBytes = $null }
        }
        $out = Invoke-MgGraphCommunityBatch -Requests @(
            @{ Method = 'GET'; Url = 'https://graph.microsoft.com/v1.0/me' }
        )
        $out[0].body.seenUrl | Should -Be '/me'
    }
}

Describe 'Multi-connection switching' {
    BeforeAll {
        $script:m = Get-Module MgGraphCommunity
        & $script:m {
            function New-TestJwt([string]$tid, [string]$upn) {
                $h = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"alg":"none"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
                $exp = [int]([DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds())
                $p = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(('{"tid":"' + $tid + '","upn":"' + $upn + '","exp":' + $exp + '}'))).TrimEnd('=').Replace('+','-').Replace('/','_')
                "$h.$p."
            }
            $mk = {
                param($tid, $upn, $client)
                [pscustomobject]@{
                    Tokens        = [pscustomobject]@{ access_token = (New-TestJwt $tid $upn); refresh_token = $null }
                    ExpiresOn     = (Get-Date).ToUniversalTime().AddHours(1)
                    CacheKey      = "key-$tid"
                    Authority     = [pscustomobject]@{ Login = 'https://login.microsoftonline.com'; GraphResource = 'https://graph.microsoft.com'; Environment = 'Global' }
                    ClientId      = $client
                    TenantSegment = $tid
                    Scopes        = @('User.Read')
                    FlowType      = 'Test'
                    Persist       = $false
                }
            }
            $script:MgcSessions = [ordered]@{}
            $script:MgcSessions['key-tenantA'] = & $mk 'tenantA' 'a@a.com' 'client-A'
            $script:MgcSessions['key-tenantB'] = & $mk 'tenantB' 'b@b.com' 'client-B'
            $script:MgcActiveSession = $script:MgcSessions['key-tenantA']
        }
    }
    AfterAll { & $script:m { $script:MgcSessions = [ordered]@{}; $script:MgcActiveSession = $null; $script:MgcContext = $null } }

    It 'lists all connections with one marked active' {
        $list = Get-MgGraphCommunityContext -ListAvailable
        $list.Count | Should -Be 2
        ($list | Where-Object IsActive).TenantId | Should -Be 'tenantA'
    }

    It 'switches the active connection by tenant' {
        Select-MgGraphCommunityContext -TenantId 'tenantB'
        $list = Get-MgGraphCommunityContext -ListAvailable
        ($list | Where-Object IsActive).TenantId | Should -Be 'tenantB'
        (Get-MgGraphCommunityContext).TenantId   | Should -Be 'tenantB'
    }

    It 'switches by 1-based index' {
        Select-MgcContext -Index 1
        (Get-MgGraphCommunityContext).TenantId | Should -Be 'tenantA'
    }

    It 'throws when the selection is ambiguous or missing' {
        { Select-MgGraphCommunityContext -ClientId 'nope' } | Should -Throw
    }
}

Describe 'AccessToken flow expiry from JWT' {
    AfterAll {
        $m = Get-Module MgGraphCommunity
        & $m { $script:MgcActiveSession = $null; $script:MgcContext = $null; $script:MgcSessions = [ordered]@{} }
    }

    It 'derives ExpiresOn from the JWT exp claim' {
        $exp = [int]([DateTimeOffset]::UtcNow.AddMinutes(42).ToUnixTimeSeconds())
        $h = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"alg":"none"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        $p = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(('{"upn":"x@y.com","tid":"t","exp":' + $exp + '}'))).TrimEnd('=').Replace('+','-').Replace('/','_')
        $jwt = "$h.$p."
        $secure = ConvertTo-SecureString $jwt -AsPlainText -Force
        Connect-MgGraphCommunity -AccessToken $secure -NoWelcome
        $ctx = Get-MgGraphCommunityContext
        $expectedUtc = [DateTimeOffset]::FromUnixTimeSeconds($exp).UtcDateTime
        ([Math]::Abs(($ctx.ExpiresOn.ToUniversalTime() - $expectedUtc).TotalMinutes)) | Should -BeLessThan 2
    }
}

Describe 'Get-MgcTokenExpiry' {
    It 'extracts the exp claim from a JWT' {
        $futureExp = [int]([DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds())
        $header  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"alg":"none","typ":"JWT"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        $payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(('{"exp":' + $futureExp + '}'))).TrimEnd('=').Replace('+','-').Replace('/','_')
        $jwt     = "$header.$payload."
        $tokens  = [pscustomobject]@{ access_token = $jwt }
        $expiry  = Get-MgcTokenExpiry -Tokens $tokens
        $expiry.Kind | Should -Be 'Utc'
        $expiry      | Should -BeGreaterThan (Get-Date).ToUniversalTime()
    }

    It 'falls back to expires_in when no JWT is decodable' {
        $tokens = [pscustomobject]@{ access_token = 'not-a-jwt'; expires_in = 3600 }
        $expiry = Get-MgcTokenExpiry -Tokens $tokens
        $expiry | Should -BeGreaterThan (Get-Date).ToUniversalTime()
    }
}
