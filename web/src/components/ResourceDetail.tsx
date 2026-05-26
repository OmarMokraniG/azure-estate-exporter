import { useUi } from '@/state/store';
import type { ArgResource } from '@/api/arm';
import { metaForType } from '@/lib/resourceTypes';

export function ResourceDetail({ resources }: { resources: ArgResource[] }) {
  const id = useUi((s) => s.selectedResourceId);
  const close = useUi((s) => s.selectResource);
  const r = id ? resources.find((x) => x.id === id) : null;

  if (!r) return null;

  const meta = metaForType(r.type);
  const json = JSON.stringify(r, null, 2);

  return (
    <aside
      className="fixed inset-y-0 right-0 z-30 flex w-full max-w-xl flex-col border-l border-slate-200 bg-white shadow-2xl"
      aria-label="Resource detail"
    >
      <div className="flex items-start justify-between border-b border-slate-200 p-4">
        <div className="min-w-0">
          <div className="text-xs uppercase tracking-wider text-slate-500">{meta.label}</div>
          <h3 className="truncate text-lg font-semibold">{r.name}</h3>
          <div className="truncate font-mono text-xs text-slate-500">{r.id}</div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => close(null)} aria-label="Close">
          ✕
        </button>
      </div>
      <div className="grid grid-cols-2 gap-3 border-b border-slate-200 p-4 text-sm">
        <KeyVal k="Type" v={r.type} mono />
        <KeyVal k="Location" v={r.location} />
        <KeyVal k="Resource Group" v={r.resourceGroup} />
        <KeyVal k="Kind" v={r.kind ?? '—'} />
        <KeyVal k="SKU" v={r.sku?.name ?? '—'} />
        <KeyVal k="Identity" v={r.identity?.type ?? '—'} />
      </div>
      <div className="flex-1 overflow-auto p-0">
        <pre className="m-0 whitespace-pre-wrap break-words p-4 font-mono text-xs text-slate-800">
          {json}
        </pre>
      </div>
    </aside>
  );
}

function KeyVal({ k, v, mono }: { k: string; v: string; mono?: boolean }) {
  return (
    <div>
      <div className="text-xs uppercase tracking-wider text-slate-500">{k}</div>
      <div className={`truncate ${mono ? 'font-mono text-xs' : ''}`}>{v}</div>
    </div>
  );
}
