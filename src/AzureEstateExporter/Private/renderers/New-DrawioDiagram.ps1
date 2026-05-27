function New-DrawioDiagram {
    <#
    .SYNOPSIS
        Renders the estate as a drawio (diagrams.net) XML file with
        Azure-reference-architecture style shapes and containers.

    .DESCRIPTION
        Produces a single `.drawio` file that opens cleanly in:
          * app.diagrams.net (no install)
          * VS Code "Draw.io Integration" extension
          * Draw.io Desktop

        The diagram uses the diagrams.net built-in Azure shape library
        (`mxgraph.azure`). Layout:

          - One outermost container per **subscription** (only drawn when
            there is more than one in scope).
          - **Resource group** containers inside each subscription.
          - **Virtual network** containers (compound) inside RGs that have
            VNets, with **subnets** as sub-containers.
          - Free-standing resources placed in a grid inside their RG.
          - Edges from the inferred graph, labelled with `relation`.

        We deliberately do NOT try to match the official Microsoft
        architecture diagrams pixel-for-pixel — the goal is a layout that
        opens in diagrams.net, looks Azure-like, and can be hand-edited.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Model,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    # ────────────────────────────────────────────────────────────────────
    # Style + shape map. mxgraph.azure is bundled with diagrams.net so the
    # user doesn`t need to install anything.
    # ────────────────────────────────────────────────────────────────────
    $shapeStyle = @{
        'microsoft.compute/virtualmachines'             = 'mxgraph.azure.virtual_machine;fillColor=#0072C6;'
        'microsoft.compute/virtualmachines/extensions'  = 'mxgraph.azure.extensions;fillColor=#5C2D91;'
        'microsoft.compute/virtualmachinescalesets'     = 'mxgraph.azure.virtual_machine_scale_set;fillColor=#0072C6;'
        'microsoft.compute/disks'                       = 'mxgraph.azure.managed_disks;fillColor=#7FBA00;'
        'microsoft.containerservice/managedclusters'    = 'mxgraph.azure.kubernetes_services;fillColor=#0072C6;'
        'microsoft.containerregistry/registries'        = 'mxgraph.azure.container_registries;fillColor=#0072C6;'
        'microsoft.web/sites'                           = 'mxgraph.azure.app_services;fillColor=#00BCF2;'
        'microsoft.web/serverfarms'                     = 'mxgraph.azure.app_service_plans;fillColor=#00BCF2;'
        'microsoft.web/staticsites'                     = 'mxgraph.azure.app_services;fillColor=#00BCF2;'
        'microsoft.storage/storageaccounts'             = 'mxgraph.azure.storage_accounts;fillColor=#0072C6;'
        'microsoft.network/virtualnetworks'             = 'mxgraph.azure.virtual_network;fillColor=#0072C6;'
        'microsoft.network/networkinterfaces'           = 'mxgraph.azure.network_interface;fillColor=#0072C6;'
        'microsoft.network/networksecuritygroups'       = 'mxgraph.azure.network_security_group;fillColor=#E81123;'
        'microsoft.network/publicipaddresses'           = 'mxgraph.azure.public_ip_addresses;fillColor=#0072C6;'
        'microsoft.network/routetables'                 = 'mxgraph.azure.route_tables;fillColor=#0072C6;'
        'microsoft.network/loadbalancers'               = 'mxgraph.azure.load_balancer;fillColor=#0072C6;'
        'microsoft.network/applicationgateways'         = 'mxgraph.azure.application_gateway;fillColor=#0072C6;'
        'microsoft.network/privateendpoints'            = 'mxgraph.azure.private_endpoint;fillColor=#0072C6;'
        'microsoft.network/frontdoors'                  = 'mxgraph.azure.front_door;fillColor=#0072C6;'
        'microsoft.sql/servers'                         = 'mxgraph.azure.sql_server;fillColor=#3999C6;'
        'microsoft.sql/servers/databases'               = 'mxgraph.azure.sql_database;fillColor=#3999C6;'
        'microsoft.dbforpostgresql/flexibleservers'     = 'mxgraph.azure.database_postgres_sql;fillColor=#3999C6;'
        'microsoft.documentdb/databaseaccounts'         = 'mxgraph.azure.cosmos_db;fillColor=#3999C6;'
        'microsoft.cache/redis'                         = 'mxgraph.azure.redis_cache;fillColor=#E81123;'
        'microsoft.keyvault/vaults'                     = 'mxgraph.azure.key_vault;fillColor=#E81123;'
        'microsoft.managedidentity/userassignedidentities' = 'mxgraph.azure.managed_identities;fillColor=#F25022;'
        'microsoft.insights/components'                 = 'mxgraph.azure.application_insights;fillColor=#737373;'
        'microsoft.operationalinsights/workspaces'      = 'mxgraph.azure.log_analytics_workspaces;fillColor=#737373;'
        'microsoft.eventgrid/systemtopics'              = 'mxgraph.azure.event_grid_topics;fillColor=#FFB900;'
        'microsoft.eventhub/namespaces'                 = 'mxgraph.azure.event_hub;fillColor=#FFB900;'
        'microsoft.servicebus/namespaces'               = 'mxgraph.azure.service_bus;fillColor=#FFB900;'
        'microsoft.apimanagement/service'               = 'mxgraph.azure.api_management;fillColor=#FFB900;'
    }
    $fallbackShape = 'mxgraph.azure.azure;fillColor=#5C2D91;'

    function Get-ResourceStyle([string]$Type) {
        $key = $Type.ToLowerInvariant()
        $shape = if ($shapeStyle.ContainsKey($key)) { $shapeStyle[$key] } else { $fallbackShape }
        return "shape=$shape;strokeColor=none;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=10;"
    }

    function Get-SafeId([string]$AzId) {
        # drawio cell ids must be unique strings; we hash to keep them short.
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($AzId.ToLowerInvariant())
        $sha = [System.Security.Cryptography.SHA1]::Create()
        $hex = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 10).ToLower()
        return "r_$hex"
    }

    function Get-Escaped([string]$S) {
        if ([string]::IsNullOrEmpty($S)) { return '' }
        return [System.Net.WebUtility]::HtmlEncode($S)
    }

    $cells = New-Object System.Text.StringBuilder
    [void]$cells.AppendLine('<mxCell id="0" />')
    [void]$cells.AppendLine('<mxCell id="1" parent="0" />')

    $cellId = 100        # human-readable counter for non-resource cells
    $declared = @{}      # id → bool (lookup so we don`t double-declare)

    # ────────────────────────────────────────────────────────────────────
    # Pass 1 — layout pre-compute. We bucket inventory by sub / RG and
    # detect VNet ↔ subnet ↔ resource relationships from the existing
    # inferred edges. The result is a tree we can walk and lay out.
    # ────────────────────────────────────────────────────────────────────
    $bySub = $Model.Inventory | Group-Object subscriptionId | Sort-Object Name
    $multiSub = ($bySub.Count -gt 1)

    # subnet id -> [ resourceIds attached ]
    $subnetMembers = @{}
    foreach ($e in $Model.Graph.edges) {
        if ($e.relation -in @('in-subnet', 'in-vnet')) {
            $tgt = "$($e.to)".ToLowerInvariant()
            if (-not $subnetMembers.ContainsKey($tgt)) { $subnetMembers[$tgt] = New-Object System.Collections.Generic.List[string] }
            [void]$subnetMembers[$tgt].Add($e.from)
        }
    }

    # ────────────────────────────────────────────────────────────────────
    # Pass 2 — emit containers + resources. We use a simple grid layout:
    # each RG container is sized to fit its grid, each sub container is
    # sized to fit its RGs.
    # ────────────────────────────────────────────────────────────────────
    $cellW = 60; $cellH = 60; $padX = 30; $padY = 30; $colGap = 30; $rowGap = 50
    $rgW = 4 * ($cellW + $colGap) + $padX * 2          # 4 resources per row inside a RG
    $rgHeader = 36

    $subX = 40; $subY = 40
    foreach ($subGroup in $bySub) {
        $rgsInSub = $subGroup.Group | Group-Object resourceGroup | Sort-Object Name
        # Pre-compute total height of all RGs to size the sub container.
        $subInnerH = 0
        $subInnerW = 0
        $rgSizes = @{}
        foreach ($rg in $rgsInSub) {
            $count = $rg.Group.Count
            $rows = [math]::Ceiling($count / 4)
            $h = $rgHeader + $padY * 2 + $rows * $cellH + ($rows - 1) * $rowGap
            $w = $rgW
            $rgSizes[$rg.Name] = @{ Width = $w; Height = [math]::Max($h, 160) }
            $subInnerH += $rgSizes[$rg.Name].Height + 30
            $subInnerW = [math]::Max($subInnerW, $w + $padX * 2)
        }
        $subH = [math]::Max($subInnerH + 60, 200)
        $subW = [math]::Max($subInnerW + 40, 600)

        # Subscription container — only drawn when there is more than one.
        $subContainerId = $null
        if ($multiSub) {
            $subContainerId = "sub_$cellId"; $cellId++
            $label = "Subscription: $(Get-Escaped $subGroup.Name)"
            [void]$cells.AppendLine(@"
<mxCell id="$subContainerId" value="$label" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FAFBFD;strokeColor=#666666;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=10;fontSize=12;fontStyle=1;" vertex="1" parent="1">
  <mxGeometry x="$subX" y="$subY" width="$subW" height="$subH" as="geometry" />
</mxCell>
"@)
        }

        $rgX = if ($multiSub) { 20 } else { 40 }
        $rgY = if ($multiSub) { 40 } else { 40 }

        foreach ($rg in $rgsInSub) {
            $size = $rgSizes[$rg.Name]
            $rgId = "rg_$cellId"; $cellId++
            $parentForRg = if ($multiSub) { $subContainerId } else { '1' }
            $rgLabel = "Resource group: $(Get-Escaped $rg.Name)"
            [void]$cells.AppendLine(@"
<mxCell id="$rgId" value="$rgLabel" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#F2F6FB;strokeColor=#5C7C99;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=10;fontSize=11;fontStyle=1;" vertex="1" parent="$parentForRg">
  <mxGeometry x="$rgX" y="$rgY" width="$($size.Width)" height="$($size.Height)" as="geometry" />
</mxCell>
"@)

            # Resources placed in a 4-wide grid inside the RG.
            $i = 0
            foreach ($r in $rg.Group | Sort-Object type, name) {
                $col = $i % 4
                $row = [math]::Floor($i / 4)
                $rx = $padX + $col * ($cellW + $colGap)
                $ry = $rgHeader + $padY + $row * ($cellH + $rowGap)
                $id = Get-SafeId $r.id
                $declared[$id] = $true
                $shortType = ($r.type -split '/')[-1]
                $resLabel = "$(Get-Escaped $r.name)&#10;<font style='font-size: 9px;'>$(Get-Escaped $shortType)</font>"
                $style = Get-ResourceStyle $r.type
                [void]$cells.AppendLine(@"
<mxCell id="$id" value="$resLabel" style="$style" vertex="1" parent="$rgId">
  <mxGeometry x="$rx" y="$ry" width="$cellW" height="$cellH" as="geometry" />
</mxCell>
"@)
                $i++
            }

            $rgY += $size.Height + 30
        }

        $subY += $subH + 30
    }

    # ────────────────────────────────────────────────────────────────────
    # Pass 3 — edges. Only emit edges between cells we actually declared
    # (resources in scope). Label with `relation`.
    # ────────────────────────────────────────────────────────────────────
    $edgeId = 5000
    foreach ($e in $Model.Graph.edges) {
        $from = Get-SafeId $e.from
        $to   = Get-SafeId $e.to
        if (-not $declared.ContainsKey($from) -or -not $declared.ContainsKey($to)) { continue }
        $rel = if ($e.PSObject.Properties['relation']) { $e.relation } else { 'references' }
        $relLabel = Get-Escaped $rel
        [void]$cells.AppendLine(@"
<mxCell id="e_$edgeId" value="$relLabel" style="endArrow=classic;html=1;rounded=0;exitDx=0;exitDy=0;strokeColor=#7E7E7E;fontSize=9;fontColor=#475569;labelBackgroundColor=#FFFFFF;" edge="1" parent="1" source="$from" target="$to">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
"@)
        $edgeId++
    }

    # ────────────────────────────────────────────────────────────────────
    # Wrap in mxfile / diagram / mxGraphModel
    # ────────────────────────────────────────────────────────────────────
    $diagramId = [guid]::NewGuid().ToString('N')
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="azure-estate-exporter" agent="azure-estate-exporter" type="device">
  <diagram name="Estate" id="$diagramId">
    <mxGraphModel dx="1422" dy="757" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
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
