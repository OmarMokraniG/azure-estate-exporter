import type { ArgResource } from '@/api/arm';

/**
 * Browser port of the PowerShell `New-DrawioDiagram` renderer (v0.5.1).
 *
 * Critical change vs v0.5.0: shapes embed the icon as a base64 SVG data URI
 * (`shape=image;image=data:image/svg+xml;base64,...`) instead of referencing
 * the `mxgraph.azure.*` stencil names. The mxgraph.azure family is NOT in
 * diagrams.net`s default shape library — it lives in the Microsoft "MSCAE"
 * stencil that has to be enabled manually — and using those style strings
 * resulted in blank squares when the file was opened. SVG-embed is
 * self-contained and renders the same in:
 *   * app.diagrams.net
 *   * VS Code Draw.io Integration
 *   * Draw.io Desktop
 *
 * Layout is an Azure reference-architecture style layered diagram:
 *
 *   Subscription → Resource group → bands by category:
 *      0. Internet / Edge   (Public IPs, Front Door, App Gateway, LB, APIM)
 *      1. Network           (VNet, Subnet, NIC, NSG, Route Table, Private EP)
 *      2. Compute & Web     (VM, VMSS, AKS, ACR, App Service, App Service Plan)
 *      3. Data & Security   (Disks, Storage, SQL, Cosmos, Redis, Key Vault, MI)
 *      4. Observability     (App Insights, Log Analytics, Event Grid/Hub, SB)
 *      5. Other             (anything we don`t recognise)
 */

const ICON_BY_TYPE: Record<string, string> = {
  'microsoft.compute/virtualmachines': 'vm',
  'microsoft.compute/virtualmachines/extensions': 'vm-extension',
  'microsoft.compute/virtualmachines/runcommands': 'vm-extension',
  'microsoft.compute/virtualmachinescalesets': 'vmss',
  'microsoft.compute/disks': 'disk',
  'microsoft.compute/snapshots': 'disk',
  'microsoft.containerservice/managedclusters': 'aks',
  'microsoft.containerregistry/registries': 'acr',
  'microsoft.web/sites': 'app-service',
  'microsoft.web/serverfarms': 'app-service-plan',
  'microsoft.web/staticsites': 'static-web-app',
  'microsoft.storage/storageaccounts': 'storage',
  'microsoft.network/virtualnetworks': 'vnet',
  'microsoft.network/virtualnetworks/subnets': 'subnet',
  'microsoft.network/networkinterfaces': 'nic',
  'microsoft.network/networksecuritygroups': 'nsg',
  'microsoft.network/publicipaddresses': 'public-ip',
  'microsoft.network/routetables': 'route-table',
  'microsoft.network/loadbalancers': 'lb',
  'microsoft.network/applicationgateways': 'app-gateway',
  'microsoft.network/privateendpoints': 'private-endpoint',
  'microsoft.network/frontdoors': 'front-door',
  'microsoft.sql/servers': 'sql',
  'microsoft.sql/servers/databases': 'sql',
  'microsoft.dbforpostgresql/flexibleservers': 'postgres',
  'microsoft.documentdb/databaseaccounts': 'cosmos',
  'microsoft.cache/redis': 'redis',
  'microsoft.keyvault/vaults': 'key-vault',
  'microsoft.managedidentity/userassignedidentities': 'managed-identity',
  'microsoft.insights/components': 'app-insights',
  'microsoft.operationalinsights/workspaces': 'log-analytics',
  'microsoft.eventgrid/systemtopics': 'event-grid',
  'microsoft.eventhub/namespaces': 'event-hub',
  'microsoft.servicebus/namespaces': 'service-bus',
  'microsoft.apimanagement/service': 'apim',
};

const CATEGORY_BY_TYPE: Record<string, number> = {
  // 0 = Edge
  'microsoft.network/publicipaddresses': 0,
  'microsoft.network/frontdoors': 0,
  'microsoft.network/applicationgateways': 0,
  'microsoft.network/loadbalancers': 0,
  'microsoft.apimanagement/service': 0,
  // 1 = Network
  'microsoft.network/virtualnetworks': 1,
  'microsoft.network/virtualnetworks/subnets': 1,
  'microsoft.network/networkinterfaces': 1,
  'microsoft.network/networksecuritygroups': 1,
  'microsoft.network/routetables': 1,
  'microsoft.network/privateendpoints': 1,
  // 2 = Compute & Web
  'microsoft.compute/virtualmachines': 2,
  'microsoft.compute/virtualmachines/extensions': 2,
  'microsoft.compute/virtualmachines/runcommands': 2,
  'microsoft.compute/virtualmachinescalesets': 2,
  'microsoft.containerservice/managedclusters': 2,
  'microsoft.containerregistry/registries': 2,
  'microsoft.web/sites': 2,
  'microsoft.web/serverfarms': 2,
  'microsoft.web/staticsites': 2,
  // 3 = Data & Security
  'microsoft.compute/disks': 3,
  'microsoft.compute/snapshots': 3,
  'microsoft.storage/storageaccounts': 3,
  'microsoft.sql/servers': 3,
  'microsoft.sql/servers/databases': 3,
  'microsoft.dbforpostgresql/flexibleservers': 3,
  'microsoft.documentdb/databaseaccounts': 3,
  'microsoft.cache/redis': 3,
  'microsoft.keyvault/vaults': 3,
  'microsoft.managedidentity/userassignedidentities': 3,
  // 4 = Observability & Integration
  'microsoft.insights/components': 4,
  'microsoft.operationalinsights/workspaces': 4,
  'microsoft.eventgrid/systemtopics': 4,
  'microsoft.eventhub/namespaces': 4,
  'microsoft.servicebus/namespaces': 4,
};

const BAND_TITLE = ['Internet / Edge', 'Network', 'Compute & Web', 'Data & Security', 'Observability & Integration', 'Other'];
const BAND_FILL = ['#FEF6E4', '#E7F0FB', '#E8F5E9', '#FCE8EA', '#F5F0F8', '#F4F4F4'];
const BAND_STROKE = ['#D89E2A', '#5C7C99', '#4E8C5A', '#B0455B', '#6C4E80', '#888888'];

export interface DrawioEdge {
  from: string;
  to: string;
  relation?: string;
}

export interface DrawioOptions {
  resources: ArgResource[];
  edges?: DrawioEdge[];
  /**
   * Override the icon base path (defaults to `/icons/`). Tests inject a
   * stub fetcher to avoid network round-trips.
   */
  iconBase?: string;
  /** Override the fetcher (defaults to global `fetch`). For tests. */
  fetcher?: (url: string) => Promise<string>;
}

async function sha1Hex(s: string): Promise<string> {
  if (typeof window !== 'undefined' && window.crypto?.subtle) {
    const buf = new TextEncoder().encode(s);
    const hash = await window.crypto.subtle.digest('SHA-1', buf);
    return Array.from(new Uint8Array(hash))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }
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

function b64encode(s: string): string {
  if (typeof window !== 'undefined' && typeof window.btoa === 'function') {
    // Use TextEncoder to handle Unicode correctly (SVGs contain UTF-8).
    const bytes = new TextEncoder().encode(s);
    let bin = '';
    for (const b of bytes) bin += String.fromCharCode(b);
    return window.btoa(bin);
  }
  // Node-side fallback (used by vitest).
  return Buffer.from(s, 'utf8').toString('base64');
}

async function defaultFetcher(url: string): Promise<string> {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`Failed to fetch ${url}: ${r.status}`);
  return r.text();
}

async function loadIconAsDataUri(
  iconName: string,
  cache: Map<string, string>,
  iconBase: string,
  fetcher: (url: string) => Promise<string>,
): Promise<string> {
  if (cache.has(iconName)) return cache.get(iconName)!;
  let svg = '';
  try {
    svg = await fetcher(`${iconBase}${iconName}.svg`);
  } catch {
    // Fall back to _default.svg
    if (iconName !== '_default') {
      try { svg = await fetcher(`${iconBase}_default.svg`); } catch { svg = ''; }
    }
  }
  const uri = svg ? `data:image/svg+xml;base64,${b64encode(svg)}` : '';
  cache.set(iconName, uri);
  return uri;
}

function shapeStyle(dataUri: string): string {
  if (!dataUri) {
    return 'rounded=1;whiteSpace=wrap;html=1;fillColor=#0072C6;strokeColor=#005A9E;fontColor=#FFFFFF;fontSize=10;';
  }
  return `shape=image;html=1;image=${dataUri};labelBackgroundColor=#FFFFFF;labelPosition=center;verticalLabelPosition=bottom;align=center;verticalAlign=top;imageAspect=0;fontSize=10;`;
}

export async function generateDrawioXml(opts: DrawioOptions): Promise<string> {
  const { resources, edges = [] } = opts;
  const iconBase = opts.iconBase ?? '/icons/';
  const fetcher = opts.fetcher ?? defaultFetcher;
  const iconCache = new Map<string, string>();

  // Pre-load every icon we`ll need so the generator stays a single async pass.
  const neededIcons = new Set<string>();
  for (const r of resources) {
    neededIcons.add(ICON_BY_TYPE[r.type.toLowerCase()] ?? '_default');
  }
  await Promise.all([...neededIcons].map((name) => loadIconAsDataUri(name, iconCache, iconBase, fetcher)));

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

  const iconW = 80,
    iconH = 80,
    iconColGap = 50,
    iconRowGap = 70,
    bandPadTop = 38,
    bandPadBottom = 16,
    bandPadX = 24,
    rgPadX = 28,
    rgPadTop = 50,
    rgWidth = 880,
    subPadX = 30,
    subPadTop = 50;

  let cellCounter = 100;
  const declared = new Set<string>();
  const idMap = new Map<string, string>();

  const subX = 60;
  let subY = 60;

  for (const [subId, rgs] of bySub) {
    // Pre-compute layout
    const rgLayouts: Array<{ name: string; bands: Map<number, ArgResource[]>; height: number }> = [];
    let subInnerH = 0;
    for (const [rgName, rgRes] of rgs) {
      const bands = new Map<number, ArgResource[]>();
      for (const r of rgRes) {
        const cat = CATEGORY_BY_TYPE[r.type.toLowerCase()] ?? 5;
        const arr = bands.get(cat) ?? [];
        arr.push(r);
        bands.set(cat, arr);
      }
      const sortedBands = [...bands.keys()].sort((a, b) => a - b);
      const iconsPerRow = 8;
      let innerH = 0;
      for (const b of sortedBands) {
        const rows = Math.max(1, Math.ceil(bands.get(b)!.length / iconsPerRow));
        innerH += bandPadTop + bandPadBottom + rows * iconH + (rows - 1) * iconRowGap;
      }
      innerH += (sortedBands.length - 1) * 20;
      const rgH = rgPadTop + innerH + 20;
      rgLayouts.push({ name: rgName, bands, height: rgH });
      subInnerH += rgH + 40;
    }
    const subH = Math.max(subInnerH + 80, 220);
    const subW = Math.max(rgWidth + subPadX * 2 + 40, 940);

    let subContainerId: string | null = null;
    if (multiSub) {
      subContainerId = `sub_${cellCounter++}`;
      cells.push(
        `<mxCell id="${subContainerId}" value="${xmlEscape(
          `Subscription: ${subId}`,
        )}" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FAFBFD;strokeColor=#444444;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;fontSize=13;fontStyle=1;" vertex="1" parent="1">
  <mxGeometry x="${subX}" y="${subY}" width="${subW}" height="${subH}" as="geometry" />
</mxCell>`,
      );
    }

    const rgX = multiSub ? subPadX : 60;
    let rgY = multiSub ? subPadTop : 60;

    for (const layout of rgLayouts) {
      const rgId = `rg_${cellCounter++}`;
      const parentForRg = multiSub ? subContainerId! : '1';
      cells.push(
        `<mxCell id="${rgId}" value="${xmlEscape(
          `Resource group: ${layout.name}`,
        )}" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#5C7C99;strokeWidth=1.5;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;spacingTop=4;fontSize=12;fontStyle=1;" vertex="1" parent="${parentForRg}">
  <mxGeometry x="${rgX}" y="${rgY}" width="${rgWidth}" height="${layout.height}" as="geometry" />
</mxCell>`,
      );

      let bandY = rgPadTop;
      const sortedBands = [...layout.bands.keys()].sort((a, b) => a - b);
      for (const b of sortedBands) {
        const rsInBand = layout.bands.get(b)!;
        const rows = Math.max(1, Math.ceil(rsInBand.length / 8));
        const bH = bandPadTop + bandPadBottom + rows * iconH + (rows - 1) * iconRowGap;
        const bandId = `band_${cellCounter++}`;
        const title = BAND_TITLE[b] ?? 'Other';
        const fill = BAND_FILL[b] ?? '#F4F4F4';
        const stroke = BAND_STROKE[b] ?? '#888888';
        cells.push(
          `<mxCell id="${bandId}" value="${xmlEscape(
            title,
          )}" style="rounded=1;whiteSpace=wrap;html=1;fillColor=${fill};strokeColor=${stroke};strokeWidth=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=12;spacingTop=2;fontSize=11;fontStyle=2;fontColor=#475569;" vertex="1" parent="${rgId}">
  <mxGeometry x="${rgPadX}" y="${bandY}" width="${rgWidth - rgPadX * 2}" height="${bH}" as="geometry" />
</mxCell>`,
        );

        const sorted = [...rsInBand].sort(
          (a, c) => a.type.localeCompare(c.type) || a.name.localeCompare(c.name),
        );
        let i = 0;
        for (const r of sorted) {
          const col = i % 8;
          const row = Math.floor(i / 8);
          const rx = bandPadX + col * (iconW + iconColGap);
          const ry = bandPadTop + row * (iconH + iconRowGap);
          const id = await safeId(r.id);
          declared.add(id);
          idMap.set(r.id.toLowerCase(), id);
          const shortType = r.type.split('/').pop() ?? r.type;
          const value = `${xmlEscape(r.name)}&#10;<font style='font-size:9px;color:#6a7388;'>${xmlEscape(shortType)}</font>`;
          const iconName = ICON_BY_TYPE[r.type.toLowerCase()] ?? '_default';
          const dataUri = iconCache.get(iconName) ?? '';
          cells.push(
            `<mxCell id="${id}" value="${value}" style="${shapeStyle(dataUri)}" vertex="1" parent="${bandId}">
  <mxGeometry x="${rx}" y="${ry}" width="${iconW}" height="${iconH}" as="geometry" />
</mxCell>`,
          );
          i++;
        }
        bandY += bH + 20;
      }

      rgY += layout.height + 40;
    }

    subY += subH + 40;
  }

  // Edges
  let edgeCounter = 5000;
  for (const e of edges) {
    const from = idMap.get(e.from.toLowerCase());
    const to = idMap.get(e.to.toLowerCase());
    if (!from || !to || !declared.has(from) || !declared.has(to)) continue;
    const relLabel = xmlEscape(e.relation ?? 'references');
    cells.push(
      `<mxCell id="e_${edgeCounter++}" value="${relLabel}" style="endArrow=classic;html=1;rounded=1;curved=1;strokeColor=#7E7E7E;strokeWidth=1.2;fontSize=9;fontColor=#475569;labelBackgroundColor=#FFFFFF;labelBorderColor=#E2E8F0;exitX=0.5;exitY=1;entryX=0.5;entryY=0;" edge="1" parent="1" source="${from}" target="${to}">
  <mxGeometry relative="1" as="geometry" />
</mxCell>`,
    );
  }

  const diagId = Math.random().toString(16).slice(2, 18);
  return `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="azure-estate-exporter" agent="azure-estate-exporter-web" type="device">
  <diagram name="Estate" id="${diagId}">
    <mxGraphModel dx="1422" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1400" pageHeight="1000" math="0" shadow="0">
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

export function openInDiagramsNetUrl(filename: string): string {
  return `https://app.diagrams.net/?title=${encodeURIComponent(filename)}`;
}
