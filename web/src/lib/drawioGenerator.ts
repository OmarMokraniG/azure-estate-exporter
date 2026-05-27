import type { ArgResource } from '@/api/arm';

/**
 * Browser port of the PowerShell `New-DrawioDiagram` renderer. Produces a
 * drawio XML string that opens cleanly in app.diagrams.net (and VS Code`s
 * Draw.io Integration extension).
 *
 * Container hierarchy:
 *   subscription (only if multiple in scope)
 *     resource-group
 *       resource (mxgraph.azure shape)
 *
 * Edges come from the same `inferEdges()` heuristic used by the React Flow
 * diagram, so the drawio export stays consistent with what users see in the
 * Diagram tab.
 */

const SHAPE: Record<string, string> = {
  'microsoft.compute/virtualmachines': 'mxgraph.azure.virtual_machine;fillColor=#0072C6;',
  'microsoft.compute/virtualmachines/extensions': 'mxgraph.azure.extensions;fillColor=#5C2D91;',
  'microsoft.compute/virtualmachinescalesets': 'mxgraph.azure.virtual_machine_scale_set;fillColor=#0072C6;',
  'microsoft.compute/disks': 'mxgraph.azure.managed_disks;fillColor=#7FBA00;',
  'microsoft.containerservice/managedclusters': 'mxgraph.azure.kubernetes_services;fillColor=#0072C6;',
  'microsoft.containerregistry/registries': 'mxgraph.azure.container_registries;fillColor=#0072C6;',
  'microsoft.web/sites': 'mxgraph.azure.app_services;fillColor=#00BCF2;',
  'microsoft.web/serverfarms': 'mxgraph.azure.app_service_plans;fillColor=#00BCF2;',
  'microsoft.web/staticsites': 'mxgraph.azure.app_services;fillColor=#00BCF2;',
  'microsoft.storage/storageaccounts': 'mxgraph.azure.storage_accounts;fillColor=#0072C6;',
  'microsoft.network/virtualnetworks': 'mxgraph.azure.virtual_network;fillColor=#0072C6;',
  'microsoft.network/networkinterfaces': 'mxgraph.azure.network_interface;fillColor=#0072C6;',
  'microsoft.network/networksecuritygroups': 'mxgraph.azure.network_security_group;fillColor=#E81123;',
  'microsoft.network/publicipaddresses': 'mxgraph.azure.public_ip_addresses;fillColor=#0072C6;',
  'microsoft.network/routetables': 'mxgraph.azure.route_tables;fillColor=#0072C6;',
  'microsoft.network/loadbalancers': 'mxgraph.azure.load_balancer;fillColor=#0072C6;',
  'microsoft.network/applicationgateways': 'mxgraph.azure.application_gateway;fillColor=#0072C6;',
  'microsoft.network/privateendpoints': 'mxgraph.azure.private_endpoint;fillColor=#0072C6;',
  'microsoft.network/frontdoors': 'mxgraph.azure.front_door;fillColor=#0072C6;',
  'microsoft.sql/servers': 'mxgraph.azure.sql_server;fillColor=#3999C6;',
  'microsoft.sql/servers/databases': 'mxgraph.azure.sql_database;fillColor=#3999C6;',
  'microsoft.dbforpostgresql/flexibleservers': 'mxgraph.azure.database_postgres_sql;fillColor=#3999C6;',
  'microsoft.documentdb/databaseaccounts': 'mxgraph.azure.cosmos_db;fillColor=#3999C6;',
  'microsoft.cache/redis': 'mxgraph.azure.redis_cache;fillColor=#E81123;',
  'microsoft.keyvault/vaults': 'mxgraph.azure.key_vault;fillColor=#E81123;',
  'microsoft.managedidentity/userassignedidentities': 'mxgraph.azure.managed_identities;fillColor=#F25022;',
  'microsoft.insights/components': 'mxgraph.azure.application_insights;fillColor=#737373;',
  'microsoft.operationalinsights/workspaces': 'mxgraph.azure.log_analytics_workspaces;fillColor=#737373;',
  'microsoft.eventgrid/systemtopics': 'mxgraph.azure.event_grid_topics;fillColor=#FFB900;',
  'microsoft.eventhub/namespaces': 'mxgraph.azure.event_hub;fillColor=#FFB900;',
  'microsoft.servicebus/namespaces': 'mxgraph.azure.service_bus;fillColor=#FFB900;',
  'microsoft.apimanagement/service': 'mxgraph.azure.api_management;fillColor=#FFB900;',
};
const FALLBACK = 'mxgraph.azure.azure;fillColor=#5C2D91;';

export interface DrawioEdge {
  from: string;
  to: string;
  relation?: string;
}

export interface DrawioOptions {
  resources: ArgResource[];
  edges?: DrawioEdge[];
}

function shapeStyle(armType: string): string {
  const shape = SHAPE[armType.toLowerCase()] ?? FALLBACK;
  return `shape=${shape}strokeColor=none;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=10;`;
}

async function sha1Hex(s: string): Promise<string> {
  if (typeof window !== 'undefined' && window.crypto?.subtle) {
    const buf = new TextEncoder().encode(s);
    const hash = await window.crypto.subtle.digest('SHA-1', buf);
    return Array.from(new Uint8Array(hash))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }
  // Fallback: simple FNV-1a 32-bit hash, hex-encoded. Good enough for cell ids.
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

async function safeId(azId: string): Promise<string> {
  const hex = (await sha1Hex(azId.toLowerCase())).slice(0, 10);
  return `r_${hex}`;
}

function xmlEscape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export async function generateDrawioXml(opts: DrawioOptions): Promise<string> {
  const { resources } = opts;
  const edges = opts.edges ?? [];

  // Group by sub > rg
  const bySub = new Map<string, Map<string, ArgResource[]>>();
  for (const r of resources) {
    let sub = bySub.get(r.subscriptionId);
    if (!sub) {
      sub = new Map();
      bySub.set(r.subscriptionId, sub);
    }
    const rg = sub.get(r.resourceGroup) ?? [];
    rg.push(r);
    sub.set(r.resourceGroup, rg);
  }

  const multiSub = bySub.size > 1;
  const cells: string[] = [];
  cells.push('<mxCell id="0" />');
  cells.push('<mxCell id="1" parent="0" />');

  const cellW = 60,
    cellH = 60,
    padX = 30,
    padY = 30,
    colGap = 30,
    rowGap = 50,
    rgHeader = 36;
  const rgW = 4 * (cellW + colGap) + padX * 2;

  let cellCounter = 100;
  const declared = new Set<string>();
  const idMap = new Map<string, string>(); // ARM id (lower) -> cell id

  const subX = 40;
  let subY = 40;

  for (const [subId, rgs] of bySub) {
    const rgSizes = new Map<string, { w: number; h: number }>();
    let subInnerH = 0,
      subInnerW = 0;
    for (const [rgName, rgRes] of rgs) {
      const rows = Math.ceil(rgRes.length / 4);
      const h = Math.max(rgHeader + padY * 2 + rows * cellH + (rows - 1) * rowGap, 160);
      rgSizes.set(rgName, { w: rgW, h });
      subInnerH += h + 30;
      subInnerW = Math.max(subInnerW, rgW + padX * 2);
    }
    const subH = Math.max(subInnerH + 60, 200);
    const subW = Math.max(subInnerW + 40, 600);

    let subContainerId: string | null = null;
    if (multiSub) {
      subContainerId = `sub_${cellCounter++}`;
      cells.push(
        `<mxCell id="${subContainerId}" value="${xmlEscape(
          `Subscription: ${subId}`,
        )}" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FAFBFD;strokeColor=#666666;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=10;fontSize=12;fontStyle=1;" vertex="1" parent="1">
  <mxGeometry x="${subX}" y="${subY}" width="${subW}" height="${subH}" as="geometry" />
</mxCell>`,
      );
    }

    const rgX = multiSub ? 20 : 40;
    let rgY = multiSub ? 40 : 40;

    for (const [rgName, rgRes] of rgs) {
      const size = rgSizes.get(rgName)!;
      const rgId = `rg_${cellCounter++}`;
      const parentForRg = multiSub ? subContainerId! : '1';
      cells.push(
        `<mxCell id="${rgId}" value="${xmlEscape(
          `Resource group: ${rgName}`,
        )}" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#F2F6FB;strokeColor=#5C7C99;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=10;fontSize=11;fontStyle=1;" vertex="1" parent="${parentForRg}">
  <mxGeometry x="${rgX}" y="${rgY}" width="${size.w}" height="${size.h}" as="geometry" />
</mxCell>`,
      );

      let i = 0;
      const sorted = [...rgRes].sort(
        (a, b) => a.type.localeCompare(b.type) || a.name.localeCompare(b.name),
      );
      for (const r of sorted) {
        const col = i % 4;
        const row = Math.floor(i / 4);
        const rx = padX + col * (cellW + colGap);
        const ry = rgHeader + padY + row * (cellH + rowGap);
        const id = await safeId(r.id);
        declared.add(id);
        idMap.set(r.id.toLowerCase(), id);
        const shortType = r.type.split('/').pop() ?? r.type;
        const value = `${xmlEscape(r.name)}&#10;<font style='font-size: 9px;'>${xmlEscape(shortType)}</font>`;
        cells.push(
          `<mxCell id="${id}" value="${value}" style="${shapeStyle(r.type)}" vertex="1" parent="${rgId}">
  <mxGeometry x="${rx}" y="${ry}" width="${cellW}" height="${cellH}" as="geometry" />
</mxCell>`,
        );
        i++;
      }

      rgY += size.h + 30;
    }
    subY += subH + 30;
  }

  // Edges
  let edgeCounter = 5000;
  for (const e of edges) {
    const from = idMap.get(e.from.toLowerCase());
    const to = idMap.get(e.to.toLowerCase());
    if (!from || !to || !declared.has(from) || !declared.has(to)) continue;
    const relLabel = xmlEscape(e.relation ?? 'references');
    cells.push(
      `<mxCell id="e_${edgeCounter++}" value="${relLabel}" style="endArrow=classic;html=1;rounded=0;strokeColor=#7E7E7E;fontSize=9;fontColor=#475569;labelBackgroundColor=#FFFFFF;" edge="1" parent="1" source="${from}" target="${to}">
  <mxGeometry relative="1" as="geometry" />
</mxCell>`,
    );
  }

  const diagId = Math.random().toString(16).slice(2, 18);
  return `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="azure-estate-exporter" agent="azure-estate-exporter-web" type="device">
  <diagram name="Estate" id="${diagId}">
    <mxGraphModel dx="1422" dy="757" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
${cells.join('\n')}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>`;
}

/** Trigger a browser download of a `.drawio` file with the given content. */
export function downloadDrawio(xml: string, filename = 'estate.drawio'): void {
  const blob = new Blob([xml], { type: 'application/xml' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5_000);
}

/**
 * Open the current diagram in app.diagrams.net via the `?title=...&url=...`
 * trick — we can`t pass the XML directly without uploading it, so we offer
 * both: a Download button that writes `.drawio`, and an Open-in-diagrams.net
 * link that opens a blank canvas with helpful pre-filled title.
 */
export function openInDiagramsNetUrl(filename: string): string {
  return `https://app.diagrams.net/?title=${encodeURIComponent(filename)}`;
}
