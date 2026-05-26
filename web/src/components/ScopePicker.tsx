import { useQuery } from '@tanstack/react-query';
import { listSubscriptions, listResourceGroups, countByResourceGroup } from '@/api/arm';
import { useUi } from '@/state/store';
import { useMemo, useState } from 'react';

export function ScopePicker() {
  const setScope = useUi((s) => s.setScope);
  const [subId, setSubId] = useState<string>('');

  const subs = useQuery({
    queryKey: ['subscriptions'],
    queryFn: listSubscriptions,
  });

  const rgs = useQuery({
    queryKey: ['rgs', subId],
    queryFn: () => listResourceGroups(subId),
    enabled: Boolean(subId),
  });

  const counts = useQuery({
    queryKey: ['counts', subId],
    queryFn: () => countByResourceGroup(subId),
    enabled: Boolean(subId),
  });

  const countByRg = useMemo(() => {
    const m = new Map<string, number>();
    for (const c of counts.data ?? []) m.set(c.resourceGroup.toLowerCase(), c.count);
    return m;
  }, [counts.data]);

  const selectedSub = subs.data?.find((s) => s.subscriptionId === subId);

  return (
    <section className="grid gap-4 md:grid-cols-2">
      <div className="card p-5">
        <h3 className="mb-3 font-semibold">1. Choose a subscription</h3>
        {subs.isLoading && <p className="text-sm text-slate-500">Loading subscriptions…</p>}
        {subs.error && (
          <p className="text-sm text-red-600">{(subs.error as Error).message}</p>
        )}
        <ul className="max-h-[60vh] divide-y divide-slate-100 overflow-y-auto">
          {(subs.data ?? []).map((s) => (
            <li key={s.subscriptionId}>
              <button
                type="button"
                onClick={() => setSubId(s.subscriptionId)}
                className={`w-full px-2 py-2 text-left text-sm hover:bg-slate-50 ${
                  subId === s.subscriptionId ? 'bg-azure-50 ring-1 ring-azure-200' : ''
                }`}
              >
                <div className="font-medium">{s.displayName}</div>
                <div className="font-mono text-xs text-slate-500">{s.subscriptionId}</div>
              </button>
            </li>
          ))}
        </ul>
      </div>

      <div className="card p-5">
        <h3 className="mb-3 font-semibold">2. Choose a scope</h3>
        {!subId && <p className="text-sm text-slate-500">Pick a subscription on the left.</p>}
        {subId && (
          <div className="space-y-3">
            <button
              type="button"
              className="btn-primary w-full justify-between"
              onClick={() =>
                setScope({
                  subscriptionId: subId,
                  subscriptionName: selectedSub?.displayName,
                  tenantId: selectedSub?.tenantId,
                  resourceGroup: undefined,
                })
              }
            >
              <span>Explore entire subscription</span>
              <span className="pill bg-white text-azure-700">
                {[...countByRg.values()].reduce((a, b) => a + b, 0)} resources
              </span>
            </button>
            <div className="text-xs uppercase tracking-wider text-slate-500">…or pick an RG</div>
            <ul className="max-h-[50vh] divide-y divide-slate-100 overflow-y-auto">
              {(rgs.data ?? []).map((rg) => {
                const c = countByRg.get(rg.name.toLowerCase()) ?? 0;
                return (
                  <li key={rg.id}>
                    <button
                      type="button"
                      className="flex w-full items-center justify-between px-2 py-2 text-left text-sm hover:bg-slate-50"
                      onClick={() =>
                        setScope({
                          subscriptionId: subId,
                          subscriptionName: selectedSub?.displayName,
                          tenantId: selectedSub?.tenantId,
                          resourceGroup: rg.name,
                        })
                      }
                    >
                      <div>
                        <div className="font-medium">{rg.name}</div>
                        <div className="text-xs text-slate-500">{rg.location}</div>
                      </div>
                      <span className="pill">{c} resources</span>
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
        )}
      </div>
    </section>
  );
}
