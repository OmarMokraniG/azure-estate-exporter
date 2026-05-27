import { useQuery } from '@tanstack/react-query';
import { listSubscriptions, listResourceGroups, countByResourceGroup } from '@/api/arm';
import { useUi } from '@/state/store';
import { useMemo, useState } from 'react';
import { ArrowRight, Box, Folder, Search, Layers } from 'lucide-react';
import clsx from 'clsx';

export function ScopePicker() {
  const setScope = useUi((s) => s.setScope);
  const [subId, setSubId] = useState<string>('');
  const [subFilter, setSubFilter] = useState('');
  const [rgFilter, setRgFilter] = useState('');

  const subs = useQuery({ queryKey: ['subscriptions'], queryFn: listSubscriptions });
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
  const totalResources = useMemo(
    () => [...countByRg.values()].reduce((a, b) => a + b, 0),
    [countByRg],
  );

  const filteredSubs = useMemo(() => {
    if (!subFilter) return subs.data ?? [];
    const q = subFilter.toLowerCase();
    return (subs.data ?? []).filter(
      (s) => s.displayName.toLowerCase().includes(q) || s.subscriptionId.includes(q),
    );
  }, [subs.data, subFilter]);

  const filteredRgs = useMemo(() => {
    if (!rgFilter) return rgs.data ?? [];
    const q = rgFilter.toLowerCase();
    return (rgs.data ?? []).filter(
      (r) => r.name.toLowerCase().includes(q) || r.location.toLowerCase().includes(q),
    );
  }, [rgs.data, rgFilter]);

  return (
    <section className="animate-fade-in">
      <header className="mb-4 flex flex-col gap-1">
        <h2 className="text-xl font-semibold text-fg">Pick a scope</h2>
        <p className="text-sm text-muted">
          Choose a subscription to start, then drill into an individual resource group or explore
          the whole subscription.
        </p>
      </header>

      <div className="grid gap-4 md:grid-cols-2">
        {/* Subscriptions */}
        <div className="surface flex h-[64vh] flex-col p-4">
          <div className="mb-3 flex items-center justify-between">
            <h3 className="flex items-center gap-2 text-sm font-semibold text-fg">
              <Layers className="h-4 w-4 text-accent" /> Subscriptions
              <span className="pill">{subs.data?.length ?? 0}</span>
            </h3>
          </div>
          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-subtle" />
            <input
              className="input pl-8"
              type="search"
              placeholder="Filter subscriptions…"
              value={subFilter}
              onChange={(e) => setSubFilter(e.target.value)}
            />
          </div>
          <ul className="mt-3 flex-1 divide-y divide-default overflow-y-auto pr-1">
            {subs.isLoading &&
              [...Array(4)].map((_, i) => (
                <li key={i} className="py-2.5">
                  <div className="skeleton h-9 w-full" />
                </li>
              ))}
            {subs.error && (
              <li className="py-2.5 text-sm text-red-500">{(subs.error as Error).message}</li>
            )}
            {filteredSubs.map((s) => (
              <li key={s.subscriptionId}>
                <button
                  type="button"
                  onClick={() => setSubId(s.subscriptionId)}
                  className={clsx(
                    'flex w-full items-center justify-between gap-3 px-2 py-2.5 text-left text-sm transition-colors',
                    subId === s.subscriptionId
                      ? 'bg-accent-soft'
                      : 'hover:bg-surface-2',
                  )}
                >
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-medium text-fg">{s.displayName}</div>
                    <div className="truncate font-mono text-[11px] text-subtle">
                      {s.subscriptionId}
                    </div>
                  </div>
                  {subId === s.subscriptionId && (
                    <ArrowRight className="h-3.5 w-3.5 text-accent" />
                  )}
                </button>
              </li>
            ))}
            {!subs.isLoading && filteredSubs.length === 0 && (
              <li className="py-4 text-center text-xs text-subtle">
                No subscriptions match the filter.
              </li>
            )}
          </ul>
        </div>

        {/* Scope inside the chosen sub */}
        <div className="surface flex h-[64vh] flex-col p-4">
          <div className="mb-3 flex items-center justify-between">
            <h3 className="flex items-center gap-2 text-sm font-semibold text-fg">
              <Folder className="h-4 w-4 text-accent" /> Resource groups
              {subId && <span className="pill">{rgs.data?.length ?? 0}</span>}
            </h3>
          </div>
          {!subId && (
            <div className="flex h-full items-center justify-center text-sm text-subtle">
              Pick a subscription on the left.
            </div>
          )}
          {subId && (
            <>
              <button
                type="button"
                className="btn-primary mb-3 w-full justify-between !py-2.5"
                onClick={() =>
                  setScope({
                    subscriptionId: subId,
                    subscriptionName: selectedSub?.displayName,
                    tenantId: selectedSub?.tenantId,
                    resourceGroup: undefined,
                  })
                }
              >
                <span className="flex items-center gap-2">
                  <Box className="h-4 w-4" /> Explore entire subscription
                </span>
                <span className="rounded-full bg-white/20 px-2 py-0.5 text-xs">
                  {totalResources} resources
                </span>
              </button>

              <div className="relative">
                <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-subtle" />
                <input
                  className="input pl-8"
                  type="search"
                  placeholder="Filter resource groups…"
                  value={rgFilter}
                  onChange={(e) => setRgFilter(e.target.value)}
                />
              </div>

              <ul className="mt-3 flex-1 divide-y divide-default overflow-y-auto pr-1">
                {rgs.isLoading &&
                  [...Array(4)].map((_, i) => (
                    <li key={i} className="py-2.5">
                      <div className="skeleton h-9 w-full" />
                    </li>
                  ))}
                {filteredRgs.map((rg) => {
                  const c = countByRg.get(rg.name.toLowerCase()) ?? 0;
                  return (
                    <li key={rg.id}>
                      <button
                        type="button"
                        className="flex w-full items-center justify-between gap-3 px-2 py-2.5 text-left text-sm transition-colors hover:bg-surface-2"
                        onClick={() =>
                          setScope({
                            subscriptionId: subId,
                            subscriptionName: selectedSub?.displayName,
                            tenantId: selectedSub?.tenantId,
                            resourceGroup: rg.name,
                          })
                        }
                      >
                        <div className="min-w-0 flex-1">
                          <div className="truncate font-medium text-fg">{rg.name}</div>
                          <div className="text-[11px] text-subtle">{rg.location}</div>
                        </div>
                        <span className="pill">{c} resources</span>
                      </button>
                    </li>
                  );
                })}
                {!rgs.isLoading && filteredRgs.length === 0 && (
                  <li className="py-4 text-center text-xs text-subtle">No RGs match the filter.</li>
                )}
              </ul>
            </>
          )}
        </div>
      </div>
    </section>
  );
}
