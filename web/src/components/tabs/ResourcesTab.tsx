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

type Row = ArgResource & { cost?: number; currency?: string };

export function ResourcesTab({ resources }: { resources: ArgResource[] }) {
  const selectResource = useUi((s) => s.selectResource);
  const scope = useUi((s) => s.scope);
  const [filter, setFilter] = useState('');
  const [sorting, setSorting] = useState<SortingState>([{ id: 'cost', desc: true }]);

  // Cost Management — fetched once per subscription. Stale-time is large
  // because cost data updates daily on Azure`s side anyway.
  const costQuery = useQuery({
    queryKey: ['cost-by-resource', scope.subscriptionId],
    queryFn: () => (scope.subscriptionId ? costByResource(scope.subscriptionId) : Promise.resolve([])),
    enabled: Boolean(scope.subscriptionId),
    staleTime: 30 * 60_000,
  });

  // Join resources with cost client-side.
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
          <span className="font-medium text-azure-700 underline-offset-2 hover:underline">
            {c.getValue<string>()}
          </span>
        ),
      },
      {
        id: 'type',
        accessorKey: 'type',
        header: 'Type',
        cell: (c) => (
          <span className="font-mono text-xs text-slate-600">
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
          if (v < 0) return <span className="text-slate-300">—</span>;
          const r = c.row.original;
          return (
            <span className="font-mono text-xs">
              {v.toFixed(2)} <span className="text-slate-400">{r.currency ?? 'USD'}</span>
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
      {/* FinOps headline */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KPI
          label="Total (MTD)"
          value={costsAvailable ? `${totalScopeCost.toFixed(2)} ${currency}` : costsLoading ? '…' : 'n/a'}
        />
        <KPI
          label="Potential savings"
          value={
            costsAvailable
              ? `${finops.headline.potentialSavings.toFixed(2)} ${currency}/mo`
              : `${finops.headline.findingCount} finding(s)`
          }
          tone={finops.headline.potentialSavings > 0 ? 'warn' : undefined}
        />
        <KPI label="Findings" value={String(finops.headline.findingCount)} />
        <KPI
          label="Top spender"
          value={
            finops.topSpenders[0]
              ? `${finops.topSpenders[0].name}`
              : 'n/a'
          }
          sub={
            finops.topSpenders[0]
              ? `${finops.topSpenders[0].cost.toFixed(2)} ${finops.topSpenders[0].currency}`
              : undefined
          }
        />
      </div>

      {!costsAvailable && !costsLoading && (
        <div className="rounded-md border-l-4 border-amber-400 bg-amber-50 px-4 py-2 text-sm text-amber-900">
          <strong>No cost data.</strong> Either your account lacks{' '}
          <code className="font-mono">Cost Management Reader</code> on this subscription, the API was
          throttled, or no usage has been recorded for the current period. The Resources table works
          regardless; the Cost column will stay empty.
        </div>
      )}

      {/* FinOps recommendations */}
      {finops.findings.length > 0 && (
        <details open className="card p-4 text-sm">
          <summary className="cursor-pointer text-base font-semibold">
            FinOps recommendations ({finops.findings.length})
          </summary>
          <p className="mt-1 text-xs text-slate-500">
            Severity is based on the estimated monthly impact. Savings figures are best-effort and
            should be reviewed per-resource before acting.
          </p>
          <table className="mt-3 min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 bg-slate-50 text-left">
                <th className="px-3 py-2 font-semibold">Sev.</th>
                <th className="px-3 py-2 font-semibold">Finding</th>
                <th className="px-3 py-2 font-semibold">Resource</th>
                <th className="px-3 py-2 text-right font-semibold">Est. savings/mo</th>
                <th className="px-3 py-2 font-semibold">Recommendation</th>
              </tr>
            </thead>
            <tbody>
              {finops.findings.map((f, i) => (
                <tr key={i} className="border-b border-slate-100 hover:bg-slate-50">
                  <td className="px-3 py-2">
                    <SevPill sev={f.severity} />
                  </td>
                  <td className="px-3 py-2">{f.title}</td>
                  <td className="px-3 py-2 font-mono text-xs">
                    {f.resourceId ? (
                      <button
                        type="button"
                        className="text-azure-700 underline-offset-2 hover:underline"
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
                  <td className="px-3 py-2 text-xs text-slate-600">{f.recommendation}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </details>
      )}

      {/* Service mix + top spenders (compact) */}
      {finops.serviceMix.length > 0 && (
        <div className="grid gap-3 lg:grid-cols-2">
          <div className="card p-4">
            <h3 className="mb-2 text-sm font-semibold">Cost mix by service type</h3>
            <table className="min-w-full text-xs">
              <thead>
                <tr className="border-b border-slate-200 text-left text-slate-500">
                  <th className="py-1">Service</th>
                  <th className="py-1 text-right">Count</th>
                  <th className="py-1 text-right">Cost</th>
                  <th className="py-1 text-right">%</th>
                </tr>
              </thead>
              <tbody>
                {finops.serviceMix.slice(0, 8).map((m, i) => (
                  <tr key={i} className="border-b border-slate-100">
                    <td className="py-1 font-mono">{m.serviceType}</td>
                    <td className="py-1 text-right">{m.resourceCount}</td>
                    <td className="py-1 text-right">{m.totalCost.toFixed(2)}</td>
                    <td className="py-1 text-right">
                      <Bar value={m.percentOfTotal} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="card p-4">
            <h3 className="mb-2 text-sm font-semibold">Top 10 resources by cost</h3>
            <table className="min-w-full text-xs">
              <thead>
                <tr className="border-b border-slate-200 text-left text-slate-500">
                  <th className="py-1">Resource</th>
                  <th className="py-1">Type</th>
                  <th className="py-1 text-right">Cost</th>
                </tr>
              </thead>
              <tbody>
                {finops.topSpenders.map((t, i) => (
                  <tr key={i} className="border-b border-slate-100">
                    <td className="py-1">
                      <button
                        type="button"
                        className="text-azure-700 underline-offset-2 hover:underline"
                        onClick={() => selectResource(t.resourceId)}
                      >
                        {t.name}
                      </button>
                    </td>
                    <td className="py-1 font-mono">{metaForType(t.type).label}</td>
                    <td className="py-1 text-right font-mono">
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
      <input
        type="search"
        placeholder="Filter by name, type, RG, location…"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:border-azure-500 focus:outline-none focus:ring-2 focus:ring-azure-200"
      />
      <div className="overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead>
            {table.getHeaderGroups().map((hg) => (
              <tr key={hg.id} className="border-b border-slate-200 bg-slate-50">
                {hg.headers.map((h) => (
                  <th
                    key={h.id}
                    className="cursor-pointer px-3 py-2 text-left font-semibold text-slate-700"
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
                className="cursor-pointer border-b border-slate-100 hover:bg-slate-50"
                onClick={() => selectResource(row.original.id)}
              >
                {row.getVisibleCells().map((cell) => (
                  <td key={cell.id} className="px-3 py-2">
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
        {!table.getRowModel().rows.length && (
          <p className="p-4 text-center text-sm text-slate-500">No rows match the filter.</p>
        )}
      </div>
    </div>
  );
}

function KPI({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: string;
  sub?: string;
  tone?: 'warn' | 'crit';
}) {
  const valColour =
    tone === 'crit' ? 'text-red-700' : tone === 'warn' ? 'text-amber-700' : 'text-azure-700';
  return (
    <div className="card flex flex-col gap-1 px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-slate-500">{label}</div>
      <div className={`text-lg font-semibold ${valColour} truncate`}>{value}</div>
      {sub && <div className="text-xs text-slate-500">{sub}</div>}
    </div>
  );
}

function SevPill({ sev }: { sev: 'High' | 'Medium' | 'Low' }) {
  const cls =
    sev === 'High'
      ? 'bg-red-100 text-red-800'
      : sev === 'Medium'
        ? 'bg-amber-100 text-amber-800'
        : 'bg-emerald-100 text-emerald-800';
  return (
    <span className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold ${cls}`}>
      {sev}
    </span>
  );
}

function Bar({ value }: { value: number }) {
  return (
    <span className="inline-flex items-center gap-1">
      <span className="inline-block h-2 w-16 overflow-hidden rounded bg-slate-100">
        <span
          className="block h-full bg-azure-500"
          style={{ width: `${Math.min(100, Math.max(0, value))}%` }}
        />
      </span>
      <span className="font-mono text-[10px]">{value}%</span>
    </span>
  );
}
