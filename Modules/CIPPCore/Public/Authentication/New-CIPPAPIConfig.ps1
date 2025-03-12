function New-CIPPAPIConfig {

    [CmdletBinding(SupportsShouldProcess)]
    param (
        $APIName = 'CIPP API Config',
        $Headers,
        [switch]$ResetSecret,
        [string]$AppName,
        [string]$AppId
    )

    try {
        if ($AppId) {
            $APIApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appid='$($AppId)')" -NoAuthCheck $true
        } else {
            $CreateBody = @{
                api                    = @{
                    oauth2PermissionScopes = @(
                        @{
                            adminConsentDescription = 'Allow the application to access CIPP-API on behalf of the signed-in user.'
                            adminConsentDisplayName = 'Access CIPP-API'
                            id                      = 'ba7ffeff-96ea-4ac4-9822-1bcfee9adaa4'
                            isEnabled               = $true
                            type                    = 'User'
                            userConsentDescription  = 'Allow the application to access CIPP-API on your behalf.'
                            userConsentDisplayName  = 'Access CIPP-API'
                            value                   = 'user_impersonation'
                        }
                    )
                }
                displayName            = $AppName
                requiredResourceAccess = @(
                    @{
                        resourceAccess = @(
                            @{
                                id   = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'
                                type = 'Scope'
                            }
                        )
                        resourceAppId  = '00000003-0000-0000-c000-000000000000'
                    }
                )
                signInAudience         = 'AzureADMyOrg'
                web                    = @{
                    homePageUrl           = 'https://cipp.app'
                    implicitGrantSettings = @{
                        enableAccessTokenIssuance = $false
                        enableIdTokenIssuance     = $true
                    }
                    redirectUris          = @("https://$($ENV:Website_hostname)/.auth/login/aad/callback")
                }
            } | ConvertTo-Json -Depth 10 -Compress

            if ($PSCmdlet.ShouldProcess($AppName, 'Create API App')) {
                Write-Information 'Creating app'
                $APIApp = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/applications' -AsApp $true -NoAuthCheck $true -type POST -body $CreateBody
                Write-Information 'Creating password'
                $APIPassword = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($APIApp.id)/addPassword" -AsApp $true -NoAuthCheck $true -type POST -body "{`"passwordCredential`":{`"displayName`":`"Generated by API Setup`"}}"
                Write-Information 'Adding App URL'
                $APIIdUrl = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($APIApp.id)" -AsApp $true -NoAuthCheck $true -type PATCH -body "{`"identifierUris`":[`"api://$($APIApp.appId)`"]}"
                Write-Information 'Adding serviceprincipal'
                $ServicePrincipal = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/serviceprincipals' -AsApp $true -NoAuthCheck $true -type POST -body "{`"accountEnabled`":true,`"appId`":`"$($APIApp.appId)`",`"displayName`":`"$AppName`",`"tags`":[`"WindowsAzureActiveDirectoryIntegratedApp`",`"AppServiceIntegratedApp`"]}"
                Write-LogMessage -headers $Headers -API $APINAME -tenant 'None '-message "Created CIPP-API App with name '$($APIApp.displayName)'." -Sev 'info'
            }
        }
        if ($ResetSecret.IsPresent -and $APIApp) {
            if ($PSCmdlet.ShouldProcess($APIApp.displayName, 'Reset API Secret')) {
                Write-Information 'Removing all old passwords'
                $Requests = @(
                    @{
                        id      = 'removeOldPasswords'
                        method  = 'PATCH'
                        url     = "applications/$($APIApp.id)/"
                        headers = @{
                            'Content-Type' = 'application/json'
                        }
                        body    = @{
                            passwordCredentials = @()
                        }
                    },
                    @{
                        id        = 'addNewPassword'
                        method    = 'POST'
                        url       = "applications/$($APIApp.id)/addPassword"
                        headers   = @{
                            'Content-Type' = 'application/json'
                        }
                        body      = @{
                            passwordCredential = @{
                                displayName = 'Generated by API Setup'
                            }
                        }
                        dependsOn = @('removeOldPasswords')
                    }
                )
                $BatchResponse = New-GraphBulkRequest -tenantid $env:TenantID -NoAuthCheck $true -asapp $true -Requests $Requests
                $APIPassword = $BatchResponse | Where-Object { $_.id -eq 'addNewPassword' } | Select-Object -ExpandProperty body
                Write-LogMessage -headers $Headers -API $APINAME -tenant 'None '-message "Reset CIPP-API Password for '$($APIApp.displayName)'." -Sev 'info'
            }
        }

        return @{
            AppName           = $APIApp.displayName
            ApplicationID     = $APIApp.appId
            ApplicationSecret = $APIPassword.secretText
            Results           = $Results
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Information ($ErrorMessage | ConvertTo-Json -Depth 10)
        Write-LogMessage -headers $Headers -API $APINAME -tenant 'None' -message "Failed to setup CIPP-API Access: $($ErrorMessage.NormalizedError) Linenumber: $($_.InvocationInfo.ScriptLineNumber)" -Sev 'Error' -LogData $ErrorMessage
        return @{
            Results = "Failed to setup CIPP-API Access: $($ErrorMessage.NormalizedError)"
        }

    }
}
