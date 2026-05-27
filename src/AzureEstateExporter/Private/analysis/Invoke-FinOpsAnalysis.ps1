function Invoke-FinOpsAnalysis {
    <#
    .SYNOPSIS
        Derives FinOps recommendations from the already-collected inventory
        and cost data.

    .DESCRIPTION
        Pure analysis step — NO Azure calls. Walks the normalised inventory
        and (optionally) cross-references per-resource cost data to produce
        actionable recommendations:

          1. UnattachedDisk           Managed disk with no `managedBy`.
          2. UnattachedPublicIp       Public IP with no `ipConfiguration` reference.
          3. EmptyAppServicePlan      Service plan with no sites hosted on it.
          4. GrsStorageOnNonProd      Storage account using GRS/RAGRS where the
                                      RG tag/name suggests dev/test.
          5. PremiumDiskUnderused     Premium SSD/Ultra disk under 256 GB
                                      (cheaper StandardSSD class might fit).
          6. OversizedVm              VM SKU heuristic (D-/E-/M-series at 32+ vCPU).
          7. AppInsightsClassic       App Insights without a Workspace Resource
                                      Id (classic mode — workspace-based AI is
                                      the recommended target).

        Each finding is severity-graded (`Low`/`Medium`/`High`) by potential
        savings, and tries to attach an `estimatedMonthlySavings` figure when
        per-resource cost data is available. The estimate is necessarily a
        guess — the report should call that out, not present it as truth.

    .PARAMETER Inventory
        Normalised inventory rows from ConvertTo-EstateModel.

    .PARAMETER CostByResource
        Optional. Array of `{ resourceId, cost, currency }` rows produced by
        Invoke-CostCollector`s ByResource pass.

    .OUTPUTS
        [pscustomobject] with members:
          .Findings            severity-graded recommendation array
          .TopSpenders         top 10 resources by cost (cross-cuts inventory)
          .ServiceMix          { service, totalCost, percentOfTotal }
          .Headline            { totalMonthlyCost, currency, potentialSavings }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Inventory,

        [Parameter()]
        [AllowEmptyCollection()]
        [pscustomobject[]]$CostByResource = @()
    )

    $findings = New-Object System.Collections.Generic.List[pscustomobject]
    $costMap = @{}
    foreach ($c in $CostByResource) {
        if ($c.resourceId) { $costMap[$c.resourceId.ToLower()] = $c }
    }
    $currency = if ($CostByResource.Count -gt 0) { $CostByResource[0].currency } else { 'USD' }

    function Get-Cost {
        param([string]$Id)
        if ([string]::IsNullOrEmpty($Id)) { return $null }
        return $costMap[$Id.ToLower()]
    }

    function Add-Finding {
        param(
            [string]$Severity, [string]$Type, [string]$Title,
            [pscustomobject]$R, [string]$Evidence, [string]$Recommendation,
            [double]$EstimatedMonthlySavings = 0
        )
        $findings.Add([pscustomobject]@{
            severity                  = $Severity
            type                      = $Type
            title                     = $Title
            resourceId                = if ($R) { $R.id } else { $null }
            resourceName              = if ($R) { $R.name } else { $null }
            resourceType              = if ($R) { $R.type } else { $null }
            subscriptionId            = if ($R) { $R.subscriptionId } else { $null }
            resourceGroup             = if ($R) { $R.resourceGroup } else { $null }
            evidence                  = $Evidence
            recommendation            = $Recommendation
            estimatedMonthlySavings   = $EstimatedMonthlySavings
            currency                  = $currency
        }) | Out-Null
    }

    # Index by type for quick lookup
    $byType = @{}
    foreach ($r in $Inventory) {
        $t = $r.type.ToLowerInvariant()
        if (-not $byType.ContainsKey($t)) { $byType[$t] = New-Object System.Collections.Generic.List[pscustomobject] }
        $byType[$t].Add($r)
    }

    # 1. Unattached managed disks
    foreach ($d in @($byType['microsoft.compute/disks'])) {
        if (-not $d) { continue }
        if ([string]::IsNullOrEmpty($d.managedBy)) {
            $cost = Get-Cost $d.id
            $monthly = if ($cost) { $cost.cost } else { 0 }
            $sev = if ($monthly -gt 50) { 'High' } elseif ($monthly -gt 5) { 'Medium' } else { 'Low' }
            Add-Finding -Severity $sev -Type 'UnattachedDisk' `
                -Title ("Managed disk ``{0}`` is not attached to any VM" -f $d.name) `
                -R $d `
                -Evidence ("managedBy is empty; sku={0}; sizeGb={1}" -f $d.sku.name, $d.properties.diskSizeGB) `
                -Recommendation 'Delete the disk or snapshot it and delete the source. Unattached disks bill at full rate.' `
                -EstimatedMonthlySavings $monthly
        }
    }

    # 2. Unattached Public IPs
    foreach ($pip in @($byType['microsoft.network/publicipaddresses'])) {
        if (-not $pip) { continue }
        $hasCfg = $pip.properties.ipConfiguration -and $pip.properties.ipConfiguration.id
        if (-not $hasCfg) {
            $cost = Get-Cost $pip.id
            $monthly = if ($cost) { $cost.cost } else { 4 } # Standard PIP ~$3-4/mo
            $sev = if ($monthly -gt 5) { 'Medium' } else { 'Low' }
            Add-Finding -Severity $sev -Type 'UnattachedPublicIp' `
                -Title ("Public IP ``{0}`` is not associated with any resource" -f $pip.name) `
                -R $pip `
                -Evidence ("sku={0}; allocation={1}" -f $pip.sku.name, $pip.properties.publicIPAllocationMethod) `
                -Recommendation 'Delete the Public IP or attach it to a resource. Standard SKU PIPs bill even when idle.' `
                -EstimatedMonthlySavings $monthly
        }
    }

    # 3. App Service plans with no hosted sites
    $plans = @($byType['microsoft.web/serverfarms'])
    $sites = @($byType['microsoft.web/sites'])
    foreach ($plan in $plans) {
        if (-not $plan) { continue }
        $hosted = $sites | Where-Object { $_.properties.serverFarmId -and $_.properties.serverFarmId.ToLower() -eq $plan.id.ToLower() }
        if (-not $hosted) {
            $cost = Get-Cost $plan.id
            $monthly = if ($cost) { $cost.cost } else { 0 }
            $sev = if ($monthly -gt 50) { 'High' } elseif ($monthly -gt 10) { 'Medium' } else { 'Low' }
            Add-Finding -Severity $sev -Type 'EmptyAppServicePlan' `
                -Title ("App Service Plan ``{0}`` has no sites hosted on it" -f $plan.name) `
                -R $plan `
                -Evidence ("sku={0}; tier={1}" -f $plan.sku.name, $plan.sku.tier) `
                -Recommendation 'Delete the empty plan or scale it down to Free/Shared. Dedicated plans bill regardless of site count.' `
                -EstimatedMonthlySavings $monthly
        }
    }

    # 4. GRS / RAGRS storage on dev/test RGs
    foreach ($sa in @($byType['microsoft.storage/storageaccounts'])) {
        if (-not $sa) { continue }
        $replType = "$($sa.sku.name)"
        if ($replType -match 'GRS|RAGRS') {
            $rgLower = "$($sa.resourceGroup)".ToLowerInvariant()
            $tagEnv = "$($sa.tags.environment)$($sa.tags.Environment)$($sa.tags.env)$($sa.tags.Env)".ToLowerInvariant()
            $isNonProd = ($rgLower -match 'dev|test|qa|staging|sandbox' -or $tagEnv -match 'dev|test|qa|staging|sandbox')
            if ($isNonProd) {
                $cost = Get-Cost $sa.id
                $monthly = if ($cost) { $cost.cost } else { 0 }
                # GRS roughly 2x LRS price. Savings = half the current spend.
                $savings = if ($monthly -gt 0) { [math]::Round($monthly * 0.5, 2) } else { 0 }
                $sev = if ($savings -gt 50) { 'Medium' } else { 'Low' }
                Add-Finding -Severity $sev -Type 'GrsStorageOnNonProd' `
                    -Title ("Storage account ``{0}`` uses {1} replication on a {2} RG" -f $sa.name, $replType, ($rgLower -match 'prod' ? 'production-named' : 'non-production')) `
                    -R $sa `
                    -Evidence ("sku.name={0}; rg={1}; envTag={2}" -f $replType, $rgLower, ($tagEnv -ne '' ? $tagEnv : 'n/a')) `
                    -Recommendation 'Consider LRS (Locally-Redundant Storage) for non-production data. GRS roughly doubles the storage cost vs LRS.' `
                    -EstimatedMonthlySavings $savings
            }
        }
    }

    # 5. Premium / Ultra disks that are small (StandardSSD often fits)
    foreach ($d in @($byType['microsoft.compute/disks'])) {
        if (-not $d) { continue }
        $sku = "$($d.sku.name)"
        $sizeGb = [int]$d.properties.diskSizeGB
        if (($sku -match 'Premium|UltraSSD') -and $sizeGb -gt 0 -and $sizeGb -lt 256) {
            $cost = Get-Cost $d.id
            $monthly = if ($cost) { $cost.cost } else { 0 }
            # Premium → StandardSSD typically halves cost.
            $savings = if ($monthly -gt 0) { [math]::Round($monthly * 0.5, 2) } else { 0 }
            Add-Finding -Severity 'Low' -Type 'PremiumDiskSmall' `
                -Title ("{0} disk ``{1}`` is only {2} GB" -f $sku, $d.name, $sizeGb) `
                -R $d `
                -Evidence ("sku={0}; sizeGb={1}" -f $sku, $sizeGb) `
                -Recommendation 'Evaluate StandardSSD_LRS if the workload does not need >5000 IOPS or sub-ms latency.' `
                -EstimatedMonthlySavings $savings
        }
    }

    # 6. Oversized VMs (heuristic: D-/E-/M-series with 32+ vCPU)
    foreach ($vm in @($byType['microsoft.compute/virtualmachines'])) {
        if (-not $vm) { continue }
        $size = "$($vm.properties.hardwareProfile.vmSize)"
        if ($size -match '^Standard_[DEM]\d?\d?(?:s_v\d|_v\d)?\d*' -and $size -match '_(32|48|64|96|128)') {
            $cost = Get-Cost $vm.id
            $monthly = if ($cost) { $cost.cost } else { 0 }
            $sev = if ($monthly -gt 500) { 'High' } else { 'Medium' }
            Add-Finding -Severity $sev -Type 'OversizedVm' `
                -Title ("VM ``{0}`` is sized ``{1}`` — review utilisation" -f $vm.name, $size) `
                -R $vm `
                -Evidence ("vmSize={0}" -f $size) `
                -Recommendation 'Pull 7-30 day CPU + memory metrics; consider Burstable (B-series) or smaller D/E if averages stay under 40%.' `
                -EstimatedMonthlySavings ([math]::Round($monthly * 0.3, 2))
        }
    }

    # 7. Classic App Insights (no workspaceResourceId)
    foreach ($ai in @($byType['microsoft.insights/components'])) {
        if (-not $ai) { continue }
        $ws = "$($ai.properties.WorkspaceResourceId)$($ai.properties.workspaceResourceId)"
        if (-not $ws) {
            Add-Finding -Severity 'Low' -Type 'AppInsightsClassic' `
                -Title ("App Insights ``{0}`` is classic mode (no Log Analytics workspace)" -f $ai.name) `
                -R $ai `
                -Evidence 'WorkspaceResourceId is empty.' `
                -Recommendation 'Migrate to workspace-based App Insights. Microsoft is retiring classic AI; workspace mode also unifies billing with Log Analytics.' `
                -EstimatedMonthlySavings 0
        }
    }

    # Cross-cuts: top spenders, service mix, headline.
    $topSpenders = @()
    $serviceMix = New-Object System.Collections.Generic.List[pscustomobject]
    $totalCost = 0.0

    if ($CostByResource.Count -gt 0) {
        $idToInv = @{}
        foreach ($r in $Inventory) {
            if ($r.id) { $idToInv[$r.id.ToString().ToLower()] = $r }
        }
        $enriched = foreach ($c in $CostByResource) {
            if (-not $c.resourceId) { continue }
            $r = $idToInv[$c.resourceId.ToString().ToLower()]
            [pscustomobject]@{
                resourceId    = $c.resourceId
                name          = if ($r) { $r.name } else { ($c.resourceId -split '/')[-1] }
                type          = if ($r) { $r.type } else { 'n/a' }
                resourceGroup = if ($r) { $r.resourceGroup } else { ($c.resourceId -split '/')[4] }
                cost          = [double]$c.cost
                currency      = $c.currency
            }
        }
        $topSpenders = $enriched | Sort-Object cost -Descending | Select-Object -First 10
        $totalCost   = ($CostByResource | Measure-Object cost -Sum).Sum
        $byTypeCost  = $enriched | Group-Object type | ForEach-Object {
            [pscustomobject]@{
                serviceType    = $_.Name
                totalCost      = [math]::Round(($_.Group | Measure-Object cost -Sum).Sum, 2)
                resourceCount  = $_.Count
                percentOfTotal = if ($totalCost -gt 0) { [math]::Round(100 * ($_.Group | Measure-Object cost -Sum).Sum / $totalCost, 1) } else { 0 }
            }
        } | Sort-Object totalCost -Descending
        foreach ($r in $byTypeCost) { $serviceMix.Add($r) }
    }

    $potentialSavings = ($findings | Measure-Object -Property estimatedMonthlySavings -Sum).Sum
    $headline = [pscustomobject]@{
        totalMonthlyCost   = [math]::Round($totalCost, 2)
        currency           = $currency
        potentialSavings   = [math]::Round([double]$potentialSavings, 2)
        findingCount       = $findings.Count
        findingsBySeverity = $findings | Group-Object severity | ForEach-Object {
            [pscustomobject]@{ severity = $_.Name; count = $_.Count }
        }
    }

    $sevOrder = @{ 'High' = 0; 'Medium' = 1; 'Low' = 2 }
    return [pscustomobject]@{
        Findings    = @($findings | Sort-Object @{ Expression = { $sevOrder[$_.severity] } }, @{ Expression = { -$_.estimatedMonthlySavings } }, type, resourceName)
        TopSpenders = @($topSpenders)
        ServiceMix  = @($serviceMix)
        Headline    = $headline
    }
}
