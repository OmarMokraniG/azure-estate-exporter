# azure-estate-exporter

> Inventory, diagram and Terraform-baseline any Azure tenant or subscription — open-source, MIT-licensed.

`azure-estate-exporter` is a PowerShell 7 module that connects to an Azure tenant or subscription you can already read, and produces:

1. **An inventory** of every resource visible to your identity, as JSON and human-readable Markdown.
2. **Architecture diagrams** (Mermaid by default, Excalidraw on demand).
3. **A Terraform HCL baseline** of the existing infrastructure via [`aztfexport`](https://github.com/Azure/aztfexport), Microsoft's official Azure-to-Terraform exporter.

It is designed for Microsoft engineers, architects, partners and customers who need to **document, share, or reverse-engineer** an existing Azure estate quickly and reproducibly.

> ⚠️ **Scope honesty.** This tool produces a *documentation-oriented baseline*. The generated Terraform is **not** guaranteed to recreate your estate byte-for-byte — `aztfexport` does not support every resource type and some write-only properties are unrecoverable. See [`docs/coverage.md`](docs/coverage.md) for what works in v0.1.

---

## Quickstart

```powershell
# 1. Prerequisites — see docs/installation.md for full list
#    - PowerShell 7+
#    - Azure CLI 2.60+ (`az login` already done)
#    - Terraform 1.5+
#    - aztfexport (optional, only needed for Terraform export)
#        winget install Microsoft.Azure.aztfexport
#        # or:  go install github.com/Azure/aztfexport@latest

# 2. Clone and import
git clone https://github.com/OmarMokraniG/azure-estate-exporter.git
cd azure-estate-exporter
Import-Module ./src/AzureEstateExporter

# 3. Run against the currently selected subscription
Export-AzureEstate -OutputPath ./out

# 4. Or target a specific scope
Export-AzureEstate -SubscriptionId <guid> -ResourceGroup my-rg

# 5. Discovery-only (cheap, no Terraform export)
Export-AzureEstate -SubscriptionId <guid> -InventoryOnly
```

Outputs land in `./out/<timestamp>/`:

```
out/2026-05-25T13-00-00/
├── README.md              # index of everything produced
├── inventory.json         # full normalized inventory
├── manifest.json          # stable resource-id -> tf-address map
├── errors.json            # any per-resource failures
├── report/
│   └── report.md          # human-friendly Markdown
├── diagrams/
│   ├── estate.mmd         # Mermaid (default)
│   └── estate.excalidraw  # Excalidraw (if -Diagram Excalidraw|Both)
└── terraform/
    └── <rg-name>/         # one HCL folder per resource group
        ├── main.tf
        ├── providers.tf
        └── ...
```

## Features (v0.1)

- ✅ **Resource Graph–based** discovery across one subscription or all subscriptions visible to your identity.
- ✅ **Pluggable collectors**: ARG primary + supplementary ARM collectors for diagnostic settings, role assignments, locks (extension model — easy to add more).
- ✅ **Pluggable renderers**: Markdown report, Mermaid diagram, Excalidraw diagram, Terraform via `aztfexport`.
- ✅ **Modes**: `-InventoryOnly`, `-DiagramOnly`, `-TerraformOnly`, plus `-WhatIf` for dry runs.
- ✅ **Secret redaction by default** for known-sensitive keys (`password`, `secret`, `connectionString`, `key`, `sas`, `token`, `certificate`). Disable with `-NoRedact` *(not recommended)*.
- ✅ **Deterministic output** with a `manifest.json` mapping resource IDs to Terraform addresses so re-runs produce stable diffs.
- ✅ **Failure-tolerant**: a single broken resource group does not abort the run.
- ✅ **Preflight summary**: before any expensive work, prints how many subs / RGs / resources will be touched and (for very large scopes) requires `-ConfirmLargeExport`.

## What is NOT in scope (yet)

See [`docs/coverage.md`](docs/coverage.md). High-level:

- **Entra ID** / Azure AD objects — not exported.
- **Management Groups** & subscription/policy hierarchy — not exported.
- **Ansible** playbooks for in-VM configuration — roadmap.
- **Cost/billing data** beyond budgets metadata — out of scope.
- **Resource types unsupported by `aztfexport`** — listed in coverage doc.

## Why this exists

The classic problem: a customer has an Azure subscription nobody owns the IaC for. To migrate it, document it, or hand it over, you need:

- An accurate inventory you can trust.
- A picture you can put in a deck.
- Terraform you can start iterating on rather than writing from scratch.

Doing this by hand for a non-trivial estate takes days. This tool gets you to a solid baseline in minutes, then lets a human review and harden the result.

## Security

Read [`SECURITY.md`](SECURITY.md). TL;DR:

- The tool needs **Reader** at minimum on the scope you target.
- Generated artifacts may include resource metadata that some organisations treat as confidential — **review before sharing or pushing to public repos**. The default `.gitignore` already excludes `out/`.
- Never commit `terraform.tfstate*`, `*.tfvars`, or unredacted exports.

## Contributing

PRs welcome — especially new collectors and renderers. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Related work

- [`Azure/aztfexport`](https://github.com/Azure/aztfexport) — the official Azure-to-Terraform exporter that powers our Terraform backend.
- [Azure Resource Graph](https://learn.microsoft.com/azure/governance/resource-graph/) — primary inventory engine.
- [Excalidraw](https://excalidraw.com/) — diagrams.
- [Terraformer](https://github.com/GoogleCloudPlatform/terraformer) — alternative exporter; could be plugged in as a future backend.

## License

[MIT](LICENSE).
