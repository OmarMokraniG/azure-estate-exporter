import { useMemo, useState } from 'react';
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
import { metaForType } from '@/lib/resourceTypes';
import { useUi } from '@/state/store';

export function ResourcesTab({ resources }: { resources: ArgResource[] }) {
  const selectResource = useUi((s) => s.selectResource);
  const [filter, setFilter] = useState('');
  const [sorting, setSorting] = useState<SortingState>([{ id: 'name', desc: false }]);

  const columns = useMemo<ColumnDef<ArgResource>[]>(
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
        id: 'sku',
        accessorFn: (r) => r.sku?.name ?? '',
        header: 'SKU',
        cell: (c) => c.getValue<string>() || '—',
      },
      {
        id: 'kind',
        accessorFn: (r) => r.kind ?? '',
        header: 'Kind',
        cell: (c) => c.getValue<string>() || '—',
      },
    ],
    [],
  );

  const table = useReactTable({
    data: resources,
    columns,
    state: { globalFilter: filter, sorting },
    onGlobalFilterChange: setFilter,
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getSortedRowModel: getSortedRowModel(),
    globalFilterFn: 'includesString',
  });

  return (
    <div className="flex flex-col gap-3 p-4">
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
