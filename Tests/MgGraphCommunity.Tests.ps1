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

# ---------------------------------------------------------------------------
# v1.5.0 - sovereign clouds, CAE, default ClientId, app registration helper
# ---------------------------------------------------------------------------

Describe 'Resolve-MgcAuthority v1.5.0 environments' {
    It 'returns the exact endpoint pair for every environment' {
        $expected = @{
            Global     = @('https://login.microsoftonline.com',  'https://graph.microsoft.com')
            USGov      = @('https://login.microsoftonline.us',   'https://graph.microsoft.us')
            USGovDoD   = @('https://login.microsoftonline.us',   'https://dod-graph.microsoft.us')
            China      = @('https://login.chinacloudapi.cn',     'https://microsoftgraph.chinacloudapi.cn')
            BleuCloud  = @('https://login.sovcloud-identity.fr', 'https://graph.svc.sovcloud.fr')
            DelosCloud = @('https://login.sovcloud-identity.de', 'https://graph.svc.sovcloud.de')
            GovSGCloud = @('https://login.sovcloud-identity.sg', 'https://graph.svc.sovcloud.sg')
        }
        foreach ($env in $expected.Keys) {
            $a = Resolve-MgcAuthority -Environment $env
            $a.Environment   | Should -Be $env
            $a.Login         | Should -Be $expected[$env][0]
            $a.GraphResource | Should -Be $expected[$env][1]
        }
    }

    It 'Connect-MgGraphCommunity accepts the new environment names' {
        $param = (Get-Command Connect-MgGraphCommunity).Parameters['Environment']
        $validate = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        foreach ($env in @('BleuCloud','DelosCloud','GovSGCloud')) {
            $validate.ValidValues | Should -Contain $env
        }
    }
}

Describe 'Get-MgcCaeClaims' {
    It 'returns the CP1 client capability by default' {
        $claims = Get-MgcCaeClaims
        $parsed = $claims | ConvertFrom-Json
        $parsed.access_token.xms_cc.values | Should -Contain 'CP1'
    }

    It 'merges CP1 into a claims challenge' {
        $challenge = '{"access_token":{"nbf":{"essential":true,"value":"1700000000"}}}'
        $merged = Get-MgcCaeClaims -ChallengeClaims $challenge | ConvertFrom-Json
        $merged.access_token.nbf.essential     | Should -BeTrue
        $merged.access_token.xms_cc.values     | Should -Contain 'CP1'
    }

    It 'passes an unparseable challenge through untouched' {
        Get-MgcCaeClaims -ChallengeClaims 'not-json{' | Should -Be 'not-json{'
    }
}

Describe 'Get-MgcClaimsChallenge' {
    It 'decodes a claims challenge from WWW-Authenticate' {
        $json    = '{"access_token":{"nbf":{"essential":true,"value":"1700000000"}}}'
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
        $header  = 'Bearer realm="", authorization_uri="https://login.microsoftonline.com/common/oauth2/authorize", error="insufficient_claims", claims="' + $encoded + '"'
        $decoded = Get-MgcClaimsChallenge -WwwAuthenticate $header
        ($decoded | ConvertFrom-Json).access_token.nbf.essential | Should -BeTrue
    }

    It 'returns null when the header has no claims challenge' {
        Get-MgcClaimsChallenge -WwwAuthenticate 'Bearer realm="", error="invalid_token"' | Should -BeNullOrEmpty
        Get-MgcClaimsChallenge -WwwAuthenticate $null | Should -BeNullOrEmpty
    }

    It 'returns null when the claims value is not valid Base64 JSON' {
        Get-MgcClaimsChallenge -WwwAuthenticate 'Bearer claims="%%%not-base64%%%"' | Should -BeNullOrEmpty
    }
}

Describe 'CAE claims parameter in delegated token requests' {
    It 'Invoke-MgcRefreshTokenAuth sends CP1 claims by default' {
        $script:tokenBody = $null
        Mock Invoke-MgcTokenEndpoint {
            $script:tokenBody = $Body
            [pscustomobject]@{ access_token = 'AT'; refresh_token = 'RT'; expires_in = 3600 }
        }
        $null = Invoke-MgcRefreshTokenAuth -LoginEndpoint 'https://login.microsoftonline.com' `
            -TenantSegment 'common' -ClientId 'c' -RefreshToken 'RT' -Scopes @('User.Read')
        ($script:tokenBody['claims'] | ConvertFrom-Json).access_token.xms_cc.values | Should -Contain 'CP1'
    }

    It 'Invoke-MgcRefreshTokenAuth passes explicit challenge claims through' {
        $script:tokenBody = $null
        Mock Invoke-MgcTokenEndpoint {
            $script:tokenBody = $Body
            [pscustomobject]@{ access_token = 'AT'; refresh_token = 'RT'; expires_in = 3600 }
        }
        $null = Invoke-MgcRefreshTokenAuth -LoginEndpoint 'https://login.microsoftonline.com' `
            -TenantSegment 'common' -ClientId 'c' -RefreshToken 'RT' -Scopes @('User.Read') `
            -Claims '{"access_token":{"nbf":{"essential":true}}}'
        $script:tokenBody['claims'] | Should -Be '{"access_token":{"nbf":{"essential":true}}}'
    }
}

Describe 'Invoke-MgGraphCommunityRequest CAE claims challenge handling' {
    BeforeAll {
        $script:m = Get-Module MgGraphCommunity
        & $script:m {
            $script:MgcActiveSession = [pscustomobject]@{
                Tokens        = [pscustomobject]@{ access_token = 'AT-old'; refresh_token = 'RT' }
                ExpiresOn     = (Get-Date).ToUniversalTime().AddHours(1)
                CacheKey      = 'cae-test-key'
                Authority     = [pscustomobject]@{ Login = 'https://login.microsoftonline.com'; GraphResource = 'https://graph.microsoft.com' }
                ClientId      = 'test-client'
                TenantSegment = 'common'
                Scopes        = @('User.Read')
                FlowType      = 'Test'
                Persist       = $false
            }
        }
        $script:challengeJson    = '{"access_token":{"nbf":{"essential":true,"value":"1700000000"}}}'
        $script:challengeHeader  = 'Bearer realm="", error="insufficient_claims", claims="' +
            [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($script:challengeJson)) + '"'
    }
    AfterAll { & $script:m { $script:MgcActiveSession = $null } }
    BeforeEach {
        & $script:m { $script:MgcActiveSession.Tokens = [pscustomobject]@{ access_token = 'AT-old'; refresh_token = 'RT' } }
    }

    It 'answers a CAE claims challenge with one claims-bearing re-acquisition and retry' {
        $script:httpCalls = 0
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            $script:httpCalls++
            if ($Parameters['Headers']['Authorization'] -eq 'Bearer AT-new') {
                [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{"ok":true}' }
            } else {
                [pscustomobject]@{ StatusCode = 401; Headers = @{ 'WWW-Authenticate' = $script:challengeHeader }; Content = '' }
            }
        }
        $script:refreshClaims = 'unset'
        Mock -ModuleName MgGraphCommunity Invoke-MgcRefreshTokenAuth {
            $script:refreshClaims = $Claims
            [pscustomobject]@{ access_token = 'AT-new'; refresh_token = 'RT2'; expires_in = 3600 }
        }
        $r = Invoke-MgGraphCommunityRequest -Uri '/me'
        $r.ok | Should -BeTrue
        $script:httpCalls | Should -Be 2
        $parsed = $script:refreshClaims | ConvertFrom-Json
        $parsed.access_token.nbf.essential   | Should -BeTrue
        $parsed.access_token.xms_cc.values   | Should -Contain 'CP1'
    }

    It 'treats a plain 401 as an ordinary refresh (no challenge claims)' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            if ($Parameters['Headers']['Authorization'] -eq 'Bearer AT-new') {
                [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Type' = 'application/json' }; Content = '{"ok":true}' }
            } else {
                [pscustomobject]@{ StatusCode = 401; Headers = @{ 'WWW-Authenticate' = 'Bearer realm="", error="invalid_token"' }; Content = '' }
            }
        }
        $script:sawClaimsParam = $false
        Mock -ModuleName MgGraphCommunity Invoke-MgcRefreshTokenAuth {
            $script:sawClaimsParam = $PSBoundParameters.ContainsKey('Claims')
            [pscustomobject]@{ access_token = 'AT-new'; refresh_token = 'RT2'; expires_in = 3600 }
        }
        (Invoke-MgGraphCommunityRequest -Uri '/me').ok | Should -BeTrue
        $script:sawClaimsParam | Should -BeFalse
    }

    It 'throws a reconnect error when CAE re-acquisition fails' {
        Mock -ModuleName MgGraphCommunity Invoke-MgcHttpRequest {
            [pscustomobject]@{ StatusCode = 401; Headers = @{ 'WWW-Authenticate' = $script:challengeHeader }; Content = '' }
        }
        Mock -ModuleName MgGraphCommunity Invoke-MgcRefreshTokenAuth { throw 'refresh dead' }
        { Invoke-MgGraphCommunityRequest -Uri '/me' } |
            Should -Throw -ExpectedMessage '*Connect-MgGraphCommunity*'
    }
}

Describe 'Default ClientId persistence and precedence' {
    BeforeAll {
        $script:m = Get-Module MgGraphCommunity
    }
    AfterAll {
        & $script:m { $script:MgcActiveSession = $null; $script:MgcContext = $null; $script:MgcSessions = [ordered]@{} }
    }

    It 'Set / read / clear round-trips through config.json' {
        Mock -ModuleName MgGraphCommunity Get-MgcAppDataDir { Join-Path $TestDrive 'mgc-config' }
        $guid = '11111111-2222-3333-4444-555555555555'
        Set-MgGraphCommunityDefaultClientId -ClientId $guid
        & $script:m { Get-MgcDefaultClientId } | Should -Be $guid
        Set-MgGraphCommunityDefaultClientId -Clear
        & $script:m { Get-MgcDefaultClientId } | Should -BeNullOrEmpty
    }

    It 'rejects a non-GUID ClientId' {
        { Set-MgGraphCommunityDefaultClientId -ClientId 'not-a-guid' } | Should -Throw
    }

    Context 'Connect-MgGraphCommunity precedence' {
        BeforeEach {
            Mock -ModuleName MgGraphCommunity Invoke-MgcInteractiveAuth {
                $script:flowClientId = $ClientId
                [pscustomobject]@{ access_token = 'AT'; refresh_token = $null; expires_in = 3600; token_type = 'Bearer' }
            }
            Mock -ModuleName MgGraphCommunity Send-MgcTokenToSdk { 'skipped' }
        }

        It 'uses the saved default when no -ClientId is passed' {
            Mock -ModuleName MgGraphCommunity Get-MgcDefaultClientId { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
            Connect-MgGraphCommunity -NoWelcome -NoCache
            & $script:m { $script:MgcActiveSession.ClientId } | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        }

        It 'an explicit -ClientId wins over the saved default' {
            Mock -ModuleName MgGraphCommunity Get-MgcDefaultClientId { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
            Connect-MgGraphCommunity -NoWelcome -NoCache -ClientId 'ffffffff-1111-2222-3333-444444444444'
            & $script:m { $script:MgcActiveSession.ClientId } | Should -Be 'ffffffff-1111-2222-3333-444444444444'
        }

        It 'falls back to the built-in Microsoft ClientId when nothing is saved' {
            Mock -ModuleName MgGraphCommunity Get-MgcDefaultClientId { $null }
            Connect-MgGraphCommunity -NoWelcome -NoCache
            & $script:m { $script:MgcActiveSession.ClientId } | Should -Be '14d82eec-204b-4c2f-b7e8-296a70dab67e'
        }
    }
}

Describe 'New-MgGraphCommunityAppRegistration' {
    BeforeAll {
        $script:m = Get-Module MgGraphCommunity
    }
    AfterAll {
        & $script:m { $script:MgcActiveSession = $null; $script:MgcContext = $null }
    }

    It 'throws a clear error when no session is active' {
        & $script:m { $script:MgcActiveSession = $null }
        { New-MgGraphCommunityAppRegistration } | Should -Throw -ExpectedMessage '*Application.ReadWrite.All*'
    }

    Context 'with an active session' {
        BeforeEach {
            & $script:m {
                $script:MgcActiveSession = [pscustomobject]@{ Tokens = [pscustomobject]@{ access_token = 'AT'; refresh_token = $null } }
                $script:MgcContext       = [pscustomobject]@{ TenantId = 'tenant-1' }
            }
            $script:graphCalls = [System.Collections.ArrayList]@()
            Mock -ModuleName MgGraphCommunity Invoke-MgGraphCommunityRequest {
                $null = $script:graphCalls.Add(@{ Method = $Method; Uri = $Uri; Body = $Body })
                if ($Method -eq 'POST') {
                    return [pscustomobject]@{ appId = '99999999-8888-7777-6666-555555555555'; id = 'new-obj-id'; displayName = $Body.displayName }
                }
                return [pscustomobject]@{ appId = '99999999-8888-7777-6666-555555555555' }
            }
        }

        It 'creates a single-tenant public client app with the loopback redirect' {
            $result = New-MgGraphCommunityAppRegistration -DisplayName 'TestApp'
            $post = $script:graphCalls | Where-Object { $_.Method -eq 'POST' } | Select-Object -First 1
            $post.Uri                          | Should -Be '/applications'
            $post.Body.displayName             | Should -Be 'TestApp'
            $post.Body.signInAudience          | Should -Be 'AzureADMyOrg'
            $post.Body.isFallbackPublicClient  | Should -BeTrue
            $post.Body.publicClient.redirectUris | Should -Contain 'http://localhost'
            $result.ClientId | Should -Be '99999999-8888-7777-6666-555555555555'
            $result.ObjectId | Should -Be 'new-obj-id'
            $result.TenantId | Should -Be 'tenant-1'
        }

        It 'adds the WAM broker redirect URI with -AddWamRedirectUri' {
            $result = New-MgGraphCommunityAppRegistration -AddWamRedirectUri
            $patch = $script:graphCalls | Where-Object { $_.Method -eq 'PATCH' } | Select-Object -First 1
            $patch.Uri | Should -Be '/applications/new-obj-id'
            $patch.Body.publicClient.redirectUris | Should -Contain 'ms-appx-web://Microsoft.AAD.BrokerPlugin/99999999-8888-7777-6666-555555555555'
            $result.RedirectUris | Should -Contain 'ms-appx-web://Microsoft.AAD.BrokerPlugin/99999999-8888-7777-6666-555555555555'
        }

        It 'persists the ClientId with -SetAsDefault' {
            Mock -ModuleName MgGraphCommunity Set-MgGraphCommunityDefaultClientId { $script:savedDefault = $ClientId }
            $script:savedDefault = $null
            $null = New-MgGraphCommunityAppRegistration -SetAsDefault
            $script:savedDefault | Should -Be '99999999-8888-7777-6666-555555555555'
        }

        It 'maps a 403 to an actionable missing-scope error' {
            Mock -ModuleName MgGraphCommunity Invoke-MgGraphCommunityRequest {
                if ($Method -eq 'POST') { throw 'Graph error 403 [Authorization_RequestDenied]: Insufficient privileges' }
            }
            { New-MgGraphCommunityAppRegistration } | Should -Throw -ExpectedMessage '*Application.ReadWrite.All*'
        }
    }
}

Describe 'Module exports the v1.5.0 surface' {
    It 'exports the new functions' {
        $m = Get-Module MgGraphCommunity
        foreach ($name in @('New-MgGraphCommunityAppRegistration','Set-MgGraphCommunityDefaultClientId')) {
            $m.ExportedFunctions.Keys | Should -Contain $name
        }
    }
    It 'exports the new aliases' {
        $m = Get-Module MgGraphCommunity
        foreach ($alias in @('New-MgcApp','Set-MgcDefaultClientId')) {
            $m.ExportedAliases.Keys | Should -Contain $alias
        }
    }
}
