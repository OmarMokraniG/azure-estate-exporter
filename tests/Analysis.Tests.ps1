#Requires -Version 7.2
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter' 'AzureEstateExporter.psd1'
    Import-Module $modulePath -Force

    # Dot-source the private analysis functions for direct testing.
    $analysisRoot = Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter' 'Private' 'analysis'
    . (Join-Path $analysisRoot 'Invoke-ExposureAnalysis.ps1')
    . (Join-Path $analysisRoot 'Invoke-AccessAnalysis.ps1')
}

Describe 'Invoke-ExposureAnalysis' {
    It 'flags a High severity finding for an NSG that allows RDP from any source' {
        $inventory = @(
            [pscustomobject]@{
                id             = '/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg1'
                name           = 'nsg1'
                type           = 'Microsoft.Network/networkSecurityGroups'
                subscriptionId = 'x'
                resourceGroup  = 'rg'
                properties     = [pscustomobject]@{
                    securityRules = @([pscustomobject]@{
                        name = 'allow-rdp'
                        properties = [pscustomobject]@{
                            access = 'Allow'; direction = 'Inbound'; protocol = 'Tcp'
                            sourceAddressPrefix = '*'; destinationPortRange = '3389'; priority = 100
                        }
                    })
                }
            }
        )
        $findings = @(Invoke-ExposureAnalysis -Inventory $inventory)
        $findings.Count               | Should -BeGreaterThan 0
        $findings[0].severity         | Should -Be 'High'
        $findings[0].type             | Should -Be 'OpenManagementPort'
        $findings[0].resourceId       | Should -Match 'nsg1$'
    }

    It 'does NOT flag an NSG with a corporate-CIDR-only inbound rule' {
        $inventory = @(
            [pscustomobject]@{
                id             = '/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg2'
                name           = 'nsg2'
                type           = 'Microsoft.Network/networkSecurityGroups'
                subscriptionId = 'x'
                resourceGroup  = 'rg'
                properties     = [pscustomobject]@{
                    securityRules = @([pscustomobject]@{
                        name = 'corp-ssh'
                        properties = [pscustomobject]@{
                            access = 'Allow'; direction = 'Inbound'; protocol = 'Tcp'
                            sourceAddressPrefix = '10.0.0.0/8'; destinationPortRange = '22'; priority = 100
                        }
                    })
                }
            }
        )
        @(Invoke-ExposureAnalysis -Inventory $inventory).Count | Should -Be 0
    }

    It 'flags a Storage account with public network access AND public blob enabled as High' {
        $inventory = @(
            [pscustomobject]@{
                id             = '/subscriptions/x/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st1'
                name           = 'st1'
                type           = 'Microsoft.Storage/storageAccounts'
                subscriptionId = 'x'
                resourceGroup  = 'rg'
                properties     = [pscustomobject]@{
                    publicNetworkAccess     = 'Enabled'
                    allowBlobPublicAccess   = $true
                    networkAcls             = [pscustomobject]@{ defaultAction = 'Allow' }
                }
            }
        )
        $f = @(Invoke-ExposureAnalysis -Inventory $inventory)[0]
        $f.severity | Should -Be 'High'
        $f.type     | Should -Be 'PublicBlobAccess'
    }

    It 'flags a Key Vault with public access + default allow as High' {
        $inventory = @(
            [pscustomobject]@{
                id             = '/subscriptions/x/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv1'
                name           = 'kv1'
                type           = 'Microsoft.KeyVault/vaults'
                subscriptionId = 'x'
                resourceGroup  = 'rg'
                properties     = [pscustomobject]@{
                    publicNetworkAccess = 'Enabled'
                    networkAcls         = [pscustomobject]@{ defaultAction = 'Allow' }
                }
            }
        )
        @(Invoke-ExposureAnalysis -Inventory $inventory)[0].type | Should -Be 'KeyVaultPublicAccess'
    }

    It 'sorts findings High before Medium before Info' {
        $inventory = @(
            [pscustomobject]@{
                id             = '/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip1'
                name           = 'pip1'
                type           = 'Microsoft.Network/publicIPAddresses'
                subscriptionId = 'x'; resourceGroup = 'rg'
                sku            = [pscustomobject]@{ name = 'Standard' }
                properties     = [pscustomobject]@{ publicIPAllocationMethod = 'Static'; ipAddress = '1.2.3.4' }
            },
            [pscustomobject]@{
                id             = '/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg-rdp'
                name           = 'nsg-rdp'
                type           = 'Microsoft.Network/networkSecurityGroups'
                subscriptionId = 'x'; resourceGroup = 'rg'
                properties     = [pscustomobject]@{
                    securityRules = @([pscustomobject]@{
                        name = 'rdp'
                        properties = [pscustomobject]@{
                            access = 'Allow'; direction = 'Inbound'; protocol = 'Tcp'
                            sourceAddressPrefix = '*'; destinationPortRange = '3389'; priority = 100
                        }
                    })
                }
            }
        )
        $f = @(Invoke-ExposureAnalysis -Inventory $inventory)
        $f[0].severity | Should -Be 'High'
        $f[-1].severity | Should -Be 'Info'
    }
}

Describe 'Invoke-AccessAnalysis' {
    It 'emits a High finding for Owner at subscription scope' {
        $ra = @(
            [pscustomobject]@{
                principalId = 'p1'; principalName = 'alice@contoso.com'; principalType = 'User'
                roleDefinitionName = 'Owner'
                scope = '/subscriptions/11111111-1111-1111-1111-111111111111'
            }
        )
        $r = Invoke-AccessAnalysis -RoleAssignments $ra
        $r.Findings.Count | Should -Be 1
        $r.Findings[0].severity | Should -Be 'High'
        $r.Findings[0].type     | Should -Be 'BroadScopeRoleAssignment'
    }

    It 'emits a Medium finding for Owner at RG scope (downgraded from High)' {
        $ra = @(
            [pscustomobject]@{
                principalId = 'p2'; principalName = 'bob@contoso.com'; principalType = 'User'
                roleDefinitionName = 'Owner'
                scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg1'
            }
        )
        $r = Invoke-AccessAnalysis -RoleAssignments $ra
        $r.Findings[0].severity | Should -Be 'Medium'
    }

    It 'emits NO broad-scope finding for Owner at resource scope' {
        $ra = @(
            [pscustomobject]@{
                principalId = 'p3'; principalName = 'carol'; principalType = 'User'
                roleDefinitionName = 'Owner'
                scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/st1'
            }
        )
        $r = Invoke-AccessAnalysis -RoleAssignments $ra
        @($r.Findings | Where-Object { $_.type -eq 'BroadScopeRoleAssignment' }).Count | Should -Be 0
    }

    It 'detects orphaned assignments (principalName null) and emits a single Medium finding' {
        $ra = @(
            [pscustomobject]@{
                principalId = 'deleted1'; principalName = $null; principalType = 'User'
                roleDefinitionName = 'Reader'
                scope = '/subscriptions/x/resourceGroups/rg'
            },
            [pscustomobject]@{
                principalId = 'deleted2'; principalName = $null; principalType = 'Unknown'
                roleDefinitionName = 'Reader'
                scope = '/subscriptions/x/resourceGroups/rg'
            }
        )
        $r = Invoke-AccessAnalysis -RoleAssignments $ra
        @($r.Findings | Where-Object { $_.type -eq 'OrphanedRoleAssignment' }).Count | Should -Be 1
        $r.OrphanedAssignments.Count | Should -Be 2
    }

    It 'aggregates assignments per principal and exposes top-severity' {
        $ra = @(
            [pscustomobject]@{ principalId='p'; principalName='svc'; principalType='ServicePrincipal'; roleDefinitionName='Reader';      scope='/subscriptions/x' },
            [pscustomobject]@{ principalId='p'; principalName='svc'; principalType='ServicePrincipal'; roleDefinitionName='Contributor'; scope='/subscriptions/x' },
            [pscustomobject]@{ principalId='p'; principalName='svc'; principalType='ServicePrincipal'; roleDefinitionName='Owner';       scope='/subscriptions/x' }
        )
        $r = Invoke-AccessAnalysis -RoleAssignments $ra
        $byP = $r.ByPrincipal[0]
        $byP.assignmentCount | Should -Be 3
        $byP.topSeverity     | Should -Be 'High'
        $byP.roles -contains 'Owner' | Should -BeTrue
    }
}
