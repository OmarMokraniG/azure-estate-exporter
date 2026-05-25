# Usage

## Install prerequisites

| Tool | Min version | Install |
|------|-------------|---------|
| PowerShell | 7.2 | `winget install Microsoft.PowerShell` |
| Azure CLI | 2.60 | `winget install Microsoft.AzureCLI` |
| Terraform | 1.5 | `winget install Hashicorp.Terraform` |
| `aztfexport` | 0.15 | `winget install Microsoft.Azure.aztfexport` (or `go install github.com/Azure/aztfexport@latest`) |

```powershell
az login
az account set --subscription <id>     # only if you have several
```

## Import the module

```powershell
git clone https://github.com/OmarMokraniG/azure-estate-exporter.git
cd azure-estate-exporter
Import-Module ./src/AzureEstateExporter -Force
Get-Help Export-AzureEstate -Full
```

## Common recipes

### Inventory only — fast, cheap, no `aztfexport` required

```powershell
Export-AzureEstate -InventoryOnly -OutputPath ./out
```

### One resource group, fully exported

```powershell
Export-AzureEstate `
  -SubscriptionId 00000000-0000-0000-0000-000000000000 `
  -ResourceGroup  my-rg `
  -OutputPath     ./out
```

### A whole subscription, Mermaid diagram only

```powershell
Export-AzureEstate `
  -SubscriptionId 00000000-0000-0000-0000-000000000000 `
  -DiagramOnly `
  -Diagram Mermaid
```

### A whole tenant — careful

```powershell
Export-AzureEstate `
  -TenantId 11111111-1111-1111-1111-111111111111 `
  -ConfirmLargeExport `
  -ResourceLimit 5000
```

A preflight count is printed and the run aborts if it exceeds `-ResourceLimit` unless `-ConfirmLargeExport` is passed.

### Dry run — preview without writing anything

```powershell
Export-AzureEstate -SubscriptionId <id> -InventoryOnly -WhatIf
```

## Output

```
out/2026-05-25T13-00-00/
├── README.md
├── inventory.json
├── graph.json
├── manifest.json
├── errors.json
├── report/report.md
├── diagrams/estate.mmd       (always when -Diagram includes Mermaid)
├── diagrams/estate.excalidraw (when -Diagram is Excalidraw or Both)
└── terraform/<sub>/<rg>/...   (when not -InventoryOnly / -DiagramOnly)
```

## Re-running and diffs

`manifest.json` records the deterministic mapping `azure_resource_id -> terraform_address`. Re-runs reuse the same mapping, so:

```powershell
diff (Get-Content out/2026-05-25T13-00-00/inventory.json) `
     (Get-Content out/2026-05-25T14-30-00/inventory.json)
```

shows only real estate drift, not formatter noise.

## Troubleshooting

- **`aztfexport not found`** — install it (`winget install Microsoft.Azure.aztfexport`). The rest of the run continues; the failure is recorded in `errors.json`.
- **`Not logged in. Run az login`** — `az login` once on this machine.
- **ARG returns 0 rows** — the calling principal lacks Reader on the target. See [`docs/permissions.md`](permissions.md).
- **Excalidraw scene is unreadable** — over 300 resources is too many for a flat layout. Use Mermaid or render per-RG.
