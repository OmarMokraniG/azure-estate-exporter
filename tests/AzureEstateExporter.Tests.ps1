#Requires -Version 7.2
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter' 'AzureEstateExporter.psd1'
    Import-Module $modulePath -Force
}

Describe 'Module surface' {
    It 'exports only Export-AzureEstate' {
        $exports = (Get-Module AzureEstateExporter).ExportedFunctions.Keys
        $exports | Should -Contain 'Export-AzureEstate'
        $exports.Count | Should -Be 1
    }

    It 'has comment-based help' {
        $h = Get-Help Export-AzureEstate -Full
        $h.Synopsis | Should -Not -BeNullOrEmpty
        $h.Description | Should -Not -BeNullOrEmpty
    }
}

Describe 'Protect-SensitiveValue' {
    BeforeAll {
        # Re-import to access private functions for unit testing.
        $modulePath = Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter'
        $script:protect = Get-ChildItem $modulePath -Recurse -Filter 'Protect-SensitiveValue.ps1' | Select-Object -First 1
        . $script:protect.FullName
    }

    It 'redacts keys that match the sensitive pattern' {
        $obj = [pscustomobject]@{
            name              = 'safe'
            password          = 'p@ss'
            connectionString  = 'Server=...;Password=...'
            nested            = [pscustomobject]@{ apiKey = 'sk-xxx'; ok = 'yes' }
        }
        $red = Protect-SensitiveValue -InputObject $obj
        $red.name             | Should -Be 'safe'
        $red.password         | Should -Be '***REDACTED***'
        $red.connectionString | Should -Be '***REDACTED***'
        $red.nested.apiKey    | Should -Be '***REDACTED***'
        $red.nested.ok        | Should -Be 'yes'
    }

    It 'returns the input unchanged when -NoRedact is set' {
        $obj = [pscustomobject]@{ password = 'p@ss' }
        $out = Protect-SensitiveValue -InputObject $obj -NoRedact
        $out.password | Should -Be 'p@ss'
    }

    It 'handles arrays' {
        $obj = @(
            [pscustomobject]@{ secret = 's1' },
            [pscustomobject]@{ secret = 's2' }
        )
        $out = Protect-SensitiveValue -InputObject $obj
        $out.Count | Should -Be 2
        $out[0].secret | Should -Be '***REDACTED***'
        $out[1].secret | Should -Be '***REDACTED***'
    }
}

Describe 'ConvertTo-EstateModel' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter'
        Get-ChildItem $modulePath -Recurse -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }

    It 'normalizes ARG rows and builds an edge from properties referencing another resource id' {
        $vmId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1'
        $nicId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Network/networkInterfaces/nic1'

        $arg = @(
            [pscustomobject]@{
                id = $vmId; name = 'vm1'; type = 'Microsoft.Compute/virtualMachines'
                kind = $null; location = 'westeurope'; resourceGroup = 'rg1'; subscriptionId = 's1'
                tags = @{}; sku = @{}; identity = @{ type = 'None' }
                properties = [pscustomobject]@{ networkProfile = [pscustomobject]@{ networkInterfaces = @(@{ id = $nicId }) } }
            },
            [pscustomobject]@{
                id = $nicId; name = 'nic1'; type = 'Microsoft.Network/networkInterfaces'
                kind = $null; location = 'westeurope'; resourceGroup = 'rg1'; subscriptionId = 's1'
                tags = @{}; sku = @{}; identity = @{}
                properties = [pscustomobject]@{}
            }
        )
        $extras = [pscustomobject]@{ DiagnosticSettings=@(); RoleAssignments=@(); Locks=@(); PolicyAssignments=@() }

        $model = ConvertTo-EstateModel -ArgRows $arg -ArmExtras $extras
        $model.Inventory.Count | Should -Be 2
        $model.Graph.nodes.Count | Should -Be 2
        $model.Graph.edges | Should -Not -BeNullOrEmpty
        $model.Manifest.Count | Should -Be 2
        ($model.Manifest | Where-Object { $_.azureId -eq $vmId }).tfAddress | Should -Match 'virtualmachines.vm1'
    }
}
