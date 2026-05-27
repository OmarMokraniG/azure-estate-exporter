import type { ArgResource } from '@/api/arm';

/**
 * Browser port of the PowerShell `New-DrawioDiagram` renderer (v0.6.1).
 *
 * v0.6.1 rewrite: Microsoft Azure architecture reference style — resources
 * are grouped by **network topology** (Subscription → RG → VNet → Subnet)
 * with three additional bands for resources that don`t live inside a
 * subnet:
 *
 *   ┌─ Resource group ─────────────────────────────────────────────┐
 *   │  ┌─ Internet / Edge ────────────────────────────────────┐    │
 *   │  │  [PIP]  [App Gateway]  [Front Door]  [LB]            │    │
 *   │  ├─ Virtual network ────────────────────────────────────┤    │
 *   │  │  ┌─ Subnet snet-foo ─────────┐                       │    │
 *   │  │  │  [NIC]  [VM]  [PE]        │                       │    │
 *   │  │  └───────────────────────────┘                       │    │
 *   │  │  ┌─ Subnet snet-bar ─────────┐                       │    │
 *   │  │  │  [Bastion]                │                       │    │
 *   │  │  └───────────────────────────┘                       │    │
 *   │  ├─ Platform services ──────────────────────────────────┤    │
 *   │  │  [Storage]  [Key Vault]  [SQL]                       │    │
 *   │  ├─ Observability ──────────────────────────────────────┤    │
 *   │  │  [App Insights]  [Log Analytics]                     │    │
 *   │  └──────────────────────────────────────────────────────┘    │
 *   └──────────────────────────────────────────────────────────────┘
 *
 * Subnets normally come embedded in the VNet`s `properties.subnets[]`
 * (ARG doesn`t flatten them into separate rows by default), so we
 * synthesise them from the parent VNet before laying out.
 *
 * Resource→subnet placement uses a brute-force properties scan because
 * NIC / Private Endpoint / etc. always store the parent subnet id under
 * some property; the exact path varies. The scan walks the JSON looking
 * for the subnet id substring — cheap on the dataset sizes we care about.
 *
 * Icons stay base64 SVG data URIs (v0.5.1 fix) so the file renders the
 * same in app.diagrams.net, VS Code Draw.io Integration and Draw.io
 * Desktop without setup.
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

type BandName = 'edge' | 'platform' | 'observability' | 'other';

const BAND_BY_TYPE: Record<string, BandName> = {
  'microsoft.network/publicipaddresses': 'edge',
  'microsoft.network/frontdoors': 'edge',
  'microsoft.network/applicationgateways': 'edge',
  'microsoft.network/loadbalancers': 'edge',
  'microsoft.apimanagement/service': 'edge',
  'microsoft.storage/storageaccounts': 'platform',
  'microsoft.sql/servers': 'platform',
  'microsoft.sql/servers/databases': 'platform',
  'microsoft.dbforpostgresql/flexibleservers': 'platform',
  'microsoft.documentdb/databaseaccounts': 'platform',
  'microsoft.cache/redis': 'platform',
  'microsoft.keyvault/vaults': 'platform',
  'microsoft.managedidentity/userassignedidentities': 'platform',
  'microsoft.containerregistry/registries': 'platform',
  'microsoft.web/sites': 'platform',
  'microsoft.web/serverfarms': 'platform',
  'microsoft.web/staticsites': 'platform',
  'microsoft.containerservice/managedclusters': 'platform',
  'microsoft.compute/disks': 'platform',
  'microsoft.compute/snapshots': 'platform',
  'microsoft.compute/virtualmachines': 'platform',
  'microsoft.compute/virtualmachinescalesets': 'platform',
  'microsoft.insights/components': 'observability',
  'microsoft.operationalinsights/workspaces': 'observability',
  'microsoft.eventgrid/systemtopics': 'observability',
  'microsoft.eventhub/namespaces': 'observability',
  'microsoft.servicebus/namespaces': 'observability',
};

const BAND_SPEC: Record<BandName, { title: string; fill: string; stroke: string }> = {
  edge:          { title: 'Internet / Edge',   fill: '#F0F9FF', stroke: '#0EA5E9' },
  platform:      { title: 'Platform services', fill: '#FAFAF9', stroke: '#737373' },
  observability: { title: 'Observability',     fill: '#F5F0F8', stroke: '#6C4E80' },
  other:         { title: 'Other',             fill: '#FAFAFA', stroke: '#A1A1AA' },
};

export interface DrawioEdge {
  from: string;
  to: string;
  relation?: string;
}

export interface DrawioOptions {
  resources: ArgResource[];
  edges?: DrawioEdge[];
  iconBase?: string;
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
    const bytes = new TextEncoder().encode(s);
    let bin = '';
    for (const b of bytes) bin += String.fromCharCode(b);
    return window.btoa(bin);
  }
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
    return 'rounded=1;whiteSpace=wrap;html=1;fillColor=#0078D4;strokeColor=#0067BB;fontColor=#FFFFFF;fontSize=10;';
  }
  return `shape=image;html=1;image=${dataUri};labelBackgroundColor=#FFFFFF;labelPosition=center;verticalLabelPosition=bottom;align=center;verticalAlign=top;imageAspect=0;fontSize=10;`;
}

interface SubnetLayout {
  subnet: ArgResource;
  resources: ArgResource[];
  width: number;
  height: number;
}
interface VNetLayout {
  vnet: ArgResource;
  subnets: SubnetLayout[];
  width: number;
  height: number;
}
interface BandLayout {
  name: BandName;
  resources: ArgResource[];
  width: number;
  height: number;
}
interface RgLayout {
  rg: string;
  width: number;
  height: number;
  vnets: VNetLayout[];
  bands: BandLayout[];
}

// Layout constants (kept in sync with the PS renderer)
const ICON_W = 80;
const ICON_H = 80;
const ICON_COL_GAP = 50;
const ICON_ROW_GAP = 70;
const SUBNET_PAD_TOP = 30;
const SUBNET_PAD_X = 18;
const VNET_PAD_TOP = 38;
const VNET_PAD_X = 22;
const RG_PAD_TOP = 50;
const RG_PAD_X = 24;
const RG_WIDTH = 1100;
const SUB_PAD_TOP = 50;
const SUB_PAD_X = 30;

export async function generateDrawioXml(opts: DrawioOptions): Promise<string> {
  const { resources, edges = [] } = opts;
  const iconBase = opts.iconBase ?? '/icons/';
  const fetcher = opts.fetcher ?? defaultFetcher;
  const iconCache = new Map<string, string>();

  // Pre-load icons so the generator stays a single async pass.
  const neededIcons = new Set<string>(['_default']);
  for (const r of resources) {
    neededIcons.add(ICON_BY_TYPE[r.type.toLowerCase()] ?? '_default');
  }
  await Promise.all(
    [...neededIcons].map((name) => loadIconAsDataUri(name, iconCache, iconBase, fetcher)),
  );

  // ── Topology discovery from edges (in-subnet + VM→NIC) ────────────────
  const subnetMembers = new Map<string, Set<string>>(); // subnetId(lc) -> {resId}
  const nicToSubnet = new Map<string, string>();
  for (const e of edges) {
    if ((e.relation ?? '').toLowerCase() === 'in-subnet') {
      const to = e.to.toLowerCase();
      const from = e.from.toLowerCase();
      if (!subnetMembers.has(to)) subnetMembers.set(to, new Set());
      subnetMembers.get(to)!.add(from);
      const src = resources.find((r) => r.id.toLowerCase() === from);
      if (src && src.type.toLowerCase() === 'microsoft.network/networkinterfaces') {
        nicToSubnet.set(from, to);
      }
    }
  }
  const vmToNic = new Map<string, string>();
  for (const r of resources) {
    if (r.type.toLowerCase() !== 'microsoft.compute/virtualmachines') continue;
    const p = (r.properties ?? {}) as Record<string, unknown>;
    const np = (p.networkProfile as Record<string, unknown> | undefined) ?? {};
    const nics = Array.isArray(np.networkInterfaces) ? (np.networkInterfaces as Array<{ id?: string }>) : [];
    if (nics[0]?.id) vmToNic.set(r.id.toLowerCase(), nics[0].id.toLowerCase());
  }

  // ── Group by sub → RG ────────────────────────────────────────────────
  const bySub = new Map<string, Map<string, ArgResource[]>>();
  for (const r of resources) {
    let sub = bySub.get(r.subscriptionId);
    if (!sub) { sub = new Map(); bySub.set(r.subscriptionId, sub); }
    const rg = sub.get(r.resourceGroup) ?? [];
    rg.push(r);
    sub.set(r.resourceGroup, rg);
  }
  const multiSub = bySub.size > 1;

  const cells: string[] = [];
  cells.push('<mxCell id="0" />');
  cells.push('<mxCell id="1" parent="0" />');
  let cellCounter = 100;
  const declared = new Set<string>();
  const idMap = new Map<string, string>(); // arm-id (lc) -> cell id

  const subX = 60;
  let subY = 60;

  for (const [subId, rgs] of bySub) {
    // Pre-compute each RG`s layout to size the sub container.
    const rgLayouts: RgLayout[] = [];
    let subInnerH = 0;
    for (const [rgName, rgInv] of rgs) {
      rgLayouts.push(computeRgLayout(rgInv, rgName, subnetMembers, nicToSubnet, vmToNic));
    }
    for (const rl of rgLayouts) subInnerH += rl.height + 40;
    const subH = Math.max(subInnerH + 80, 240);
    const subW = RG_WIDTH + SUB_PAD_X * 2 + 40;

    let subContainerId: string | null = null;
    if (multiSub) {
      subContainerId = `sub_${cellCounter++}`;
      cells.push(
        `<mxCell id="${subContainerId}" value="${xmlEscape(`Subscription: ${subId}`)}" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FAFBFD;strokeColor=#444444;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;fontSize=13;fontStyle=1;" vertex="1" parent="1">
  <mxGeometry x="${subX}" y="${subY}" width="${subW}" height="${subH}" as="geometry" />
</mxCell>`,
      );
    }

    const rgX = multiSub ? SUB_PAD_X : 60;
    let rgY = multiSub ? SUB_PAD_TOP : 60;

    for (const layout of rgLayouts) {
      const rgId = `rg_${cellCounter++}`;
      const parentForRg = multiSub ? subContainerId! : '1';
      cells.push(
        `<mxCell id="${rgId}" value="${xmlEscape(`Resource group: ${layout.rg}`)}" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#5C7C99;strokeWidth=1.5;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;spacingTop=4;fontSize=12;fontStyle=1;" vertex="1" parent="${parentForRg}">
  <mxGeometry x="${rgX}" y="${rgY}" width="${layout.width}" height="${layout.height}" as="geometry" />
</mxCell>`,
      );

      let sectionY = RG_PAD_TOP;

      // 1. Edge band on top
      const edgeBand = layout.bands.find((b) => b.name === 'edge');
      if (edgeBand) {
        await emitBand(edgeBand, rgId, RG_PAD_X, sectionY, layout.width - RG_PAD_X * 2, cells, () => cellCounter++, declared, idMap, iconCache);
        sectionY += edgeBand.height + 24;
      }

      // 2. VNets → subnets → resources
      for (const v of layout.vnets) {
        const vnetCellId = `vnet_${cellCounter++}`;
        cells.push(
          `<mxCell id="${vnetCellId}" value="${xmlEscape(`Virtual network: ${v.vnet.name}`)}" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#F0FAFF;strokeColor=#0078D4;strokeWidth=1.5;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=14;spacingTop=6;fontSize=11;fontStyle=2;fontColor=#0078D4;" vertex="1" parent="${rgId}">
  <mxGeometry x="${RG_PAD_X}" y="${sectionY}" width="${v.width}" height="${v.height}" as="geometry" />
</mxCell>`,
        );
        const vid = await safeId(v.vnet.id);
        declared.add(vid);
        idMap.set(v.vnet.id.toLowerCase(), vid);

        let subnetY = VNET_PAD_TOP;
        for (const sn of v.subnets) {
          const snCellId = `snet_${cellCounter++}`;
          const leaf = sn.subnet.name.split('/').pop() ?? sn.subnet.name;
          cells.push(
            `<mxCell id="${snCellId}" value="${xmlEscape(`Subnet: ${leaf}`)}" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#7FB1E6;strokeWidth=1;dashed=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=12;spacingTop=4;fontSize=10;fontStyle=2;fontColor=#3A6FB0;" vertex="1" parent="${vnetCellId}">
  <mxGeometry x="${VNET_PAD_X}" y="${subnetY}" width="${sn.width}" height="${sn.height}" as="geometry" />
</mxCell>`,
          );
          const snid = await safeId(sn.subnet.id);
          declared.add(snid);
          idMap.set(sn.subnet.id.toLowerCase(), snid);

          const sortedRes = [...sn.resources].sort(
            (a, b) => a.type.localeCompare(b.type) || a.name.localeCompare(b.name),
          );
          let i = 0;
          for (const r of sortedRes) {
            const col = i % 6;
            const row = Math.floor(i / 6);
            const rx = SUBNET_PAD_X + col * (ICON_W + ICON_COL_GAP);
            const ry = SUBNET_PAD_TOP + row * (ICON_H + ICON_ROW_GAP);
            const id = await safeId(r.id);
            declared.add(id);
            idMap.set(r.id.toLowerCase(), id);
            const shortType = r.type.split('/').pop() ?? r.type;
            const isPE = r.type.toLowerCase() === 'microsoft.network/privateendpoints';
            const prefix = isPE ? '🔒 ' : '';
            const label = `${xmlEscape(prefix + r.name)}&#10;<font style='font-size:9px;color:#6a7388;'>${xmlEscape(shortType)}</font>`;
            const iconName = ICON_BY_TYPE[r.type.toLowerCase()] ?? '_default';
            const dataUri = iconCache.get(iconName) ?? '';
            cells.push(
              `<mxCell id="${id}" value="${label}" style="${shapeStyle(dataUri)}" vertex="1" parent="${snCellId}">
  <mxGeometry x="${rx}" y="${ry}" width="${ICON_W}" height="${ICON_H}" as="geometry" />
</mxCell>`,
            );
            i++;
          }
          subnetY += sn.height + 16;
        }
        sectionY += v.height + 24;
      }

      // 3. Platform services
      const platBand = layout.bands.find((b) => b.name === 'platform');
      if (platBand) {
        await emitBand(platBand, rgId, RG_PAD_X, sectionY, layout.width - RG_PAD_X * 2, cells, () => cellCounter++, declared, idMap, iconCache);
        sectionY += platBand.height + 24;
      }
      // 4. Observability
      const obsBand = layout.bands.find((b) => b.name === 'observability');
      if (obsBand) {
        await emitBand(obsBand, rgId, RG_PAD_X, sectionY, layout.width - RG_PAD_X * 2, cells, () => cellCounter++, declared, idMap, iconCache);
        sectionY += obsBand.height + 24;
      }
      // 5. Other
      const otherBand = layout.bands.find((b) => b.name === 'other');
      if (otherBand) {
        await emitBand(otherBand, rgId, RG_PAD_X, sectionY, layout.width - RG_PAD_X * 2, cells, () => cellCounter++, declared, idMap, iconCache);
      }

      rgY += layout.height + 40;
    }
    subY += subH + 40;
  }

  // Edges (skip in-subnet/in-vnet because the nesting conveys them visually)
  let edgeCounter = 5000;
  for (const e of edges) {
    const rel = (e.relation ?? '').toLowerCase();
    if (rel === 'in-subnet' || rel === 'in-vnet') continue;
    const from = idMap.get(e.from.toLowerCase());
    const to = idMap.get(e.to.toLowerCase());
    if (!from || !to || !declared.has(from) || !declared.has(to)) continue;
    cells.push(
      `<mxCell id="e_${edgeCounter++}" value="${xmlEscape(e.relation ?? 'references')}" style="endArrow=classic;html=1;rounded=1;curved=1;strokeColor=#7E7E7E;strokeWidth=1.2;fontSize=9;fontColor=#475569;labelBackgroundColor=#FFFFFF;labelBorderColor=#E2E8F0;" edge="1" parent="1" source="${from}" target="${to}">
  <mxGeometry relative="1" as="geometry" />
</mxCell>`,
    );
  }

  const diagId = Math.random().toString(16).slice(2, 18);
  return `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="azure-estate-exporter" agent="azure-estate-exporter-web" type="device">
  <diagram name="Estate" id="${diagId}">
    <mxGraphModel dx="1800" dy="1100" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1700" pageHeight="1200" math="0" shadow="0">
      <root>
${cells.join('\n')}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>`;
}

// ────────────────────────────────────────────────────────────────────────
// Per-RG layout computation
// ────────────────────────────────────────────────────────────────────────

function computeRgLayout(
  rgInv: ArgResource[],
  rgName: string,
  subnetMembers: Map<string, Set<string>>,
  nicToSubnet: Map<string, string>,
  vmToNic: Map<string, string>,
): RgLayout {
  const vnets = rgInv.filter((r) => r.type.toLowerCase() === 'microsoft.network/virtualnetworks');
  const standaloneSubnets = rgInv.filter(
    (r) => r.type.toLowerCase() === 'microsoft.network/virtualnetworks/subnets',
  );
  // Synthesise subnets from each VNet`s properties.subnets[] when they are
  // not exposed as their own ARG rows.
  const embeddedSubnets: ArgResource[] = [];
  for (const vnet of vnets) {
    const p = (vnet.properties ?? {}) as Record<string, unknown>;
    const sns = Array.isArray(p.subnets) ? (p.subnets as Array<Record<string, unknown>>) : [];
    for (const sn of sns) {
      const snId = sn.id as string | undefined;
      if (!snId) continue;
      if (standaloneSubnets.some((x) => x.id.toLowerCase() === snId.toLowerCase())) continue;
      embeddedSubnets.push({
        id: snId,
        name: sn.name as string,
        type: 'microsoft.network/virtualnetworks/subnets',
        kind: null,
        location: vnet.location,
        resourceGroup: vnet.resourceGroup,
        subscriptionId: vnet.subscriptionId,
        sku: null,
        identity: null,
        tags: null,
        properties: (sn.properties as Record<string, unknown>) ?? {},
        managedBy: null,
      });
    }
  }
  const subnets = [...standaloneSubnets, ...embeddedSubnets];
  const subnetParent = new Map<string, string>();
  for (const sn of subnets) {
    subnetParent.set(sn.id.toLowerCase(), sn.id.replace(/\/subnets\/[^/]+$/i, '').toLowerCase());
  }

  // Brute-force properties scan to find each resource`s subnet home when
  // the inferred edges didn`t catch it (embedded subnets aren`t in the
  // edge inference`s idSet so they don`t generate in-subnet edges).
  const resourceSubnet = new Map<string, string>();
  const subnetIdsLower = subnets.map((s) => s.id.toLowerCase());
  for (const r of rgInv) {
    const rid = r.id.toLowerCase();
    if (!r.properties) continue;
    const json = JSON.stringify(r.properties).toLowerCase();
    for (const snIdLower of subnetIdsLower) {
      if (json.includes(snIdLower)) {
        resourceSubnet.set(rid, snIdLower);
        break;
      }
    }
  }

  // Decide each non-network resource`s home (subnet or band)
  const subnetResources = new Map<string, ArgResource[]>();
  const bandResources: Record<BandName, ArgResource[]> = {
    edge: [], platform: [], observability: [], other: [],
  };
  for (const r of rgInv) {
    const rid = r.id.toLowerCase();
    const rtype = r.type.toLowerCase();
    if (
      rtype === 'microsoft.network/virtualnetworks' ||
      rtype === 'microsoft.network/virtualnetworks/subnets'
    ) continue;
    // 1. in-subnet edges
    let foundSubnet: string | undefined;
    for (const [snId, mems] of subnetMembers) {
      if (mems.has(rid)) { foundSubnet = snId; break; }
    }
    // 2. Properties scan
    if (!foundSubnet) foundSubnet = resourceSubnet.get(rid);
    // 3. VM → NIC → subnet bubble-up
    if (!foundSubnet && rtype === 'microsoft.compute/virtualmachines') {
      const nicId = vmToNic.get(rid);
      if (nicId) {
        foundSubnet = nicToSubnet.get(nicId) ?? resourceSubnet.get(nicId);
      }
    }
    if (foundSubnet && subnetParent.has(foundSubnet)) {
      const arr = subnetResources.get(foundSubnet) ?? [];
      arr.push(r);
      subnetResources.set(foundSubnet, arr);
      continue;
    }
    const band = BAND_BY_TYPE[rtype] ?? 'other';
    bandResources[band].push(r);
  }

  // VNet layouts
  const vnetLayouts: VNetLayout[] = [];
  for (const vnet of vnets) {
    const childSubnets = subnets
      .filter((s) => subnetParent.get(s.id.toLowerCase()) === vnet.id.toLowerCase())
      .sort((a, b) => a.name.localeCompare(b.name));
    const snLayouts: SubnetLayout[] = [];
    let innerH = 0;
    for (const sn of childSubnets) {
      const inside = subnetResources.get(sn.id.toLowerCase()) ?? [];
      const count = Math.max(1, inside.length);
      const rows = Math.ceil(count / 6);
      const h = SUBNET_PAD_TOP + (rows * ICON_H + (rows - 1) * ICON_ROW_GAP) + 20;
      const w = RG_WIDTH - VNET_PAD_X * 2 - 30;
      snLayouts.push({ subnet: sn, resources: inside, width: w, height: h });
      innerH += h + 16;
    }
    const vh = VNET_PAD_TOP + Math.max(innerH, 80) + 20;
    vnetLayouts.push({
      vnet,
      subnets: snLayouts,
      width: RG_WIDTH - RG_PAD_X * 2,
      height: vh,
    });
  }

  const bandLayouts: BandLayout[] = [];
  for (const name of ['edge', 'platform', 'observability', 'other'] as BandName[]) {
    const rs = bandResources[name];
    if (rs.length === 0) continue;
    const count = rs.length;
    const rows = Math.ceil(count / 8);
    const h = 32 + (rows * ICON_H + (rows - 1) * ICON_ROW_GAP) + 20;
    bandLayouts.push({ name, resources: rs, width: RG_WIDTH - RG_PAD_X * 2, height: h });
  }

  let rgInnerH = 0;
  for (const v of vnetLayouts) rgInnerH += v.height + 24;
  for (const b of bandLayouts) rgInnerH += b.height + 24;
  const rgH = RG_PAD_TOP + Math.max(rgInnerH, 160) + 20;

  return { rg: rgName, width: RG_WIDTH, height: rgH, vnets: vnetLayouts, bands: bandLayouts };
}

async function emitBand(
  band: BandLayout,
  parentId: string,
  x: number,
  y: number,
  w: number,
  cells: string[],
  nextId: () => number,
  declared: Set<string>,
  idMap: Map<string, string>,
  iconCache: Map<string, string>,
): Promise<void> {
  const spec = BAND_SPEC[band.name];
  const bandCellId = `band_${nextId()}`;
  cells.push(
    `<mxCell id="${bandCellId}" value="${xmlEscape(spec.title)}" style="rounded=1;whiteSpace=wrap;html=1;fillColor=${spec.fill};strokeColor=${spec.stroke};strokeWidth=1;container=1;collapsible=0;verticalAlign=top;align=left;spacingLeft=12;spacingTop=4;fontSize=11;fontStyle=2;fontColor=#475569;" vertex="1" parent="${parentId}">
  <mxGeometry x="${x}" y="${y}" width="${w}" height="${band.height}" as="geometry" />
</mxCell>`,
  );
  const sorted = [...band.resources].sort(
    (a, b) => a.type.localeCompare(b.type) || a.name.localeCompare(b.name),
  );
  let i = 0;
  for (const r of sorted) {
    const col = i % 8;
    const row = Math.floor(i / 8);
    const rx = 22 + col * (ICON_W + ICON_COL_GAP);
    const ry = 32 + row * (ICON_H + ICON_ROW_GAP);
    const id = await safeId(r.id);
    declared.add(id);
    idMap.set(r.id.toLowerCase(), id);
    const shortType = r.type.split('/').pop() ?? r.type;
    const label = `${xmlEscape(r.name)}&#10;<font style='font-size:9px;color:#6a7388;'>${xmlEscape(shortType)}</font>`;
    const iconName = ICON_BY_TYPE[r.type.toLowerCase()] ?? '_default';
    const dataUri = iconCache.get(iconName) ?? '';
    cells.push(
      `<mxCell id="${id}" value="${label}" style="${shapeStyle(dataUri)}" vertex="1" parent="${bandCellId}">
  <mxGeometry x="${rx}" y="${ry}" width="${ICON_W}" height="${ICON_H}" as="geometry" />
</mxCell>`,
    );
    i++;
  }
}

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
