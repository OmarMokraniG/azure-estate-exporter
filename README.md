# azure-estate-exporter

> Inventory, diagram and Terraform-baseline any Azure tenant or subscription — open-source, MIT-licensed.

`azure-estate-exporter` is a PowerShell 7 module that connects to an Azure tenant or subscription you can already read, and produces:

1. **An inventory** of every resource visible to your identity, as JSON and human-readable Markdown.
2. **Architecture diagrams** (Mermaid by default, Excalidraw on demand).
3. **A single-file HTML dashboard** you can email to a customer.
4. **A Terraform HCL baseline** of the existing infrastructure via [`aztfexport`](https://github.com/Azure/aztfexport), Microsoft's official Azure-to-Terraform exporter.
5. **A diff between any two runs** so you can use it as an ongoing audit log.

It is designed for Microsoft engineers, architects, partners and customers who need to **document, share, or reverse-engineer** an existing Azure estate quickly and reproducibly.

> ⚠️ **Scope honesty.** This tool produces a *documentation-oriented baseline*. The generated Terraform is **not** guaranteed to recreate your estate byte-for-byte — `aztfexport` does not support every resource type and some write-only properties are unrecoverable. See [`docs/coverage.md`](docs/coverage.md) for what works in v0.2.

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
├── index.html             # ⭐ self-contained HTML dashboard (Mermaid embedded)
├── inventory.json         # full normalized inventory
├── graph.json             # nodes + inferred edges (relation + sourceProperty)
├── manifest.json          # run metadata, collection confidence, per-resource SHA-256 hashes
├── errors.json            # any per-resource failures
├── report/
│   └── report.md          # human-friendly Markdown
├── diagrams/
│   ├── estate.mmd         # Mermaid (default)
│   └── estate.excalidraw  # Excalidraw (if -Diagram Excalidraw|Both)
└── terraform/
    └── <sub>/<rg-name>/   # one HCL folder per resource group
        ├── main.tf
        ├── providers.tf
        ├── tf-report.json # what was exported / unsupported, plus tool version
        └── ...
```

## Diff two runs

```powershell
Compare-AzureEstateRun -Previous out/2026-05-20T10-00-00 -Current out/2026-05-25T13-00-00
# writes out/2026-05-25T13-00-00/diff/changelog.{md,json}
```

Only the **property paths** that changed are emitted — values are never copied
across to avoid leaking what redaction was supposed to hide.

## Try without an Azure subscription

The [`samples/`](samples/) folder contains anonymized output you can use to test
renderers, write downstream tooling or demo the project offline.

## 🌐 Web UI (v0.3, preview)

Prefer clicking to scripting? The [`web/`](web/) folder contains a Vite + React
SPA that lets you sign in with Entra, browse subscriptions and resource groups,
and explore your estate visually:

- interactive **resource map** (React Flow + heuristic edges + Azure-style category icons)
- sortable, filterable **resource table** with a JSON side panel
- one-click **Terraform CLI handoff** that runs the PowerShell module locally

```powershell
# 1. Create your own Entra app registration (one-off, in your tenant)
pwsh -File scripts/create-app-reg.ps1

# 2. Configure the web app
cd web
cp .env.example .env.local
#    paste the printed appId into VITE_AZURE_CLIENT_ID

# 3. Run it
npm install
npm run dev
#    open http://localhost:5173
```

See [`web/README.md`](web/README.md) for deployment to Azure Static Web Apps and
notes on Microsoft's Azure architecture icons (we ship generic open-source
placeholders; the official icons are an opt-in download).

## Features (v0.2)

- ✅ **Resource Graph–based** discovery across one subscription or all subscriptions visible to your identity.
- ✅ **Self-contained HTML dashboard** with embedded Mermaid (works offline).
- ✅ **`Compare-AzureEstateRun`** turns the tool into an ongoing audit log.
- ✅ **Pluggable collectors**: ARG primary + supplementary ARM collectors for diagnostic settings, role assignments, locks (extension model — easy to add more).
- ✅ **Pluggable renderers**: Markdown report, Mermaid diagram, Excalidraw diagram, HTML dashboard, Terraform via `aztfexport`.
- ✅ **Rich edges**: every inferred edge carries a `relation` (e.g. `hosted-on`, `in-subnet`, `managed-by`) and the `sourceProperty` path it came from.
- ✅ **Collection confidence**: every `manifest.json` includes the tool versions used, the scope queried, and error counts by area.
- ✅ **Modes**: `-InventoryOnly`, `-DiagramOnly`, `-TerraformOnly`, plus `-WhatIf` for dry runs.
- ✅ **Secret redaction by default** for known-sensitive keys (`password`, `secret`, `connectionString`, `key`, `sas`, `token`, `certificate`). Disable with `-NoRedact` *(not recommended)*.
- ✅ **Deterministic output** with a `manifest.json` mapping resource IDs to Terraform addresses + SHA-256 hashes so re-runs produce stable diffs.
- ✅ **Failure-tolerant**: a single broken resource group does not abort the run.
- ✅ **Devcontainer / Codespaces** ready — see `.devcontainer/devcontainer.json`.

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
