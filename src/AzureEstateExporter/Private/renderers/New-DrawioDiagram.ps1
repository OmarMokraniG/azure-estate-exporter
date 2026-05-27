function New-DrawioDiagram {
    <#
    .SYNOPSIS
        Renders the estate as a drawio (diagrams.net) XML file with embedded
        SVG icons and an Azure-reference-architecture-style layered layout.

    .DESCRIPTION
        v0.5.1 redesign. The previous implementation referenced
        `mxgraph.azure.*` shape names which are NOT in diagrams.net`s
        bundled shape library (they live in the Microsoft "MSCAE" stencil
        which has to be enabled by hand). The result was blank squares
        when the file was opened.

        This version embeds each icon as a base64-encoded SVG data URI in
        the shape style:

            shape=image;html=1;image=data:image/svg+xml;base64,...

        That makes the file 100% self-contained and renders the same in
        app.diagrams.net, VS Code Draw.io Integration, or Draw.io Desktop
        whether or not the user has Azure stencils enabled.

        The layout follows Azure reference-architecture conventions:

            ┌─────────────────────────────────────────────────────────┐
            │  Subscription (only if multiple in scope)              │
            │  ┌───────────────────────────────────────────────────┐ │
            │  │  Resource group                                   │ │
            │  │  ┌─────────────────────────────────────────────┐  │ │
            │  │  │  Ingress / Edge (PIPs, Front Door, AppGw)   │  │ │
            │  │  └─────────────────────────────────────────────┘  │ │
            │  │  ┌─────────────────────────────────────────────┐  │ │
            │  │  │  Network (VNet, NIC, NSG, route table)      │  │ │
            │  │  └─────────────────────────────────────────────┘  │ │
            │  │  ┌─────────────────────────────────────────────┐  │ │
            │  │  │  Compute / Web (VM, App Service, AKS, ACR)  │  │ │
            │  │  └─────────────────────────────────────────────┘  │ │
            │  │  ┌─────────────────────────────────────────────┐  │ │
            │  │  │  Data / Security (SQL, Cosmos, KV, Storage) │  │ │
            │  │  └─────────────────────────────────────────────┘  │ │
            │  │  ┌─────────────────────────────────────────────┐  │ │
            │  │  │  Observability / Integration                │  │ │
            │  │  └─────────────────────────────────────────────┘  │ │
            │  └───────────────────────────────────────────────────┘ │
            └─────────────────────────────────────────────────────────┘

        Resources are placed into a band by category. Edges use the same
        `relation` labels the Mermaid renderer already produces.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Model,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    # ────────────────────────────────────────────────────────────────────
    # Icon catalogue: ARM type → SVG filename (without extension).
    # The actual SVGs live in `Assets/icons/` and are loaded lazily below.
    # ────────────────────────────────────────────────────────────────────
    $iconNameByType = @{
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

    # Category lookup → band index in the layered layout
    $categoryByType = @{
        # 0 = Ingress / edge
        'microsoft.network/publicipaddresses'      = 0
        'microsoft.network/frontdoors'             = 0
        'microsoft.network/applicationgateways'    = 0
        'microsoft.network/loadbalancers'          = 0
        'microsoft.apimanagement/service'          = 0
        # 1 = Network
        'microsoft.network/virtualnetworks'        = 1
        'microsoft.network/virtualnetworks/subnets'= 1
        'microsoft.network/networkinterfaces'      = 1
        'microsoft.network/networksecuritygroups'  = 1
        'microsoft.network/routetables'            = 1
        'microsoft.network/privateendpoints'       = 1
        # 2 = Compute / web
        'microsoft.compute/virtualmachines'        = 2
        'microsoft.compute/virtualmachines/extensions' = 2
        'microsoft.compute/virtualmachines/runcommands' = 2
        'microsoft.compute/virtualmachinescalesets'= 2
        'microsoft.containerservice/managedclusters'= 2
        'microsoft.containerregistry/registries'   = 2
        'microsoft.web/sites'                      = 2
        'microsoft.web/serverfarms'                = 2
        'microsoft.web/staticsites'                = 2
        # 3 = Data / security
        'microsoft.compute/disks'                  = 3
        'microsoft.compute/snapshots'              = 3
        'microsoft.storage/storageaccounts'        = 3
        'microsoft.sql/servers'                    = 3
        'microsoft.sql/servers/databases'          = 3
        'microsoft.dbforpostgresql/flexibleservers'= 3
        'microsoft.documentdb/databaseaccounts'    = 3
        'microsoft.cache/redis'                    = 3
        'microsoft.keyvault/vaults'                = 3
        'microsoft.managedidentity/userassignedidentities' = 3
        # 4 = Observability / integration
        'microsoft.insights/components'            = 4
        'microsoft.operationalinsights/workspaces' = 4
        'microsoft.eventgrid/systemtopics'         = 4
        'microsoft.eventhub/namespaces'            = 4
        'microsoft.servicebus/namespaces'          = 4
    }
    $bandTitle = @(
        'Internet / Edge', 'Network', 'Compute & Web', 'Data & Security', 'Observability & Integration'
    )
    $bandFill = @(
        '#FEF6E4', '#E7F0FB', '#E8F5E9', '#FCE8EA', '#F5F0F8'
    )
    $bandStroke = @(
        '#D89E2A', '#5C7C99', '#4E8C5A', '#B0455B', '#6C4E80'
    )

    # ────────────────────────────────────────────────────────────────────
    # SVG → base64 data URI cache.
    # Icons live next to this script under ../../Assets/icons/.
    # ────────────────────────────────────────────────────────────────────
    $iconRoot = Join-Path $PSScriptRoot '..' '..' 'Assets' 'icons'
    $iconCache = @{}
    function Get-IconDataUri {
        param([string]$IconName)
        if (-not $IconName) { $IconName = '_default' }
        if ($iconCache.ContainsKey($IconName)) { return $iconCache[$IconName] }
        $path = Join-Path $iconRoot "$IconName.svg"
        if (-not (Test-Path $path)) {
            $path = Join-Path $iconRoot '_default.svg'
        }
        if (Test-Path $path) {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $b64 = [Convert]::ToBase64String($bytes)
            $uri = "data:image/svg+xml;base64,$b64"
        } else {
            $uri = ''
        }
        $iconCache[$IconName] = $uri
        return $uri
    }

    function Get-ShapeStyle {
        param([string]$Type)
        $iconName = if ($iconNameByType.ContainsKey($Type.ToLowerInvariant())) {
            $iconNameByType[$Type.ToLowerInvariant()]
        } else { '_default' }
        $uri = Get-IconDataUri $iconName
        if ([string]::IsNullOrEmpty($uri)) {
            # Fallback when the icon file is missing — use a coloured rectangle
            # so the diagram still renders, just without the Azure icon.
            return 'rounded=1;whiteSpace=wrap;html=1;fillColor=#0072C6;strokeColor=#005A9E;fontColor=#FFFFFF;fontSize=10;'
        }
        return "shape=image;html=1;image=$uri;labelBackgroundColor=#FFFFFF;labelPosition=center;verticalLabelPosition=bottom;align=center;verticalAlign=top;imageAspect=0;fontSize=10;"
    }

    function Get-SafeId {
        param([string]$AzId)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($AzId.ToLowerInvariant())
        $sha = [System.Security.Cryptography.SHA1]::Create()
        $hex = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 10).ToLower()
        return "r_$hex"
    }

    function Get-Escaped {
        param([string]$S)
        if ([string]::IsNullOrEmpty($S)) { return '' }
        return [System.Net.WebUtility]::HtmlEncode($S)
    }

    # ────────────────────────────────────────────────────────────────────
    # Group resources by sub → RG → band.
    # ────────────────────────────────────────────────────────────────────
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
    $bandPadTop = 38      # space for band title
    $bandPadBottom = 16
    $bandPadX = 24
    $rgPadX = 28; $rgPadTop = 50
    $rgWidthMin = 880     # wider canvas → looks like a reference architecture
    $subPadX = 30; $subPadTop = 50

    $subX = 60; $subY = 60

    foreach ($subGroup in $bySub) {
        $rgsInSub = $subGroup.Group | Group-Object resourceGroup | Sort-Object Name

        # Pre-compute RG layouts so we can size containers correctly.
        $rgLayouts = New-Object System.Collections.Generic.List[pscustomobject]
        $subInnerH = 0; $subInnerW = 0

        foreach ($rg in $rgsInSub) {
            # Bucket resources into bands.
            $bands = @{}
            foreach ($r in $rg.Group) {
                $cat = if ($categoryByType.ContainsKey($r.type.ToLowerInvariant())) {
                    $categoryByType[$r.type.ToLowerInvariant()]
                } else { 5 }  # bucket for unknown types
                if (-not $bands.ContainsKey($cat)) { $bands[$cat] = New-Object System.Collections.Generic.List[pscustomobject] }
                [void]$bands[$cat].Add($r)
            }
            $nonEmptyBands = @($bands.Keys | Sort-Object)
            $iconsPerRow = 8

            # Compute band heights individually.
            $bandHeights = @{}
            foreach ($b in $nonEmptyBands) {
                $count = $bands[$b].Count
                $rows = [math]::Max(1, [math]::Ceiling($count / $iconsPerRow))
                $bandHeights[$b] = $bandPadTop + $bandPadBottom + $rows * $iconH + ($rows - 1) * $iconRowGap
            }
            $rgInnerH = ($bandHeights.Values | Measure-Object -Sum).Sum + ($nonEmptyBands.Count - 1) * 20
            $rgH = $rgPadTop + $rgInnerH + 20
            $rgW = $rgWidthMin
            $rgLayouts.Add([pscustomobject]@{ Rg = $rg.Name; Resources = $rg.Group; Bands = $bands; BandHeights = $bandHeights; Width = $rgW; Height = $rgH })
            $subInnerH += $rgH + 40
            $subInnerW = [math]::Max($subInnerW, $rgW + $subPadX * 2)
        }
        $subH = [math]::Max($subInnerH + 80, 220)
        $subW = [math]::Max($subInnerW + 40, 940)

        # Subscription container
        $subContainerId = $null
        if ($multiSub) {
            $subContainerId = "sub_$cellId"; $cellId++
            $label = "Subscription: $(Get-Escaped $subGroup.Name)"
            [void]$cells.AppendLine(@"
<mxCell id="$subContainerId" value="$label" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FAFBFD;strokeColor=#444444;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;fontSize=13;fontStyle=1;" vertex="1" parent="1">
  <mxGeometry x="$subX" y="$subY" width="$subW" height="$subH" as="geometry" />
</mxCell>
"@)
        }

        $rgX = if ($multiSub) { $subPadX } else { 60 }
        $rgY = if ($multiSub) { $subPadTop } else { 60 }

        foreach ($layout in $rgLayouts) {
            $rgId = "rg_$cellId"; $cellId++
            $parentForRg = if ($multiSub) { $subContainerId } else { '1' }
            $rgLabel = "Resource group: $(Get-Escaped $layout.Rg)"
            [void]$cells.AppendLine(@"
<mxCell id="$rgId" value="$rgLabel" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#5C7C99;strokeWidth=1.5;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;spacingTop=4;fontSize=12;fontStyle=1;" vertex="1" parent="$parentForRg">
  <mxGeometry x="$rgX" y="$rgY" width="$($layout.Width)" height="$($layout.Height)" as="geometry" />
</mxCell>
"@)

            # Bands inside RG
            $bandY = $rgPadTop
            $nonEmptyBands = @($layout.BandHeights.Keys | Sort-Object)
            foreach ($b in $nonEmptyBands) {
                $bH = $layout.BandHeights[$b]
                $bandTitle_ = if ($b -ge 0 -and $b -lt $bandTitle.Count) { $bandTitle[$b] } else { 'Other' }
                $fill = if ($b -ge 0 -and $b -lt $bandFill.Count) { $bandFill[$b] } else { '#F4F4F4' }
                $stroke = if ($b -ge 0 -and $b -lt $bandStroke.Count) { $bandStroke[$b] } else { '#888888' }
                $bandId = "band_$cellId"; $cellId++
                [void]$cells.AppendLine(@"
<mxCell id="$bandId" value="$(Get-Escaped $bandTitle_)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=$fill;strokeColor=$stroke;strokeWidth=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=12;spacingTop=2;fontSize=11;fontStyle=2;fontColor=#475569;" vertex="1" parent="$rgId">
  <mxGeometry x="$rgPadX" y="$bandY" width="$($layout.Width - $rgPadX * 2)" height="$bH" as="geometry" />
</mxCell>
"@)
                # Resources placed in a grid inside the band.
                $i = 0
                foreach ($r in $layout.Bands[$b] | Sort-Object type, name) {
                    $col = $i % 8
                    $row = [math]::Floor($i / 8)
                    $rx = $bandPadX + $col * ($iconW + $iconColGap)
                    $ry = $bandPadTop + $row * ($iconH + $iconRowGap)
                    $id = Get-SafeId $r.id
                    $declared[$id] = $true
                    $shortType = ($r.type -split '/')[-1]
                    $label = "$(Get-Escaped $r.name)&#10;<font style='font-size:9px;color:#6a7388;'>$(Get-Escaped $shortType)</font>"
                    $style = Get-ShapeStyle $r.type
                    [void]$cells.AppendLine(@"
<mxCell id="$id" value="$label" style="$style" vertex="1" parent="$bandId">
  <mxGeometry x="$rx" y="$ry" width="$iconW" height="$iconH" as="geometry" />
</mxCell>
"@)
                    $i++
                }
                $bandY += $bH + 20
            }

            $rgY += $layout.Height + 40
        }

        $subY += $subH + 40
    }

    # ────────────────────────────────────────────────────────────────────
    # Edges. Use bezier curves and put labels on a white background so
    # they stay readable when they cross containers.
    # ────────────────────────────────────────────────────────────────────
    $edgeId = 5000
    foreach ($e in $Model.Graph.edges) {
        $from = Get-SafeId $e.from
        $to   = Get-SafeId $e.to
        if (-not $declared.ContainsKey($from) -or -not $declared.ContainsKey($to)) { continue }
        $rel = if ($e.PSObject.Properties['relation']) { $e.relation } else { 'references' }
        $relLabel = Get-Escaped $rel
        [void]$cells.AppendLine(@"
<mxCell id="e_$edgeId" value="$relLabel" style="endArrow=classic;html=1;rounded=1;curved=1;strokeColor=#7E7E7E;strokeWidth=1.2;fontSize=9;fontColor=#475569;labelBackgroundColor=#FFFFFF;labelBorderColor=#E2E8F0;exitX=0.5;exitY=1;entryX=0.5;entryY=0;" edge="1" parent="1" source="$from" target="$to">
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
    <mxGraphModel dx="1422" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1400" pageHeight="1000" math="0" shadow="0">
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
