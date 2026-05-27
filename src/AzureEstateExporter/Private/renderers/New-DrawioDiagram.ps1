$script:DrawioIconRoot = $null
$script:DrawioIconCache = @{}

$script:DrawioIconByType = @{
    'microsoft.compute/virtualmachines'                = 'vm'
    'microsoft.compute/virtualmachines/extensions'     = 'vm-extension'
    'microsoft.compute/virtualmachines/runcommands'    = 'vm-extension'
    'microsoft.compute/virtualmachinescalesets'        = 'vmss'
    'microsoft.compute/disks'                          = 'disk'
    'microsoft.compute/snapshots'                      = 'disk'
    'microsoft.containerservice/managedclusters'       = 'aks'
    'microsoft.containerregistry/registries'           = 'acr'
    'microsoft.web/sites'                              = 'app-service'
    'microsoft.web/serverfarms'                        = 'app-service-plan'
    'microsoft.web/staticsites'                        = 'static-web-app'
    'microsoft.storage/storageaccounts'                = 'storage'
    'microsoft.network/virtualnetworks'                = 'vnet'
    'microsoft.network/virtualnetworks/subnets'        = 'subnet'
    'microsoft.network/networkinterfaces'              = 'nic'
    'microsoft.network/networksecuritygroups'          = 'nsg'
    'microsoft.network/publicipaddresses'              = 'public-ip'
    'microsoft.network/routetables'                    = 'route-table'
    'microsoft.network/loadbalancers'                  = 'lb'
    'microsoft.network/applicationgateways'            = 'app-gateway'
    'microsoft.network/privateendpoints'               = 'private-endpoint'
    'microsoft.network/frontdoors'                     = 'front-door'
    'microsoft.sql/servers'                            = 'sql'
    'microsoft.sql/servers/databases'                  = 'sql'
    'microsoft.dbforpostgresql/flexibleservers'        = 'postgres'
    'microsoft.documentdb/databaseaccounts'            = 'cosmos'
    'microsoft.cache/redis'                            = 'redis'
    'microsoft.keyvault/vaults'                        = 'key-vault'
    'microsoft.managedidentity/userassignedidentities' = 'managed-identity'
    'microsoft.insights/components'                    = 'app-insights'
    'microsoft.operationalinsights/workspaces'         = 'log-analytics'
    'microsoft.eventgrid/systemtopics'                 = 'event-grid'
    'microsoft.eventhub/namespaces'                    = 'event-hub'
    'microsoft.servicebus/namespaces'                  = 'service-bus'
    'microsoft.apimanagement/service'                  = 'apim'
}

# Network-topology homes for resources that don`t live INSIDE a subnet.
$script:DrawioBandByType = @{
    'microsoft.network/publicipaddresses'      = 'edge'
    'microsoft.network/frontdoors'             = 'edge'
    'microsoft.network/applicationgateways'    = 'edge'
    'microsoft.network/loadbalancers'          = 'edge'
    'microsoft.apimanagement/service'          = 'edge'
    'microsoft.storage/storageaccounts'        = 'platform'
    'microsoft.sql/servers'                    = 'platform'
    'microsoft.sql/servers/databases'          = 'platform'
    'microsoft.dbforpostgresql/flexibleservers'= 'platform'
    'microsoft.documentdb/databaseaccounts'    = 'platform'
    'microsoft.cache/redis'                    = 'platform'
    'microsoft.keyvault/vaults'                = 'platform'
    'microsoft.managedidentity/userassignedidentities' = 'platform'
    'microsoft.containerregistry/registries'   = 'platform'
    'microsoft.web/sites'                      = 'platform'
    'microsoft.web/serverfarms'                = 'platform'
    'microsoft.web/staticsites'                = 'platform'
    'microsoft.containerservice/managedclusters'= 'platform'
    'microsoft.compute/disks'                  = 'platform'
    'microsoft.compute/snapshots'              = 'platform'
    'microsoft.compute/virtualmachines'        = 'platform'
    'microsoft.compute/virtualmachinescalesets'= 'platform'
    'microsoft.insights/components'            = 'observability'
    'microsoft.operationalinsights/workspaces' = 'observability'
    'microsoft.eventgrid/systemtopics'         = 'observability'
    'microsoft.eventhub/namespaces'            = 'observability'
    'microsoft.servicebus/namespaces'          = 'observability'
}

$script:DrawioBandSpec = @{
    edge          = @{ Title = 'Internet / Edge';     Fill = '#F0F9FF'; Stroke = '#0EA5E9' }
    platform      = @{ Title = 'Platform services';   Fill = '#FAFAF9'; Stroke = '#737373' }
    observability = @{ Title = 'Observability';       Fill = '#F5F0F8'; Stroke = '#6C4E80' }
    other         = @{ Title = 'Other';               Fill = '#FAFAFA'; Stroke = '#A1A1AA' }
}

function Get-DrawioIconDataUri {
    param([string]$IconName)
    if (-not $IconName) { $IconName = '_default' }
    if ($script:DrawioIconCache.ContainsKey($IconName)) { return $script:DrawioIconCache[$IconName] }
    if (-not $script:DrawioIconRoot) {
        $script:DrawioIconRoot = Join-Path $PSScriptRoot '..' '..' 'Assets' 'icons'
    }
    $path = Join-Path $script:DrawioIconRoot "$IconName.svg"
    if (-not (Test-Path $path)) { $path = Join-Path $script:DrawioIconRoot '_default.svg' }
    $uri = if (Test-Path $path) {
        "data:image/svg+xml;base64," + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
    } else { '' }
    $script:DrawioIconCache[$IconName] = $uri
    return $uri
}

function Get-DrawioShapeStyle {
    param([string]$Type)
    $iconName = if ($script:DrawioIconByType.ContainsKey($Type.ToLowerInvariant())) {
        $script:DrawioIconByType[$Type.ToLowerInvariant()]
    } else { '_default' }
    $uri = Get-DrawioIconDataUri $iconName
    if ([string]::IsNullOrEmpty($uri)) {
        return 'rounded=1;whiteSpace=wrap;html=1;fillColor=#0078D4;strokeColor=#0067BB;fontColor=#FFFFFF;fontSize=10;'
    }
    return "shape=image;html=1;image=$uri;labelBackgroundColor=#FFFFFF;labelPosition=center;verticalLabelPosition=bottom;align=center;verticalAlign=top;imageAspect=0;fontSize=10;"
}

function Get-DrawioSafeId {
    param([string]$AzId)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($AzId.ToLowerInvariant())
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hex = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 10).ToLower()
    return "r_$hex"
}

function Get-DrawioEscaped {
    param([string]$S)
    if ([string]::IsNullOrEmpty($S)) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($S)
}

function Write-DrawioBand {
    param(
        [Parameter(Mandatory)] [pscustomobject]$Band,
        [Parameter(Mandatory)] [string]$ParentId,
        [Parameter(Mandatory)] [int]$X,
        [Parameter(Mandatory)] [int]$Y,
        [Parameter(Mandatory)] [int]$W,
        [Parameter(Mandatory)] [System.Text.StringBuilder]$Cells,
        [Parameter(Mandatory)] [ref]$CellIdRef,
        [Parameter(Mandatory)] [hashtable]$Declared,
        [hashtable]$PrivateLinkTargets = @{}
    )
    $spec = $script:DrawioBandSpec[$Band.Name]
    $bandCellId = "band_$($CellIdRef.Value)"; $CellIdRef.Value++
    [void]$Cells.AppendLine(@"
<mxCell id="$bandCellId" value="$(Get-DrawioEscaped $spec.Title)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=$($spec.Fill);strokeColor=$($spec.Stroke);strokeWidth=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=12;spacingTop=4;fontSize=11;fontStyle=2;fontColor=#475569;" vertex="1" parent="$ParentId">
  <mxGeometry x="$X" y="$Y" width="$W" height="$($Band.Height)" as="geometry" />
</mxCell>
"@)
    $iconW = 80; $iconH = 80; $iconColGap = 50; $iconRowGap = 70; $bandPadTop = 32; $bandPadX = 22
    $i = 0
    foreach ($r in @($Band.Resources) | Sort-Object type, name) {
        $col = $i % 8
        $row = [math]::Floor($i / 8)
        $rx = $bandPadX + $col * ($iconW + $iconColGap)
        $ry = $bandPadTop + $row * ($iconH + $iconRowGap)
        $rIdLower = $r.id.ToLowerInvariant()
        $rid = Get-DrawioSafeId $r.id
        $Declared[$rid] = $true
        $shortType = ($r.type -split '/')[-1]
        $hasPE = $PrivateLinkTargets.ContainsKey($rIdLower)
        $prefix = if ($hasPE) { '🔒 ' } else { '' }
        $label = "$prefix$(Get-DrawioEscaped $r.name)&#10;<font style='font-size:9px;color:#6a7388;'>$(Get-DrawioEscaped $shortType)</font>"
        $style = Get-DrawioShapeStyle $r.type
        [void]$Cells.AppendLine(@"
<mxCell id="$rid" value="$label" style="$style" vertex="1" parent="$bandCellId">
  <mxGeometry x="$rx" y="$ry" width="$iconW" height="$iconH" as="geometry" />
</mxCell>
"@)
        $i++
    }
}

function New-DrawioDiagram {
    <#
    .SYNOPSIS
        Renders the estate as a drawio (diagrams.net) XML file in the style of
        the Microsoft Azure architecture reference diagrams.
    .DESCRIPTION
        v0.6.1 rewrite. Resources are grouped by **network topology** instead
        of the old "5 horizontal bands by category" layout:

          Internet / Edge (top)
          Virtual Network → Subnet → resources inside the subnet
          Platform services (Storage, KV, SQL, ...) — PaaS without a subnet home
          Observability (App Insights, Log Analytics, ...)
          Other (anything we don`t recognise)

        Resource homes come from the inferred edges (`in-subnet` and
        `private-endpoint-to`) plus a VM→NIC traversal so VMs sit beside
        their NICs inside the right subnet.

        Icons are embedded as base64 SVG data URIs (v0.5.1) so the file
        renders the same in app.diagrams.net, VS Code Draw.io Integration
        and Draw.io Desktop without setup.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Model,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    # ────────────────────────────────────────────────────────────────────
    # Topology discovery from the inferred edges
    # ────────────────────────────────────────────────────────────────────
    $subnetMembers = @{}            # subnetId(lower) -> [resourceId]
    $nicToSubnet = @{}              # nicId(lower) -> subnetId
    $vmToNic = @{}                  # vmId(lower) -> nicId
    $privateLinkTargets = @{}       # paas resource id (lower) -> PE id (lower)

    foreach ($e in $Model.Graph.edges) {
        $rel = "$($e.relation)".ToLowerInvariant()
        $from = "$($e.from)".ToLowerInvariant()
        $to = "$($e.to)".ToLowerInvariant()
        if ($rel -eq 'in-subnet') {
            if (-not $subnetMembers.ContainsKey($to)) { $subnetMembers[$to] = New-Object System.Collections.Generic.List[string] }
            [void]$subnetMembers[$to].Add($from)
            $srcInv = $Model.Inventory | Where-Object { $_.id.ToLowerInvariant() -eq $from } | Select-Object -First 1
            if ($srcInv -and "$($srcInv.type)".ToLowerInvariant() -eq 'microsoft.network/networkinterfaces') {
                $nicToSubnet[$from] = $to
            }
        }
        elseif ($rel -eq 'private-endpoint-to') {
            $privateLinkTargets[$to] = $from
        }
    }
    # VM → first NIC (from the raw VM properties — not exposed by the edge
    # inference under a clean relation name).
    foreach ($r in $Model.Inventory | Where-Object { "$($_.type)".ToLowerInvariant() -eq 'microsoft.compute/virtualmachines' }) {
        $nics = @($r.properties.networkProfile.networkInterfaces) | Where-Object { $_.id } | Select-Object -First 1
        if ($nics) { $vmToNic[$r.id.ToLowerInvariant()] = $nics.id.ToLowerInvariant() }
    }

    $bySub = $Model.Inventory | Group-Object subscriptionId | Sort-Object Name
    $multiSub = ($bySub.Count -gt 1)

    $cells = New-Object System.Text.StringBuilder
    [void]$cells.AppendLine('<mxCell id="0" />')
    [void]$cells.AppendLine('<mxCell id="1" parent="0" />')

    $cellId = 100
    $declared = @{}

    # Layout constants
    $iconW = 80; $iconH = 80
    $iconColGap = 50; $iconRowGap = 70
    $subnetPadTop = 30; $subnetPadX = 18
    $vnetPadTop = 38; $vnetPadX = 22
    $rgPadTop = 50; $rgPadX = 24
    $rgWidth = 1100
    $subPadTop = 50; $subPadX = 30

    $subX = 60; $subY = 60

    foreach ($subGroup in $bySub) {
        $rgsInSub = $subGroup.Group | Group-Object resourceGroup | Sort-Object Name
        $rgLayouts = New-Object System.Collections.Generic.List[pscustomobject]
        $subInnerH = 0

        foreach ($rg in $rgsInSub) {
            $rgInv = @($rg.Group)
            $vnets   = $rgInv | Where-Object { "$($_.type)".ToLowerInvariant() -eq 'microsoft.network/virtualnetworks' }
            # Subnets can show up either as standalone ARG rows OR embedded in
            # the VNet`s `properties.subnets`. ARG typically does the latter, so
            # we synthesise lightweight pseudo-resources from each VNet`s props
            # and merge them with any standalone subnet rows we found.
            $standaloneSubnets = $rgInv | Where-Object { "$($_.type)".ToLowerInvariant() -eq 'microsoft.network/virtualnetworks/subnets' }
            $embeddedSubnets = New-Object System.Collections.Generic.List[pscustomobject]
            foreach ($vnet in $vnets) {
                foreach ($sn in @($vnet.properties.subnets)) {
                    if (-not $sn.id) { continue }
                    $alreadyHave = $standaloneSubnets | Where-Object { $_.id -ieq $sn.id }
                    if ($alreadyHave) { continue }
                    $embeddedSubnets.Add([pscustomobject]@{
                        id             = $sn.id
                        name           = $sn.name
                        type           = 'microsoft.network/virtualnetworks/subnets'
                        subscriptionId = $vnet.subscriptionId
                        resourceGroup  = $vnet.resourceGroup
                        properties     = $sn.properties
                    })
                }
            }
            $subnets = @($standaloneSubnets) + @($embeddedSubnets)
            $subnetParent = @{}
            foreach ($sn in $subnets) {
                $parentVnet = ($sn.id -replace '/subnets/[^/]+$','').ToLowerInvariant()
                $subnetParent[$sn.id.ToLowerInvariant()] = $parentVnet
            }

            # Walk every resource`s properties for a "subnet" / "subnet.id"
            # reference and stash the match so we can place that resource
            # inside the right subnet container. This is broader than the
            # inferred-edges lookup because the embedded subnets don`t
            # generate `in-subnet` edges (their IDs aren`t in the inventory
            # idSet at edge-inference time).
            $resourceSubnet = @{}    # resource id (lower) -> subnet id (lower)
            $subnetIdsLower = @($subnets | ForEach-Object { $_.id.ToLowerInvariant() })
            foreach ($r in $rgInv) {
                $rid = $r.id.ToLowerInvariant()
                if (-not $r.properties) { continue }
                $json = $r.properties | ConvertTo-Json -Depth 12 -Compress -ErrorAction SilentlyContinue
                if (-not $json) { continue }
                foreach ($snIdLower in $subnetIdsLower) {
                    if ($json.ToLower().Contains($snIdLower)) {
                        $resourceSubnet[$rid] = $snIdLower
                        break
                    }
                }
            }

            # Decide each non-network resource`s home (subnet or band).
            $subnetResources = @{}
            $bandResources = @{
                edge          = New-Object System.Collections.Generic.List[pscustomobject]
                platform      = New-Object System.Collections.Generic.List[pscustomobject]
                observability = New-Object System.Collections.Generic.List[pscustomobject]
                other         = New-Object System.Collections.Generic.List[pscustomobject]
            }
            foreach ($r in $rgInv) {
                $rid = $r.id.ToLowerInvariant()
                $rtype = "$($r.type)".ToLowerInvariant()
                if ($rtype -in 'microsoft.network/virtualnetworks','microsoft.network/virtualnetworks/subnets') {
                    continue
                }
                # 1. Subnet home from inferred edges (in-subnet relation).
                $foundSubnet = $null
                foreach ($snId in $subnetMembers.Keys) {
                    if ($subnetMembers[$snId] -contains $rid) { $foundSubnet = $snId; break }
                }
                # 2. Subnet home from properties scan (resourceSubnet map).
                if (-not $foundSubnet -and $resourceSubnet.ContainsKey($rid)) {
                    $foundSubnet = $resourceSubnet[$rid]
                }
                # 3. VMs: bubble up through their NIC.
                if (-not $foundSubnet -and $rtype -eq 'microsoft.compute/virtualmachines') {
                    $nicId = $vmToNic[$rid]
                    if ($nicId) {
                        if ($nicToSubnet.ContainsKey($nicId)) { $foundSubnet = $nicToSubnet[$nicId] }
                        elseif ($resourceSubnet.ContainsKey($nicId)) { $foundSubnet = $resourceSubnet[$nicId] }
                    }
                }
                if ($foundSubnet -and $subnetParent.ContainsKey($foundSubnet)) {
                    if (-not $subnetResources.ContainsKey($foundSubnet)) {
                        $subnetResources[$foundSubnet] = New-Object System.Collections.Generic.List[pscustomobject]
                    }
                    [void]$subnetResources[$foundSubnet].Add($r)
                    continue
                }
                $band = if ($script:DrawioBandByType.ContainsKey($rtype)) {
                    $script:DrawioBandByType[$rtype]
                } else { 'other' }
                [void]$bandResources[$band].Add($r)
            }

            # VNet layouts (subnets stacked vertically inside each VNet)
            $vnetLayouts = New-Object System.Collections.Generic.List[pscustomobject]
            foreach ($vnet in $vnets) {
                $vnetId = $vnet.id.ToLowerInvariant()
                $childSubnets = $subnets | Where-Object { $subnetParent[$_.id.ToLowerInvariant()] -eq $vnetId } | Sort-Object name
                $subnetSizes = New-Object System.Collections.Generic.List[pscustomobject]
                $vnetInnerH = 0
                foreach ($sn in $childSubnets) {
                    $snId = $sn.id.ToLowerInvariant()
                    $inside = if ($subnetResources.ContainsKey($snId)) { @($subnetResources[$snId]) } else { @() }
                    $count = [math]::Max(1, $inside.Count)
                    $rows = [math]::Ceiling($count / 6)
                    $snH = $subnetPadTop + ($rows * $iconH + ($rows - 1) * $iconRowGap) + 20
                    $snW = $rgWidth - $vnetPadX * 2 - 30
                    $subnetSizes.Add([pscustomobject]@{ Subnet = $sn; Resources = $inside; Width = $snW; Height = $snH })
                    $vnetInnerH += $snH + 16
                }
                $vnetH = $vnetPadTop + [math]::Max($vnetInnerH, 80) + 20
                $vnetLayouts.Add([pscustomobject]@{ Vnet = $vnet; Subnets = $subnetSizes; Width = $rgWidth - $rgPadX * 2; Height = $vnetH })
            }

            # Band layouts (non-empty only)
            $bandLayouts = New-Object System.Collections.Generic.List[pscustomobject]
            foreach ($b in 'edge','platform','observability','other') {
                $rs = @($bandResources[$b])
                if ($rs.Count -eq 0) { continue }
                $count = $rs.Count
                $rows = [math]::Ceiling($count / 8)
                $bandH = 32 + ($rows * $iconH + ($rows - 1) * $iconRowGap) + 20
                $bandLayouts.Add([pscustomobject]@{ Name = $b; Resources = $rs; Width = $rgWidth - $rgPadX * 2; Height = $bandH })
            }

            $rgInnerH = 0
            foreach ($v in $vnetLayouts) { $rgInnerH += $v.Height + 24 }
            foreach ($b in $bandLayouts) { $rgInnerH += $b.Height + 24 }
            $rgH = $rgPadTop + [math]::Max($rgInnerH, 160) + 20

            $rgLayouts.Add([pscustomobject]@{
                Rg = $rg.Name; Width = $rgWidth; Height = $rgH;
                Vnets = $vnetLayouts; Bands = $bandLayouts
            })
            $subInnerH += $rgH + 40
        }

        $subH = [math]::Max($subInnerH + 80, 240)
        $subW = $rgWidth + $subPadX * 2 + 40

        $subContainerId = $null
        if ($multiSub) {
            $subContainerId = "sub_$cellId"; $cellId++
            [void]$cells.AppendLine(@"
<mxCell id="$subContainerId" value="Subscription: $(Get-DrawioEscaped $subGroup.Name)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FAFBFD;strokeColor=#444444;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;fontSize=13;fontStyle=1;" vertex="1" parent="1">
  <mxGeometry x="$subX" y="$subY" width="$subW" height="$subH" as="geometry" />
</mxCell>
"@)
        }

        $rgX = if ($multiSub) { $subPadX } else { 60 }
        $rgY = if ($multiSub) { $subPadTop } else { 60 }

        foreach ($layout in $rgLayouts) {
            $rgId = "rg_$cellId"; $cellId++
            $parentForRg = if ($multiSub) { $subContainerId } else { '1' }
            [void]$cells.AppendLine(@"
<mxCell id="$rgId" value="Resource group: $(Get-DrawioEscaped $layout.Rg)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#5C7C99;strokeWidth=1.5;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;spacingTop=4;fontSize=12;fontStyle=1;" vertex="1" parent="$parentForRg">
  <mxGeometry x="$rgX" y="$rgY" width="$($layout.Width)" height="$($layout.Height)" as="geometry" />
</mxCell>
"@)

            $sectionY = $rgPadTop

            # 1. Edge band on top
            $edgeBand = $layout.Bands | Where-Object { $_.Name -eq 'edge' } | Select-Object -First 1
            if ($edgeBand) {
                Write-DrawioBand -Band $edgeBand -ParentId $rgId -X $rgPadX -Y $sectionY -W ($layout.Width - $rgPadX * 2) -Cells $cells -CellIdRef ([ref]$cellId) -Declared $declared
                $sectionY += $edgeBand.Height + 24
            }

            # 2. Virtual networks with subnets nested inside
            foreach ($v in $layout.Vnets) {
                $vnetCellId = "vnet_$cellId"; $cellId++
                [void]$cells.AppendLine(@"
<mxCell id="$vnetCellId" value="Virtual network: $(Get-DrawioEscaped $v.Vnet.name)" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#F0FAFF;strokeColor=#0078D4;strokeWidth=1.5;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;spacingTop=6;fontSize=11;fontStyle=2;fontColor=#0078D4;" vertex="1" parent="$rgId">
  <mxGeometry x="$rgPadX" y="$sectionY" width="$($v.Width)" height="$($v.Height)" as="geometry" />
</mxCell>
"@)
                $declared[(Get-DrawioSafeId $v.Vnet.id)] = $true

                $subnetY = $vnetPadTop
                foreach ($sn in $v.Subnets) {
                    $snCellId = "snet_$cellId"; $cellId++
                    [void]$cells.AppendLine(@"
<mxCell id="$snCellId" value="Subnet: $(Get-DrawioEscaped (($sn.Subnet.name -split '/')[-1]))" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#7FB1E6;strokeWidth=1;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=12;spacingTop=4;fontSize=10;fontStyle=2;fontColor=#3A6FB0;" vertex="1" parent="$vnetCellId">
  <mxGeometry x="$vnetPadX" y="$subnetY" width="$($sn.Width)" height="$($sn.Height)" as="geometry" />
</mxCell>
"@)
                    $declared[(Get-DrawioSafeId $sn.Subnet.id)] = $true

                    $i = 0
                    foreach ($r in @($sn.Resources) | Sort-Object type, name) {
                        $col = $i % 6
                        $row = [math]::Floor($i / 6)
                        $rx = $subnetPadX + $col * ($iconW + $iconColGap)
                        $ry = $subnetPadTop + $row * ($iconH + $iconRowGap)
                        $id = Get-DrawioSafeId $r.id
                        $declared[$id] = $true
                        $shortType = ($r.type -split '/')[-1]
                        $isPE = ("$($r.type)".ToLowerInvariant() -eq 'microsoft.network/privateendpoints')
                        $prefix = if ($isPE) { '🔒 ' } else { '' }
                        $label = "$prefix$(Get-DrawioEscaped $r.name)&#10;<font style='font-size:9px;color:#6a7388;'>$(Get-DrawioEscaped $shortType)</font>"
                        $style = Get-DrawioShapeStyle $r.type
                        [void]$cells.AppendLine(@"
<mxCell id="$id" value="$label" style="$style" vertex="1" parent="$snCellId">
  <mxGeometry x="$rx" y="$ry" width="$iconW" height="$iconH" as="geometry" />
</mxCell>
"@)
                        $i++
                    }
                    $subnetY += $sn.Height + 16
                }

                $sectionY += $v.Height + 24
            }

            # 3. Platform services
            $platBand = $layout.Bands | Where-Object { $_.Name -eq 'platform' } | Select-Object -First 1
            if ($platBand) {
                Write-DrawioBand -Band $platBand -ParentId $rgId -X $rgPadX -Y $sectionY -W ($layout.Width - $rgPadX * 2) -Cells $cells -CellIdRef ([ref]$cellId) -Declared $declared -PrivateLinkTargets $privateLinkTargets
                $sectionY += $platBand.Height + 24
            }

            # 4. Observability
            $obsBand = $layout.Bands | Where-Object { $_.Name -eq 'observability' } | Select-Object -First 1
            if ($obsBand) {
                Write-DrawioBand -Band $obsBand -ParentId $rgId -X $rgPadX -Y $sectionY -W ($layout.Width - $rgPadX * 2) -Cells $cells -CellIdRef ([ref]$cellId) -Declared $declared
                $sectionY += $obsBand.Height + 24
            }

            # 5. Other
            $otherBand = $layout.Bands | Where-Object { $_.Name -eq 'other' } | Select-Object -First 1
            if ($otherBand) {
                Write-DrawioBand -Band $otherBand -ParentId $rgId -X $rgPadX -Y $sectionY -W ($layout.Width - $rgPadX * 2) -Cells $cells -CellIdRef ([ref]$cellId) -Declared $declared
            }

            $rgY += $layout.Height + 40
        }

        $subY += $subH + 40
    }

    # Edges — skip in-subnet/in-vnet (the nesting conveys them visually).
    $edgeId = 5000
    foreach ($e in $Model.Graph.edges) {
        $rel = "$($e.relation)".ToLowerInvariant()
        if ($rel -in 'in-subnet','in-vnet') { continue }
        $from = Get-DrawioSafeId $e.from
        $to   = Get-DrawioSafeId $e.to
        if (-not $declared.ContainsKey($from) -or -not $declared.ContainsKey($to)) { continue }
        $relLabel = Get-DrawioEscaped $e.relation
        [void]$cells.AppendLine(@"
<mxCell id="e_$edgeId" value="$relLabel" style="endArrow=classic;html=1;rounded=1;curved=1;strokeColor=#7E7E7E;strokeWidth=1.2;fontSize=9;fontColor=#475569;labelBackgroundColor=#FFFFFF;labelBorderColor=#E2E8F0;" edge="1" parent="1" source="$from" target="$to">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
"@)
        $edgeId++
    }

    $diagramId = [guid]::NewGuid().ToString('N')
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="azure-estate-exporter" agent="azure-estate-exporter" type="device">
  <diagram name="Estate" id="$diagramId">
    <mxGraphModel dx="1800" dy="1100" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1700" pageHeight="1200" math="0" shadow="0">
      <root>
$($cells.ToString())
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
"@

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write drawio diagram')) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $xml | Set-Content -Path $OutputPath -Encoding utf8
        Write-EstateLog "Drawio diagram -> $OutputPath" -Level Success
    }
}
