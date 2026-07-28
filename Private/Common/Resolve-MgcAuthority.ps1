function Resolve-MgcAuthority {
    <#
    .SYNOPSIS
        Resolves the login + Graph endpoints for a named Microsoft cloud environment.

    .DESCRIPTION
        Mirrors the -Environment parameter on Connect-MgGraph. Supported values:
            Global     -> login.microsoftonline.com    + graph.microsoft.com
            USGov      -> login.microsoftonline.us     + graph.microsoft.us
            USGovDoD   -> login.microsoftonline.us     + dod-graph.microsoft.us
            China      -> login.chinacloudapi.cn       + microsoftgraph.chinacloudapi.cn
            BleuCloud  -> login.sovcloud-identity.fr   + graph.svc.sovcloud.fr
            DelosCloud -> login.sovcloud-identity.de   + graph.svc.sovcloud.de
            GovSGCloud -> login.sovcloud-identity.sg   + graph.svc.sovcloud.sg

        BleuCloud (France), DelosCloud (Germany) and GovSGCloud (Singapore) endpoint
        values mirror the official SDK source (msgraph-sdk-powershell PR #3523).
        Microsoft's built-in first-party client ID may not exist in sovereign
        clouds; pass -ClientId with a local app registration there.

    .OUTPUTS
        [pscustomobject] with .Login, .GraphResource, .Environment
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Global','USGov','USGovDoD','China','BleuCloud','DelosCloud','GovSGCloud')]
        [string]$Environment = 'Global'
    )

    switch ($Environment) {
        'USGov' {
            return [pscustomobject]@{
                Environment   = 'USGov'
                Login         = 'https://login.microsoftonline.us'
                GraphResource = 'https://graph.microsoft.us'
            }
        }
        'USGovDoD' {
            return [pscustomobject]@{
                Environment   = 'USGovDoD'
                Login         = 'https://login.microsoftonline.us'
                GraphResource = 'https://dod-graph.microsoft.us'
            }
        }
        'China' {
            return [pscustomobject]@{
                Environment   = 'China'
                Login         = 'https://login.chinacloudapi.cn'
                GraphResource = 'https://microsoftgraph.chinacloudapi.cn'
            }
        }
        'BleuCloud' {
            return [pscustomobject]@{
                Environment   = 'BleuCloud'
                Login         = 'https://login.sovcloud-identity.fr'
                GraphResource = 'https://graph.svc.sovcloud.fr'
            }
        }
        'DelosCloud' {
            return [pscustomobject]@{
                Environment   = 'DelosCloud'
                Login         = 'https://login.sovcloud-identity.de'
                GraphResource = 'https://graph.svc.sovcloud.de'
            }
        }
        'GovSGCloud' {
            return [pscustomobject]@{
                Environment   = 'GovSGCloud'
                Login         = 'https://login.sovcloud-identity.sg'
                GraphResource = 'https://graph.svc.sovcloud.sg'
            }
        }
        default {
            return [pscustomobject]@{
                Environment   = 'Global'
                Login         = 'https://login.microsoftonline.com'
                GraphResource = 'https://graph.microsoft.com'
            }
        }
    }
}
