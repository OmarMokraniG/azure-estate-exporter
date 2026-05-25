# Examples

Each example below is a copy-pasteable PowerShell session. They assume `az login` has already been done and you have `Reader` on the target.

## 1. Document one resource group

```powershell
Import-Module ../src/AzureEstateExporter -Force

Export-AzureEstate `
  -SubscriptionId $(az account show --query id -o tsv) `
  -ResourceGroup my-existing-rg `
  -OutputPath ./out

# Open the Markdown report
code (Get-ChildItem out -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName/report/report.md
```

## 2. Inventory only — quick audit, no Terraform

```powershell
Export-AzureEstate -InventoryOnly -OutputPath ./audit
Get-Content (Get-ChildItem audit -Directory)[-1].FullName/report/report.md | Out-Host
```

## 3. Mermaid diagram you can paste into a PR description

```powershell
Export-AzureEstate -DiagramOnly -Diagram Mermaid -OutputPath ./out
Get-Content (Get-ChildItem out -Directory)[-1].FullName/diagrams/estate.mmd | Set-Clipboard
```

## 4. Tenant-wide export to feed a customer hand-over

```powershell
Export-AzureEstate `
  -TenantId 11111111-1111-1111-1111-111111111111 `
  -ConfirmLargeExport `
  -ResourceLimit 10000 `
  -OutputPath ./handover

# Zip it up
Compress-Archive -Path ./handover/* -DestinationPath ./handover.zip
```

> ⚠️ The zip may contain confidential resource names, IDs and tags. Treat it as you would any other customer-shared artifact.
