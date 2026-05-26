import { getArmToken } from '@/auth/getArmToken';

// `/api/arm` is rewritten by Vite (dev) or by the SWA Function (prod) to
// `https://management.azure.com`. The frontend never talks to ARM directly.
const ARM_BASE = '/api/arm';

async function armFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const token = await getArmToken();
  const url = path.startsWith('http') ? path : `${ARM_BASE}${path}`;
  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${token}`);
  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  const res = await fetch(url, { ...init, headers });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`ARM ${res.status} ${res.statusText} on ${path}: ${text.slice(0, 300)}`);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export interface Subscription {
  id: string;
  subscriptionId: string;
  displayName: string;
  state: string;
  tenantId: string;
}

export interface ResourceGroup {
  id: string;
  name: string;
  location: string;
  tags?: Record<string, string>;
}

export interface ArgResource {
  id: string;
  name: string;
  type: string;
  kind?: string | null;
  location: string;
  resourceGroup: string;
  subscriptionId: string;
  tenantId?: string;
  sku?: { name?: string; tier?: string } | null;
  identity?: { type?: string } | null;
  tags?: Record<string, string> | null;
  managedBy?: string | null;
  properties?: Record<string, unknown> | null;
}

export interface ArgPage<T> {
  data: T[];
  count: number;
  totalRecords: number;
  resultTruncated: 'true' | 'false';
  $skipToken?: string;
}

export async function listSubscriptions(): Promise<Subscription[]> {
  type Resp = { value: Subscription[] };
  const r = await armFetch<Resp>('/subscriptions?api-version=2022-12-01');
  return r.value ?? [];
}

export async function listResourceGroups(subscriptionId: string): Promise<ResourceGroup[]> {
  type Resp = { value: ResourceGroup[] };
  const r = await armFetch<Resp>(
    `/subscriptions/${subscriptionId}/resourcegroups?api-version=2022-12-01`,
  );
  return r.value ?? [];
}

/**
 * Run a KQL query against Azure Resource Graph and stream all pages.
 * Returns the full flat list of `T`.
 */
export async function argQuery<T = ArgResource>(
  query: string,
  subscriptions: string[],
): Promise<T[]> {
  const out: T[] = [];
  let skipToken: string | undefined;
  // Cap pages so a bug here never spins forever.
  for (let i = 0; i < 50; i++) {
    const body = {
      subscriptions,
      query,
      options: {
        $top: 1000,
        ...(skipToken ? { $skipToken: skipToken } : {}),
        resultFormat: 'objectArray',
      },
    };
    const page = await armFetch<ArgPage<T>>(
      '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01',
      { method: 'POST', body: JSON.stringify(body) },
    );
    out.push(...(page.data ?? []));
    if (!page.$skipToken) break;
    skipToken = page.$skipToken;
  }
  return out;
}

export async function listResources(
  subscriptionId: string,
  resourceGroup?: string,
): Promise<ArgResource[]> {
  const rgFilter = resourceGroup ? `| where resourceGroup =~ '${resourceGroup}'` : '';
  // Single-line KQL is mandatory: the ARM endpoint silently truncates after the
  // first LF on Windows-originated requests. Locked in via PowerShell regression test.
  const kql = [
    'Resources',
    rgFilter,
    `| project id, name, type, kind, location, resourceGroup, subscriptionId, tenantId, sku, identity, tags, managedBy, properties`,
    '| order by type asc, name asc',
  ]
    .filter(Boolean)
    .join(' ');
  return argQuery<ArgResource>(kql, [subscriptionId]);
}

export async function countByResourceGroup(
  subscriptionId: string,
): Promise<{ resourceGroup: string; count: number }[]> {
  const kql =
    'Resources | summarize count_=count() by resourceGroup | order by count_ desc | project resourceGroup, count=count_';
  type Row = { resourceGroup: string; count: number };
  return argQuery<Row>(kql, [subscriptionId]);
}
