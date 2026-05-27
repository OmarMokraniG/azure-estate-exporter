import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type SortingState,
} from '@tanstack/react-table';
import type { ArgResource } from '@/api/arm';
import { costByResource } from '@/api/arm';
import { metaForType } from '@/lib/resourceTypes';
import { analyzeFinOps } from '@/lib/finops';
import { useUi } from '@/state/store';
import {
  AlertTriangle,
  ChevronDown,
  ChevronUp,
  DollarSign,
  Lightbulb,
  PiggyBank,
  Search,
  TrendingUp,
} from 'lucide-react';
import clsx from 'clsx';

type Row = ArgResource & { cost?: number; currency?: string };

export function ResourcesTab({ resources }: { resources: ArgResource[] }) {
  const selectResource = useUi((s) => s.selectResource);
  const scope = useUi((s) => s.scope);
  const [filter, setFilter] = useState('');
  const [sorting, setSorting] = useState<SortingState>([{ id: 'cost', desc: true }]);
  const [showFinOps, setShowFinOps] = useState(true);

  const costQuery = useQuery({
    queryKey: ['cost-by-resource', scope.subscriptionId],
    queryFn: () =>
      scope.subscriptionId ? costByResource(scope.subscriptionId) : Promise.resolve([]),
    enabled: Boolean(scope.subscriptionId),
    staleTime: 30 * 60_000,
  });

  const rows = useMemo<Row[]>(() => {
    const costMap = new Map((costQuery.data ?? []).map((c) => [c.resourceId.toLowerCase(), c]));
    return resources.map((r) => {
      const c = costMap.get(r.id.toLowerCase());
      return { ...r, cost: c?.cost, currency: c?.currency };
    });
  }, [resources, costQuery.data]);

  const finops = useMemo(
    () => analyzeFinOps(resources, costQuery.data ?? []),
    [resources, costQuery.data],
  );

  const totalScopeCost = finops.headline.totalMonthlyCost;
  const currency = finops.headline.currency;

  const columns = useMemo<ColumnDef<Row>[]>(
    () => [
      {
        id: 'name',
        accessorKey: 'name',
        header: 'Name',
        cell: (c) => (
          <span className="font-medium text-accent underline-offset-2 hover:underline">
            {c.getValue<string>()}
          </span>
        ),
      },
      {
        id: 'type',
        accessorKey: 'type',
        header: 'Type',
        cell: (c) => (
          <span className="font-mono text-xs text-muted">
            {metaForType(c.getValue<string>()).label}
          </span>
        ),
      },
      { id: 'rg', accessorKey: 'resourceGroup', header: 'RG' },
      { id: 'location', accessorKey: 'location', header: 'Location' },
      {
        id: 'cost',
        accessorFn: (r) => r.cost ?? -1,
        header: 'Cost (MTD)',
        cell: (c) => {
          const v = c.getValue<number>();
          if (v < 0) return <span className="text-subtle">—</span>;
          const r = c.row.original;
          return (
            <span className="font-mono text-xs">
              {v.toFixed(2)}{' '}
              <span className="text-subtle">{r.currency ?? 'USD'}</span>
            </span>
          );
        },
      },
      {
        id: 'sku',
        accessorFn: (r) => r.sku?.name ?? '',
        header: 'SKU',
        cell: (c) => c.getValue<string>() || '—',
      },
    ],
    [],
  );

  const table = useReactTable({
    data: rows,
    columns,
    state: { globalFilter: filter, sorting },
    onGlobalFilterChange: setFilter,
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getSortedRowModel: getSortedRowModel(),
    globalFilterFn: 'includesString',
  });

  const costsAvailable = (costQuery.data?.length ?? 0) > 0;
  const costsLoading = costQuery.isLoading && Boolean(scope.subscriptionId);

  return (
    <div className="flex flex-col gap-4 p-4">
      {/* KPI cards */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KPI
          icon={DollarSign}
          label="Total (MTD)"
          value={
            costsAvailable
              ? `${totalScopeCost.toFixed(2)} ${currency}`
              : costsLoading
                ? '…'
                : 'n/a'
          }
          accent
        />
        <KPI
          icon={PiggyBank}
          label="Potential savings"
          value={
            costsAvailable
              ? `${finops.headline.potentialSavings.toFixed(2)} ${currency}`
              : `${finops.headline.findingCount} finding(s)`
          }
          tone={finops.headline.potentialSavings > 50 ? 'warn' : undefined}
          sub={costsAvailable ? '/month estimated' : undefined}
        />
        <KPI
          icon={Lightbulb}
          label="Findings"
          value={String(finops.headline.findingCount)}
          tone={finops.headline.findingCount > 0 ? 'warn' : undefined}
        />
        <KPI
          icon={TrendingUp}
          label="Top spender"
          value={finops.topSpenders[0]?.name ?? 'n/a'}
          sub={
            finops.topSpenders[0]
              ? `${finops.topSpenders[0].cost.toFixed(2)} ${finops.topSpenders[0].currency}`
              : undefined
          }
        />
      </div>

      {!costsAvailable && !costsLoading && (
        <div className="flex gap-2 rounded-lg border border-amber-200 bg-amber-50/80 px-4 py-2.5 text-sm text-amber-900 dark:border-amber-900/40 dark:bg-amber-900/20 dark:text-amber-100">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <div>
            <strong>No cost data.</strong> Your account may lack{' '}
            <code className="font-mono">Cost Management Reader</code> on this subscription, the API
            may be throttled, or no usage has been recorded for the current period.
          </div>
        </div>
      )}

      {/* FinOps recommendations */}
      {finops.findings.length > 0 && (
        <div className="surface">
          <button
            type="button"
            className="flex w-full items-center justify-between gap-2 px-4 py-2.5 text-left text-sm font-semibold text-fg"
            onClick={() => setShowFinOps((v) => !v)}
          >
            <span className="flex items-center gap-2">
              <Lightbulb className="h-4 w-4 text-amber-500" />
              FinOps recommendations
              <span className="pill">{finops.findings.length}</span>
            </span>
            {showFinOps ? <ChevronUp className="h-4 w-4 text-muted" /> : <ChevronDown className="h-4 w-4 text-muted" />}
          </button>
          {showFinOps && (
            <div className="border-t border-default p-4">
              <p className="mb-2 text-xs text-subtle">
                Severity reflects estimated monthly impact. Savings figures are best-effort —
                verify per resource before acting.
              </p>
              <div className="overflow-x-auto">
                <table className="min-w-full text-sm">
                  <thead>
                    <tr className="border-b border-default text-left text-xs uppercase tracking-wider text-subtle">
                      <th className="px-3 py-2">Sev.</th>
                      <th className="px-3 py-2">Finding</th>
                      <th className="px-3 py-2">Resource</th>
                      <th className="px-3 py-2 text-right">Savings/mo</th>
                      <th className="px-3 py-2">Recommendation</th>
                    </tr>
                  </thead>
                  <tbody>
                    {finops.findings.map((f, i) => (
                      <tr
                        key={i}
                        className="border-b border-default last:border-0 hover:bg-surface-2/60"
                      >
                        <td className="px-3 py-2">
                          <SevPill sev={f.severity} />
                        </td>
                        <td className="px-3 py-2">{f.title}</td>
                        <td className="px-3 py-2 font-mono text-xs">
                          {f.resourceId ? (
                            <button
                              type="button"
                              className="text-accent underline-offset-2 hover:underline"
                              onClick={() => f.resourceId && selectResource(f.resourceId)}
                            >
                              {f.resourceName}
                            </button>
                          ) : (
                            '—'
                          )}
                        </td>
                        <td className="px-3 py-2 text-right font-mono text-xs">
                          {f.estimatedMonthlySavings > 0
                            ? `${f.estimatedMonthlySavings.toFixed(2)} ${f.currency}`
                            : '—'}
                        </td>
                        <td className="px-3 py-2 text-xs text-muted">{f.recommendation}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Service mix + top spenders */}
      {finops.serviceMix.length > 0 && (
        <div className="grid gap-3 lg:grid-cols-2">
          <div className="surface p-4">
            <h3 className="mb-2 text-sm font-semibold text-fg">Cost mix by service type</h3>
            <table className="min-w-full text-xs">
              <thead>
                <tr className="border-b border-default text-left text-subtle">
                  <th className="py-1.5">Service</th>
                  <th className="py-1.5 text-right">Count</th>
                  <th className="py-1.5 text-right">Cost</th>
                  <th className="py-1.5 text-right">%</th>
                </tr>
              </thead>
              <tbody>
                {finops.serviceMix.slice(0, 8).map((m, i) => (
                  <tr key={i} className="border-b border-default/50 last:border-0">
                    <td className="py-1.5 font-mono">{m.serviceType}</td>
                    <td className="py-1.5 text-right">{m.resourceCount}</td>
                    <td className="py-1.5 text-right">{m.totalCost.toFixed(2)}</td>
                    <td className="py-1.5 text-right">
                      <Bar value={m.percentOfTotal} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="surface p-4">
            <h3 className="mb-2 text-sm font-semibold text-fg">Top 10 resources by cost</h3>
            <table className="min-w-full text-xs">
              <thead>
                <tr className="border-b border-default text-left text-subtle">
                  <th className="py-1.5">Resource</th>
                  <th className="py-1.5">Type</th>
                  <th className="py-1.5 text-right">Cost</th>
                </tr>
              </thead>
              <tbody>
                {finops.topSpenders.map((t, i) => (
                  <tr key={i} className="border-b border-default/50 last:border-0">
                    <td className="py-1.5">
                      <button
                        type="button"
                        className="text-accent underline-offset-2 hover:underline"
                        onClick={() => selectResource(t.resourceId)}
                      >
                        {t.name}
                      </button>
                    </td>
                    <td className="py-1.5 font-mono">{metaForType(t.type).label}</td>
                    <td className="py-1.5 text-right font-mono">
                      {t.cost.toFixed(2)} {t.currency}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Resources table */}
      <div className="surface p-4">
        <div className="mb-3 flex items-center justify-between gap-2">
          <h3 className="text-sm font-semibold text-fg">
            Resources <span className="pill ml-1">{rows.length}</span>
          </h3>
          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-subtle" />
            <input
              type="search"
              placeholder="Filter…"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              className="input pl-8 max-w-xs"
            />
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              {table.getHeaderGroups().map((hg) => (
                <tr key={hg.id} className="border-b border-default text-left">
                  {hg.headers.map((h) => (
                    <th
                      key={h.id}
                      className="cursor-pointer px-3 py-2 text-xs font-semibold uppercase tracking-wider text-subtle"
                      onClick={h.column.getToggleSortingHandler()}
                    >
                      {flexRender(h.column.columnDef.header, h.getContext())}
                      {{ asc: ' ▲', desc: ' ▼' }[h.column.getIsSorted() as string] ?? ''}
                    </th>
                  ))}
                </tr>
              ))}
            </thead>
            <tbody>
              {table.getRowModel().rows.map((row) => (
                <tr
                  key={row.id}
                  className="cursor-pointer border-b border-default/50 transition-colors last:border-0 hover:bg-surface-2"
                  onClick={() => selectResource(row.original.id)}
                >
                  {row.getVisibleCells().map((cell) => (
                    <td key={cell.id} className="px-3 py-2 text-fg">
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
          {!table.getRowModel().rows.length && (
            <p className="p-4 text-center text-sm text-subtle">No rows match the filter.</p>
          )}
        </div>
      </div>
    </div>
  );
}

function KPI({
  icon: Icon,
  label,
  value,
  sub,
  tone,
  accent,
}: {
  icon: typeof DollarSign;
  label: string;
  value: string;
  sub?: string;
  tone?: 'warn' | 'crit';
  accent?: boolean;
}) {
  const valClass = clsx(
    'text-lg font-semibold leading-tight truncate',
    tone === 'crit' && 'text-red-600 dark:text-red-400',
    tone === 'warn' && 'text-amber-600 dark:text-amber-400',
    !tone && accent && 'text-accent',
    !tone && !accent && 'text-fg',
  );
  return (
    <div className="surface flex items-center gap-3 px-4 py-3">
      <div
        className={clsx(
          'grid h-9 w-9 shrink-0 place-items-center rounded-lg',
          accent
            ? 'bg-accent text-white'
            : tone === 'warn'
              ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
              : 'bg-surface-2 text-muted',
        )}
      >
        <Icon className="h-4 w-4" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="text-[10px] uppercase tracking-wider text-subtle">{label}</div>
        <div className={valClass}>{value}</div>
        {sub && <div className="text-[11px] text-subtle">{sub}</div>}
      </div>
    </div>
  );
}

function SevPill({ sev }: { sev: 'High' | 'Medium' | 'Low' }) {
  return (
    <span className={`sev-pill sev-pill-${sev.toLowerCase()}`}>{sev}</span>
  );
}

function Bar({ value }: { value: number }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="inline-block h-1.5 w-20 overflow-hidden rounded-full bg-surface-2">
        <span
          className="block h-full rounded-full"
          style={{
            width: `${Math.min(100, Math.max(0, value))}%`,
            backgroundColor: 'rgb(var(--accent-bg))',
          }}
        />
      </span>
      <span className="font-mono text-[10px] text-muted">{value}%</span>
    </span>
  );
}
