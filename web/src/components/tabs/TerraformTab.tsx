import { useMemo, useState } from 'react';
import JSZip from 'jszip';
import { ChevronDown, Download, FileCode2, Terminal } from 'lucide-react';
import type { ArgResource } from '@/api/arm';
import { useUi } from '@/state/store';
import { generateTerraformRepo, isFullySupported, type GeneratedFile } from '@/lib/terraformGenerator';
import { FileTree } from '../terraform/FileTree';
import { CodeViewer } from '../terraform/CodeViewer';

export function TerraformTab({ resources }: { resources: ArgResource[] }) {
  const scope = useUi((s) => s.scope);
  const [selectedPath, setSelectedPath] = useState<string | null>(null);
  const [showCli, setShowCli] = useState(false);
  const [downloading, setDownloading] = useState(false);

  const files = useMemo<GeneratedFile[]>(() => {
    if (!scope.subscriptionId || resources.length === 0) return [];
    return generateTerraformRepo({
      subscriptionId: scope.subscriptionId,
      subscriptionName: scope.subscriptionName,
      resourceGroup: scope.resourceGroup,
      resources,
    });
  }, [scope.subscriptionId, scope.subscriptionName, scope.resourceGroup, resources]);

  const supported = resources.filter((r) => isFullySupported(r.type)).length;
  const totalCount = resources.length;
  const coverage = totalCount === 0 ? 0 : Math.round((supported / totalCount) * 100);

  const selectedFile = files.find((f) => f.path === selectedPath) ?? files[0] ?? null;
  if (selectedFile && !selectedPath) {
    queueMicrotask(() => setSelectedPath(selectedFile.path));
  }

  const downloadZip = async () => {
    if (!files.length) return;
    setDownloading(true);
    try {
      const zip = new JSZip();
      for (const f of files) zip.file(f.path, f.content);
      const blob = await zip.generateAsync({ type: 'blob' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      const slug =
        (scope.resourceGroup ?? scope.subscriptionName ?? scope.subscriptionId ?? 'estate').replace(
          /[^a-z0-9-_]+/gi,
          '-',
        );
      a.download = `terraform-repo-${slug}.zip`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 5_000);
    } finally {
      setDownloading(false);
    }
  };

  const rgFlag = scope.resourceGroup ? ` -ResourceGroup ${scope.resourceGroup}` : '';
  const cliExport = `Import-Module AzureEstateExporter; Export-AzureEstate -SubscriptionId ${scope.subscriptionId}${rgFlag}`;

  if (resources.length === 0) {
    return (
      <div className="grid h-[70vh] place-items-center text-sm text-subtle">
        No resources in scope — pick a subscription / RG first.
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col gap-3 p-4">
      {/* Header / toolbar */}
      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-default bg-surface-2/40 px-4 py-2.5">
        <FileCode2 className="h-4 w-4 text-accent" />
        <div className="text-sm text-fg">
          <strong>{coverage}%</strong> of {totalCount} resources rendered with native HCL
          {coverage < 100 && (
            <span className="ml-1 text-muted">— rest as commented stubs.</span>
          )}
        </div>
        <div className="ml-auto flex items-center gap-2">
          <button
            type="button"
            className="btn-primary !py-1.5 !text-xs"
            onClick={downloadZip}
            disabled={downloading || files.length === 0}
          >
            <Download className="h-3.5 w-3.5" />
            {downloading ? 'Zipping…' : 'Download .zip'}
          </button>
          <button
            type="button"
            className="btn-ghost !py-1.5 !text-xs"
            onClick={() => setShowCli((v) => !v)}
          >
            <Terminal className="h-3.5 w-3.5" />
            {showCli ? 'Hide CLI' : 'Show CLI'}
            <ChevronDown
              className={`h-3 w-3 transition-transform ${showCli ? 'rotate-180' : ''}`}
            />
          </button>
        </div>
      </div>

      {/* Tree + viewer */}
      <div className="grid h-[60vh] grid-cols-[260px_1fr] gap-3">
        <FileTree
          files={files}
          selectedPath={selectedFile?.path ?? null}
          onSelect={setSelectedPath}
        />
        <CodeViewer file={selectedFile} />
      </div>

      {/* Collapsible CLI handoff */}
      {showCli && (
        <details open className="surface p-4 text-sm text-fg">
          <summary className="cursor-pointer text-base font-semibold">
            Production-grade export (PowerShell + aztfexport)
          </summary>
          <p className="my-2 text-muted">
            The in-browser repo above is a fast baseline. To get a repo that <em>imports every
            resource into Terraform state</em> (so the first <code className="font-mono">terraform plan</code>{' '}
            shows <em>No changes</em>), run the PowerShell module locally — it shells out to{' '}
            <code className="font-mono">aztfexport</code> and produces a{' '}
            <code className="font-mono">bootstrap-import.ps1</code> alongside the HCL.
          </p>
          <pre className="overflow-x-auto rounded-lg bg-zinc-950 p-3 font-mono text-xs text-zinc-100">
{`# 1. Install prerequisites
winget install Microsoft.PowerShell
winget install Microsoft.AzureCLI
winget install HashiCorp.Terraform
winget install Microsoft.Azure.aztfexport

# 2. Clone + import the module
git clone https://github.com/OmarMokraniG/azure-estate-exporter.git
cd azure-estate-exporter
Import-Module ./src/AzureEstateExporter -Force

# 3. Export this scope (writes out/<timestamp>/terraform-repo/)
${cliExport} -RenameResources

# 4. Deploy
cd out/<timestamp>/terraform-repo/infra/${scope.resourceGroup ?? '<rg>'}
Copy-Item terraform.tfvars.example terraform.tfvars   # edit subscription_id
terraform init
./bootstrap-import.ps1 -WhatIf
./bootstrap-import.ps1
terraform plan   # No changes.`}
          </pre>
        </details>
      )}
    </div>
  );
}
