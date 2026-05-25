# Coverage matrix (v0.1)

Be honest with yourself and your customer about what this tool does today.

## Legend

- ✅ supported end-to-end (inventory + diagram + Terraform)
- 🟡 inventory + diagram only — Terraform partially supported by `aztfexport` or generated as `azapi_resource`
- 🔵 inventory only
- ❌ not in scope for v0.1

## Compute

| Area | Inventory | Diagram | Terraform | Notes |
|------|:---------:|:-------:|:---------:|------|
| Virtual Machines | ✅ | ✅ | ✅ | VM extensions exported via `aztfexport` when supported by the AzureRM provider. |
| Virtual Machine Scale Sets | ✅ | ✅ | 🟡 | Uniform mode well supported; Flex sometimes falls back to `azapi`. |
| AKS clusters | ✅ | 🟡 | 🟡 | Add-ons, node pools and the implicit node RG need manual review. |
| Azure Container Apps / Container Apps Environments | ✅ | 🟡 | 🟡 | Improving rapidly in `aztfexport`. |
| App Service / Function App | ✅ | ✅ | 🟡 | `appsettings` redacted by default; slot bindings need review. |

## Networking

| Area | Inventory | Diagram | Terraform | Notes |
|------|:---------:|:-------:|:---------:|------|
| VNet / Subnet / NSG / Route Table | ✅ | ✅ | ✅ | |
| Public IP, Load Balancer, App Gateway | ✅ | ✅ | ✅ | |
| Private Endpoint / Private DNS Zone link | ✅ | ✅ | 🟡 | DNS zone links exported, sometimes need provider re-format. |
| VPN / ExpressRoute Gateway | ✅ | ✅ | 🟡 | |

## Data

| Area | Inventory | Diagram | Terraform | Notes |
|------|:---------:|:-------:|:---------:|------|
| Storage Account | ✅ | ✅ | ✅ | Access keys redacted. |
| Azure SQL DB / Managed Instance | ✅ | ✅ | 🟡 | Connection strings redacted. |
| Cosmos DB | ✅ | ✅ | 🟡 | |
| Key Vault | ✅ | ✅ | 🟡 | Metadata only; **never** secret values. |

## Identity / Governance

| Area | Inventory | Diagram | Terraform | Notes |
|------|:---------:|:-------:|:---------:|------|
| Role assignments | 🔵 | — | ❌ | Inventoried into `extras`. |
| Resource locks | 🔵 | — | ❌ | |
| Policy assignments | 🔵 | — | ❌ | |
| Diagnostic settings | 🔵 | — | ❌ | Hook present, fan-out not enabled by default in v0.1. |
| Entra ID (users/groups/apps) | ❌ | ❌ | ❌ | Roadmap. |
| Management Groups | ❌ | ❌ | ❌ | Roadmap. |

## Cross-cutting

| Concern | Status | Notes |
|---------|:------:|------|
| Multi-subscription per tenant | ✅ | Use `-TenantId -ConfirmLargeExport`. |
| Multi-tenant in one run | ❌ | Run the tool once per tenant. |
| Cost / billing data | ❌ | Out of scope. Use [`azure-cost-cli`](https://github.com/mivano/azure-cost-cli). |
| Ansible playbook generation | ❌ | Roadmap. |

## Reporting gaps

If you find a resource type that's wrong above, please open an issue with:

1. The exact `type` string from `inventory.json`.
2. Which column (Inventory / Diagram / Terraform) is wrong.
3. Output of `aztfexport --version` if Terraform is involved.
