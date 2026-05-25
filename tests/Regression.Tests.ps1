#Requires -Version 7.2
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5.0' }

# Regression tests for v0.1 bugs that took us a long time to find.
# Each test must FAIL if someone reintroduces the bug, regardless of Azure access.

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter'
    Get-ChildItem $modulePath -Recurse -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    Import-Module (Join-Path $modulePath 'AzureEstateExporter.psd1') -Force
}

Describe 'Regression: ConvertTo-EstateModel walks IDictionary safely' {
    It 'finishes quickly when properties contain a Hashtable' {
        # The v0.1 bug: `foreach ($x in $hashtable)` yields the hashtable as a
        # single item, causing the walker to push the same hashtable forever.
        # IDictionary must be detected BEFORE IEnumerable.
        $targetId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/sa1'
        $arg = @(
            [pscustomobject]@{
                id = $targetId; name = 'sa1'; type = 'Microsoft.Storage/storageAccounts'
                kind = $null; location = 'westeurope'; resourceGroup = 'rg1'; subscriptionId = 's1'
                tags = @{}; sku = @{}; identity = @{}
                properties = [pscustomobject]@{}
            },
            [pscustomobject]@{
                id = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.EventGrid/topics/t1'
                name = 't1'; type = 'Microsoft.EventGrid/topics'
                kind = $null; location = 'westeurope'; resourceGroup = 'rg1'; subscriptionId = 's1'
                tags = @{}; sku = @{}; identity = @{}
                # Hashtable nested several levels deep — would hang v0.1.
                properties = @{ source = @{ resourceId = $targetId; nested = @{ deep = @{ ref = $targetId } } } }
            }
        )
        $extras = [pscustomobject]@{ DiagnosticSettings=@(); RoleAssignments=@(); Locks=@(); PolicyAssignments=@() }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $model = ConvertTo-EstateModel -ArgRows $arg -ArmExtras $extras
        $sw.Stop()
        $sw.ElapsedMilliseconds | Should -BeLessThan 2000
        $model.Graph.edges.Count | Should -BeGreaterThan 0
    }
}

Describe 'Regression: edge schema carries sourceProperty path' {
    It 'records the property path that produced the edge' {
        $appId  = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Web/sites/site1'
        $planId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Web/serverFarms/plan1'
        $arg = @(
            [pscustomobject]@{
                id = $appId; name = 'site1'; type = 'microsoft.web/sites'
                kind = 'app'; location = 'westeurope'; resourceGroup = 'rg1'; subscriptionId = 's1'
                tags = @{}; sku = @{}; identity = @{}
                properties = [pscustomobject]@{ serverFarmId = $planId }
            },
            [pscustomobject]@{
                id = $planId; name = 'plan1'; type = 'microsoft.web/serverFarms'
                kind = $null; location = 'westeurope'; resourceGroup = 'rg1'; subscriptionId = 's1'
                tags = @{}; sku = @{}; identity = @{}
                properties = [pscustomobject]@{}
            }
        )
        $extras = [pscustomobject]@{ DiagnosticSettings=@(); RoleAssignments=@(); Locks=@(); PolicyAssignments=@() }
        $model = ConvertTo-EstateModel -ArgRows $arg -ArmExtras $extras
        $edge = $model.Graph.edges | Where-Object { $_.from -eq $appId -and $_.to -eq $planId } | Select-Object -First 1
        $edge | Should -Not -BeNullOrEmpty
        $edge.sourceProperty | Should -Match 'serverFarmId'
        # serverFarmId is mapped to 'hosted-on' by the heuristic table.
        $edge.relation | Should -Be 'hosted-on'
    }
}

Describe 'Regression: managedBy creates a managed-by edge' {
    It 'links a managed resource to its manager' {
        $managerId = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mi1'
        $childId   = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1'
        $arg = @(
            [pscustomobject]@{
                id = $managerId; name = 'mi1'; type = 'Microsoft.ManagedIdentity/userAssignedIdentities'
                kind = $null; location = 'westeurope'; resourceGroup = 'rg1'; subscriptionId = 's1'
                tags = @{}; sku = @{}; identity = @{}; managedBy = $null
                properties = [pscustomobject]@{}
            },
            [pscustomobject]@{
                id = $childId; name = 'vm1'; type = 'Microsoft.Compute/virtualMachines'
                kind = $null; location = 'westeurope'; resourceGroup = 'rg1'; subscriptionId = 's1'
                tags = @{}; sku = @{}; identity = @{}; managedBy = $managerId
                properties = [pscustomobject]@{}
            }
        )
        $extras = [pscustomobject]@{ DiagnosticSettings=@(); RoleAssignments=@(); Locks=@(); PolicyAssignments=@() }
        $model = ConvertTo-EstateModel -ArgRows $arg -ArmExtras $extras
        ($model.Graph.edges | Where-Object { $_.relation -eq 'managed-by' -and $_.from -eq $childId }).Count | Should -Be 1
    }
}

Describe 'Regression: AllowEmptyCollection on Invoke-TerraformExport.Errors' {
    It 'accepts an empty ArrayList without throwing parameter binding errors' {
        # Pre-condition for the smoke path: orchestrator passes an empty list
        # when no prior collector has appended any error.
        $cmd = Get-Command Invoke-TerraformExport -ErrorAction Stop
        $p = $cmd.Parameters['Errors']
        $hasAllowEmpty = $p.Attributes | Where-Object { $_.GetType().Name -eq 'AllowEmptyCollectionAttribute' }
        $hasAllowEmpty | Should -Not -BeNullOrEmpty
    }
}

Describe 'Regression: KQL queries to az graph stay single-line' {
    It 'keeps KQL on one line so Windows argv does not truncate at LF' {
        # On Windows az.cmd splits arguments on LF, so a multi-line KQL would
        # silently be cut after the first line. The collector must `-join ' | '`
        # before calling az.
        $collector = Get-Content (Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter' 'Private' 'collectors' 'Invoke-ArgCollector.ps1') -Raw
        $collector | Should -Match "-join\s+'\s*\|\s*'"
    }
}

Describe 'Regression: scoped variable interpolation in renderers' {
    It "uses `${var} or -f instead of `$var: pattern (parse trap)" {
        # `"$page:"` is interpreted as a scoped variable read by PowerShell.
        # All callers of $page/$count/$index inside double-quoted strings must
        # use ${...} or -f to be safe.
        $files = Get-ChildItem (Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter') -Recurse -Filter '*.ps1'
        $bad = foreach ($f in $files) {
            $text = Get-Content $f.FullName -Raw
            if ($text -match '\$page:[^"]') { $f.FullName }
        }
        $bad | Should -BeNullOrEmpty
    }
}

Describe 'Compare-AzureEstateRun smoke' {
    BeforeAll {
        $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("aee-test-" + [Guid]::NewGuid().ToString('N'))
        $prev = Join-Path $tmp 'prev'
        $curr = Join-Path $tmp 'curr'
        New-Item -ItemType Directory -Force -Path $prev | Out-Null
        New-Item -ItemType Directory -Force -Path $curr | Out-Null

        $manPrev = [pscustomobject]@{
            resources = @(
                [pscustomobject]@{ azureId = '/r/a'; hash = 'sha256:aaaa' },
                [pscustomobject]@{ azureId = '/r/b'; hash = 'sha256:bbbb' }
            )
        }
        $manCurr = [pscustomobject]@{
            resources = @(
                [pscustomobject]@{ azureId = '/r/a'; hash = 'sha256:aaaa' },   # unchanged
                [pscustomobject]@{ azureId = '/r/b'; hash = 'sha256:bbbb2' },  # modified
                [pscustomobject]@{ azureId = '/r/c'; hash = 'sha256:cccc' }    # added
            )
        }
        $invPrev = @(
            [pscustomobject]@{ id = '/r/a'; location = 'westeurope'; sku = @{ name='S1' } },
            [pscustomobject]@{ id = '/r/b'; location = 'westeurope'; sku = @{ name='S1' } }
        )
        $invCurr = @(
            [pscustomobject]@{ id = '/r/a'; location = 'westeurope'; sku = @{ name='S1' } },
            [pscustomobject]@{ id = '/r/b'; location = 'northeurope'; sku = @{ name='S2' } },
            [pscustomobject]@{ id = '/r/c'; location = 'westeurope'; sku = @{ name='S1' } }
        )

        $manPrev | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $prev 'manifest.json') -Encoding utf8
        $manCurr | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $curr 'manifest.json') -Encoding utf8
        $invPrev | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $prev 'inventory.json') -Encoding utf8
        $invCurr | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $curr 'inventory.json') -Encoding utf8
    }

    It 'detects added, removed and modified resources with property paths' {
        $log = Compare-AzureEstateRun -Previous (Join-Path $tmp 'prev') -Current (Join-Path $tmp 'curr')
        $log.summary.added    | Should -Be 1
        $log.summary.removed  | Should -Be 0
        $log.summary.modified | Should -Be 1
        ($log.modified | Where-Object { $_.azureId -eq '/r/b' }).propertiesChanged | Should -Contain 'resource.location'
        Test-Path (Join-Path $tmp 'curr' 'diff' 'changelog.md') | Should -BeTrue
        Test-Path (Join-Path $tmp 'curr' 'diff' 'changelog.json') | Should -BeTrue
    }

    AfterAll {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
