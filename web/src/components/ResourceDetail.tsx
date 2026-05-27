import { useUi } from '@/state/store';
import type { ArgResource } from '@/api/arm';
import { metaForType } from '@/lib/resourceTypes';
import { Copy, ExternalLink, X } from 'lucide-react';
import { useState } from 'react';

export function ResourceDetail({ resources }: { resources: ArgResource[] }) {
  const id = useUi((s) => s.selectedResourceId);
  const close = useUi((s) => s.selectResource);
  const [copied, setCopied] = useState(false);
  const r = id ? resources.find((x) => x.id === id) : null;

  if (!r) return null;

  const meta = metaForType(r.type);
  const json = JSON.stringify(r, null, 2);
  const portal = `https://portal.azure.com/#@/resource${r.id}`;

  const copyId = async () => {
    try {
      await navigator.clipboard.writeText(r.id);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // ignore
    }
  };

  return (
    <>
      {/* Backdrop (click outside closes) */}
      <button
        type="button"
        aria-label="Close detail"
        className="fixed inset-0 z-20 bg-black/40 backdrop-blur-sm animate-fade-in"
        onClick={() => close(null)}
      />
      <aside
        className="fixed inset-y-0 right-0 z-30 flex w-full max-w-xl animate-slide-in-right flex-col border-l border-default bg-surface shadow-2xl"
        aria-label="Resource detail"
      >
        <div className="flex items-start justify-between gap-2 border-b border-default p-4">
          <div className="min-w-0">
            <div className="text-[10px] uppercase tracking-wider text-subtle">{meta.label}</div>
            <h3 className="truncate text-lg font-semibold text-fg">{r.name}</h3>
            <div className="mt-1 flex items-center gap-1 text-[11px] text-muted">
              <code className="truncate font-mono">{r.id}</code>
            </div>
          </div>
          <div className="flex items-center gap-1">
            <button
              type="button"
              className="btn-ghost !p-1.5"
              onClick={copyId}
              title="Copy resource id"
            >
              <Copy className="h-4 w-4" />
            </button>
            <a
              href={portal}
              target="_blank"
              rel="noreferrer"
              className="btn-ghost !p-1.5"
              title="Open in Azure portal"
            >
              <ExternalLink className="h-4 w-4" />
            </a>
            <button
              type="button"
              className="btn-ghost !p-1.5"
              onClick={() => close(null)}
              aria-label="Close"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 border-b border-default p-4 text-sm">
          <KeyVal k="Type" v={r.type} mono />
          <KeyVal k="Location" v={r.location} />
          <KeyVal k="Resource Group" v={r.resourceGroup} />
          <KeyVal k="Kind" v={r.kind ?? '—'} />
          <KeyVal k="SKU" v={r.sku?.name ?? '—'} />
          <KeyVal k="Identity" v={r.identity?.type ?? '—'} />
        </div>
        {r.tags && Object.keys(r.tags).length > 0 && (
          <div className="border-b border-default p-4">
            <div className="mb-1.5 text-[10px] uppercase tracking-wider text-subtle">Tags</div>
            <div className="flex flex-wrap gap-1.5">
              {Object.entries(r.tags).map(([k, v]) => (
                <span
                  key={k}
                  className="pill"
                  title={`${k}: ${v}`}
                >
                  <span className="font-medium text-fg">{k}</span>
                  <span className="text-subtle">=</span>
                  <span>{v}</span>
                </span>
              ))}
            </div>
          </div>
        )}
        <div className="flex-1 overflow-auto bg-surface-2/40">
          <pre className="m-0 whitespace-pre-wrap break-words p-4 font-mono text-xs text-fg">
            {json}
          </pre>
        </div>
        {copied && (
          <div className="pointer-events-none absolute bottom-4 right-4 rounded-md bg-fg px-3 py-1.5 text-xs text-page shadow-soft animate-fade-in">
            ID copied
          </div>
        )}
      </aside>
    </>
  );
}

function KeyVal({ k, v, mono }: { k: string; v: string; mono?: boolean }) {
  return (
    <div className="min-w-0">
      <div className="text-[10px] uppercase tracking-wider text-subtle">{k}</div>
      <div className={`truncate text-sm text-fg ${mono ? 'font-mono text-xs' : ''}`}>{v}</div>
    </div>
  );
}
