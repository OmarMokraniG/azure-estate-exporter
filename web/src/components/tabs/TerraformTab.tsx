import { useState } from 'react';
import { useUi } from '@/state/store';

export function TerraformTab() {
  const scope = useUi((s) => s.scope);
  const [copied, setCopied] = useState<string | null>(null);

  const rgFlag = scope.resourceGroup ? ` -ResourceGroup ${scope.resourceGroup}` : '';
  const exportCmd = `Import-Module AzureEstateExporter; Export-AzureEstate -SubscriptionId ${scope.subscriptionId}${rgFlag}`;
  const repackageCmd = `Import-Module AzureEstateExporter; New-AzureEstateTerraformRepo -InputPath ./out/<timestamp> -InitGit -Force`;

  const install = [
    '# Prerequisites:',
    'winget install Microsoft.PowerShell',
    'winget install Microsoft.AzureCLI',
    'winget install HashiCorp.Terraform',
    'winget install Microsoft.Azure.aztfexport',
    '',
    '# Get the module (clone for now; PowerShell Gallery release pending):',
    'git clone https://github.com/OmarMokraniG/azure-estate-exporter.git',
    'cd azure-estate-exporter',
    'Import-Module ./src/AzureEstateExporter -Force',
  ].join('\n');

  const useRepo = [
    '# Inside the generated terraform-repo/:',
    'cd out/<timestamp>/terraform-repo/infra/<rg>',
    'Copy-Item terraform.tfvars.example terraform.tfvars  # edit subscription_id',
    'terraform init',
    './bootstrap-import.ps1 -WhatIf   # dry run',
    './bootstrap-import.ps1           # imports each resource into local state',
    'terraform plan                   # should say: No changes.',
  ].join('\n');

  const copy = async (text: string, label: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(label);
      setTimeout(() => setCopied(null), 1800);
    } catch {
      // ignored; clipboard may be blocked
    }
  };

  const Btn = ({ text, label }: { text: string; label: string }) => (
    <button type="button" className="btn-ghost mt-2" onClick={() => copy(text, label)}>
      {copied === label ? 'Copied!' : `Copy ${label}`}
    </button>
  );

  return (
    <div className="space-y-6 p-6">
      <div className="rounded-md border-l-4 border-amber-400 bg-amber-50 p-4 text-sm text-amber-900">
        <strong>Terraform export runs locally.</strong> Microsoft&apos;s{' '}
        <code className="font-mono">aztfexport</code> is a Go binary and cannot run in the browser,
        so this tab gives you the commands to run on your own machine. No state is touched: the
        module defaults to <code className="font-mono">--hcl-only</code>.
      </div>

      <div>
        <h3 className="mb-2 font-semibold">1. Install prerequisites (once)</h3>
        <pre className="overflow-x-auto rounded bg-slate-900 p-4 font-mono text-xs text-slate-100">
{install}
        </pre>
        <Btn text={install} label="install commands" />
      </div>

      <div>
        <h3 className="mb-2 font-semibold">2. Export this scope</h3>
        <p className="mb-2 text-sm text-slate-600">
          Generates <code className="font-mono">out/&lt;timestamp&gt;/</code> with inventory, diagrams,
          per-RG <code className="font-mono">terraform/</code> output, AND a packaged{' '}
          <code className="font-mono">terraform-repo/</code> folder you can clone and run.
        </p>
        <pre className="overflow-x-auto rounded bg-slate-900 p-4 font-mono text-xs text-slate-100">
{exportCmd}
        </pre>
        <Btn text={exportCmd} label="export command" />
      </div>

      <div>
        <h3 className="mb-2 font-semibold">3. Deploy the generated baseline</h3>
        <p className="mb-2 text-sm text-slate-600">
          Each <code className="font-mono">infra/&lt;rg&gt;/</code> folder is a self-contained Terraform
          working dir with a <code className="font-mono">bootstrap-import.ps1</code> that imports
          every existing resource into local state so the first{' '}
          <code className="font-mono">terraform plan</code> shows <em>No changes</em>.
        </p>
        <pre className="overflow-x-auto rounded bg-slate-900 p-4 font-mono text-xs text-slate-100">
{useRepo}
        </pre>
        <Btn text={useRepo} label="deploy commands" />
      </div>

      <div>
        <h3 className="mb-2 font-semibold">4. Re-package an existing export (optional)</h3>
        <p className="mb-2 text-sm text-slate-600">
          Already have an old <code className="font-mono">out/&lt;timestamp&gt;/</code>? Repackage
          its <code className="font-mono">terraform/</code> output into a deployable repo without
          re-running <code className="font-mono">aztfexport</code>:
        </p>
        <pre className="overflow-x-auto rounded bg-slate-900 p-4 font-mono text-xs text-slate-100">
{repackageCmd}
        </pre>
        <Btn text={repackageCmd} label="re-package command" />
      </div>

      <div className="text-sm text-slate-600">
        <p>
          <strong>Important:</strong> the generated repo is a baseline, not a perfect clone.{' '}
          <code className="font-mono">aztfexport</code> does not capture secrets, data-plane
          contents, runtime config or unsupported resource types. See{' '}
          <code className="font-mono">docs/coverage.md</code> in the generated repo for details.
        </p>
      </div>
    </div>
  );
}
