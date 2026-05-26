import { useState } from 'react';
import { useUi } from '@/state/store';

export function TerraformTab() {
  const scope = useUi((s) => s.scope);
  const [copied, setCopied] = useState(false);

  const cmd = scope.resourceGroup
    ? `Import-Module AzureEstateExporter; Export-AzureEstate -SubscriptionId ${scope.subscriptionId} -ResourceGroup ${scope.resourceGroup} -TerraformOnly`
    : `Import-Module AzureEstateExporter; Export-AzureEstate -SubscriptionId ${scope.subscriptionId} -TerraformOnly`;

  const install = [
    '# Prerequisites:',
    'winget install Microsoft.PowerShell',
    'winget install Microsoft.AzureCLI',
    'winget install HashiCorp.Terraform',
    'winget install Microsoft.Azure.aztfexport',
    '',
    '# Get the module (PowerShell Gallery release pending, clone for now):',
    'git clone https://github.com/OmarMokraniG/azure-estate-exporter.git',
    'cd azure-estate-exporter',
    'Import-Module ./src/AzureEstateExporter -Force',
  ].join('\n');

  const copy = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      // ignored; clipboard may be blocked
    }
  };

  return (
    <div className="space-y-6 p-6">
      <div className="rounded-md border-l-4 border-amber-400 bg-amber-50 p-4 text-sm text-amber-900">
        <strong>Terraform export runs locally.</strong> Microsoft's <code className="font-mono">aztfexport</code>
        is a Go binary and cannot run in the browser, so this tab generates a copy-paste command
        you run on your own machine. No state is touched: the module defaults to
        <code className="font-mono"> --hcl-only</code>.
      </div>

      <div>
        <h3 className="mb-2 font-semibold">1. Install prerequisites (once)</h3>
        <pre className="overflow-x-auto rounded bg-slate-900 p-4 font-mono text-xs text-slate-100">
{install}
        </pre>
        <button type="button" className="btn-ghost mt-2" onClick={() => copy(install)}>
          Copy install commands
        </button>
      </div>

      <div>
        <h3 className="mb-2 font-semibold">2. Export this scope to Terraform</h3>
        <pre className="overflow-x-auto rounded bg-slate-900 p-4 font-mono text-xs text-slate-100">
{cmd}
        </pre>
        <div className="mt-2 flex items-center gap-2">
          <button type="button" className="btn-primary" onClick={() => copy(cmd)}>
            {copied ? 'Copied!' : 'Copy command'}
          </button>
          <span className="text-xs text-slate-500">
            Output goes to <code className="font-mono">./out/&lt;timestamp&gt;/terraform/</code>.
          </span>
        </div>
      </div>

      <div className="text-sm text-slate-600">
        <p>
          Once you've run it, you'll have an HCL baseline you can <code className="font-mono">terraform plan</code>{' '}
          against the existing infra. The <code className="font-mono">aztfexport</code> tool exports{' '}
          <em>most</em> resource types — check{' '}
          <code className="font-mono">aztfexportSkippedResources.txt</code> in the output folder for
          anything it couldn't translate.
        </p>
      </div>
    </div>
  );
}
