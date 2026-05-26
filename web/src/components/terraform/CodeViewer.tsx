import { useState } from 'react';
import type { GeneratedFile } from '@/lib/terraformGenerator';

/**
 * Read-only HCL/markdown code viewer with line numbers and a copy button.
 * Deliberately frameworkless — no Monaco/Prism dependency so the bundle
 * stays under control.
 */
export function CodeViewer({ file }: { file: GeneratedFile | null }) {
  const [copied, setCopied] = useState(false);

  if (!file) {
    return (
      <div className="grid h-full place-items-center rounded border border-slate-200 bg-white text-sm text-slate-400">
        Select a file on the left to view it.
      </div>
    );
  }

  const lines = file.content.split('\n');
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(file.content);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      // clipboard may be blocked
    }
  };

  return (
    <div className="flex h-full flex-col rounded border border-slate-200 bg-white">
      <div className="flex items-center justify-between gap-2 border-b border-slate-200 bg-slate-50 px-3 py-1.5">
        <span className="truncate font-mono text-xs text-slate-700">{file.path}</span>
        <button type="button" className="btn-ghost !px-2 !py-0.5 text-xs" onClick={copy}>
          {copied ? 'Copied!' : 'Copy'}
        </button>
      </div>
      <div className="flex-1 overflow-auto">
        <pre className="m-0 grid grid-cols-[auto_1fr] gap-x-3 p-3 font-mono text-xs leading-relaxed text-slate-900">
          <span className="select-none text-right text-slate-400">
            {lines.map((_, i) => (
              <div key={i}>{i + 1}</div>
            ))}
          </span>
          <code className="whitespace-pre">{file.content}</code>
        </pre>
      </div>
    </div>
  );
}
