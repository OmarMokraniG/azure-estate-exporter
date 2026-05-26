import type { ArgResource } from '@/api/arm';

/**
 * Heuristic edge inference, ported from the PowerShell module's
 * `ConvertTo-EstateModel.ps1`. Walks each resource's `properties` looking for
 * Azure resource id strings and labels the edge using the property name.
 *
 * Critical: IDictionary detection MUST happen before generic iteration —
 * otherwise a hashtable yields itself once and we recurse forever.
 * Locked in by the v0.2 regression tests.
 */
export interface Edge {
  from: string;
  to: string;
  relation: string;
  sourceProperty: string;
  kind: 'reference' | 'managed-by';
}

const RELATION_MAP: Record<string, string> = {
  serverfarmid: 'hosted-on',
  hostingenvironmentid: 'hosted-on',
  storageaccount: 'uses-storage',
  storageaccountid: 'uses-storage',
  keyvault: 'uses-key-vault',
  keyvaultid: 'uses-key-vault',
  subnet: 'in-subnet',
  subnetid: 'in-subnet',
  networksecuritygroup: 'protected-by',
  networksecuritygroupid: 'protected-by',
  privatelinkserviceid: 'private-endpoint-to',
  virtualnetwork: 'in-vnet',
  virtualnetworkid: 'in-vnet',
  remotevirtualnetwork: 'peered-with',
  workspaceresourceid: 'logs-to',
  workspaceid: 'logs-to',
  sourceid: 'sourced-from',
  sourceresource: 'sourced-from',
};

const ID_RE = /^\/subscriptions\/[0-9a-f-]{36}\/resourceGroups\/[^/]+\/providers\/.+/i;

function relationFor(key: string): string {
  const k = key.toLowerCase().replace(/_/g, '');
  return RELATION_MAP[k] ?? 'references';
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

export function inferEdges(resources: ArgResource[]): Edge[] {
  const ids = new Set(resources.map((r) => r.id.toLowerCase()));
  const seen = new Set<string>();
  const edges: Edge[] = [];

  const push = (e: Edge) => {
    const k = `${e.from}|${e.to}|${e.relation}|${e.sourceProperty}|${e.kind}`;
    if (seen.has(k)) return;
    seen.add(k);
    edges.push(e);
  };

  for (const r of resources) {
    if (r.managedBy && ids.has(r.managedBy.toLowerCase())) {
      push({
        from: r.managedBy,
        to: r.id,
        relation: 'managed-by',
        sourceProperty: 'managedBy',
        kind: 'managed-by',
      });
    }

    // Iterative walk so we never blow the stack on deep ARM resource trees.
    const stack: { value: unknown; path: string }[] = [{ value: r.properties, path: '' }];
    while (stack.length) {
      const { value, path } = stack.pop()!;
      if (value === null || value === undefined) continue;

      if (typeof value === 'string') {
        if (path && ID_RE.test(value) && value.toLowerCase() !== r.id.toLowerCase()) {
          const targetLower = value.toLowerCase();
          if (ids.has(targetLower)) {
            push({
              from: r.id,
              to: value,
              relation: relationFor(path.split('.').pop() ?? path),
              sourceProperty: path,
              kind: 'reference',
            });
          }
        }
        continue;
      }

      if (isPlainObject(value)) {
        // Some ARM shapes use { id: "/subscriptions/..." } objects.
        const maybeId = (value as { id?: unknown }).id;
        if (typeof maybeId === 'string' && ID_RE.test(maybeId)) {
          stack.push({ value: maybeId, path: path ? `${path}.id` : 'id' });
        }
        for (const [k, v] of Object.entries(value)) {
          stack.push({ value: v, path: path ? `${path}.${k}` : k });
        }
        continue;
      }

      if (Array.isArray(value)) {
        for (let i = 0; i < value.length; i++) {
          stack.push({ value: value[i], path: `${path}[${i}]` });
        }
      }
    }
  }

  return edges;
}
