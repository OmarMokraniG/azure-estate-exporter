import { Cog, Copy } from 'lucide-react';
import { useState } from 'react';

export function UnconfiguredBanner() {
  const [copied, setCopied] = useState(false);
  const cmd = 'pwsh -File scripts/create-app-reg.ps1';
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(cmd);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // ignore
    }
  };
  return (
    <div className="grid min-h-screen place-items-center bg-page p-6">
      <div className="surface w-full max-w-2xl animate-fade-in p-8">
        <div className="mb-4 flex items-center gap-3">
          <div className="grid h-10 w-10 place-items-center rounded-lg bg-accent text-white shadow-glow">
            <Cog className="h-5 w-5" />
          </div>
          <h2 className="text-xl font-semibold text-fg">Configure your Entra app registration</h2>
        </div>
        <p className="text-muted">
          This web app is unconfigured. Create an Entra app registration in your tenant and set the
          client id via the <code className="rounded bg-surface-2 px-1.5 py-0.5 font-mono text-xs">VITE_AZURE_CLIENT_ID</code>{' '}
          environment variable.
        </p>
        <p className="mt-3 text-muted">From the repo root, run:</p>
        <div className="mt-2 flex items-center gap-2 rounded-lg border border-default bg-surface-2 p-3 font-mono text-xs">
          <code className="flex-1 text-fg">{cmd}</code>
          <button type="button" className="btn-ghost !py-1" onClick={copy} title="Copy">
            <Copy className="h-3.5 w-3.5" />
            <span>{copied ? 'Copied!' : 'Copy'}</span>
          </button>
        </div>
        <p className="mt-3 text-xs text-subtle">
          The app needs the{' '}
          <code className="font-mono">Azure Service Management → user_impersonation</code>{' '}
          delegated permission and SPA redirect URI{' '}
          <code className="font-mono">http://localhost:5173</code>.
        </p>
      </div>
    </div>
  );
}
