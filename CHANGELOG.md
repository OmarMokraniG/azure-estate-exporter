# Changelog

All notable changes to `azure-estate-exporter` are documented here.
Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.5.0] — 2026-05-27

### Added

- **drawio (diagrams.net) diagram renderer** (`Private/renderers/New-DrawioDiagram.ps1`).
  Every run emits `diagrams/estate.drawio` with the diagrams.net Azure shape
  library (`mxgraph.azure.*`). Containers nest subscription → resource group →
  resources; labelled edges come from the same inferred graph the Mermaid
  renderer uses. Opens in **app.diagrams.net**, **VS Code Draw.io Integration**,
  or **Draw.io Desktop** without any extra install.
- **Per-resource cost** in the cost collector — `Invoke-CostCollector` now
  issues a second Cost Management query grouped by `ResourceId` (besides the
  existing RG + ServiceName one). Surfaces as `Model.Cost.ByResource` and
  `out/<timestamp>/cost.json`.
- **FinOps analyser** (`Private/analysis/Invoke-FinOpsAnalysis.ps1`) — 7 rules
  derived from inventory + cost, no extra Azure calls:
  1. Unattached managed disks
  2. Unattached Public IPs
  3. App Service plans with no hosted sites
  4. GRS/RAGRS storage on dev/test RGs
  5. Premium / Ultra disks under 256 GB (StandardSSD candidate)
  6. Oversized VMs (D/E/M-series ≥ 32 vCPU)
  7. Classic App Insights (no workspace) — migration recommendation
  Output: severity-graded findings + best-effort `estimatedMonthlySavings`
  + top spenders + service mix. Written to `out/<timestamp>/finops.json`.
- **FinOps section** added to the Markdown report and the HTML dashboard
  (headline KPI card with potential savings, top-spenders table, cost mix by
  service type, recommendations table).
- **Web app — Resources tab** rewritten with FinOps surface:
  - 4 KPI cards (Total MTD, Potential savings, Findings count, Top spender).
  - Recommendations list with severity pills and clickable resource links.
  - Cost mix by service type with inline bar gauge.
  - Top 10 spenders table.
  - New **Cost (MTD)** column in the resources table, sortable.
  - One Cost Management query per scope, 30 min staleTime.
- **Web app — Diagram tab** gets:
  - **Export as drawio** button — downloads `.drawio` XML built client-side
    by `web/src/lib/drawioGenerator.ts` (TS port of the PS renderer).
  - **Open diagrams.net ↗** link.
- 15 new tests (8 drawio + 7 FinOps).

### Changed

- `ConvertTo-EstateModel` now exposes a `FinOps` slot on the model (null
  when analysis is skipped or fails).

### Notes

- The FinOps analyser is honest about uncertainty — every `estimatedMonthlySavings`
  is a heuristic and the UI says so. The PowerShell module and the web app share
  the same rule set (the TS file is a port; both render identical findings for
  the same inputs).
- drawio shape library is the bundled `mxgraph.azure` set, which renders in
  diagrams.net without installing Microsoft's official icons.

## [0.4.1] — 2026-05-26

### Added

- **Web app Terraform tab now renders the full repo in-browser** — no longer
  just a copy-paste CLI handoff. From the SPA you get:
  - A file tree with `README.md`, `.gitignore`, `backend.tf.example`, and
    `infra/<rg>/{main.tf, provider.tf, variables.tf, terraform.tfvars.example,
    outputs.tf, README.md}` for every resource group in scope.
  - A live HCL viewer (line numbers + Copy button) showing the selected file.
  - **Download .zip** button — bundles the entire generated repo via JSZip
    so you can `unzip ; terraform init ; terraform plan` immediately.
  - Coverage banner: shows what % of resources have native HCL renderers.
- **Browser-side HCL generator** (`web/src/lib/terraformGenerator.ts`) covers
  the ~15 most common resource types (RG, Storage, VNet/Subnet, NIC, NSG,
  Public IP, Route Table, VM linux/windows, Managed Disk, Key Vault, Service
  Plan, App Service linux/windows, Log Analytics, App Insights). Unsupported
  types emit honest commented stubs that point users at the PowerShell module.
- The previous copy-paste CLI handoff is preserved behind a "Show CLI handoff"
  toggle — production-grade `aztfexport` flow stays one click away.
- **Vitest** added to the web project. `npm test` runs 13 tests covering the
  generator (sanitiser, file structure, HCL content, subnet ref resolution,
  unsupported-type stubs, idempotency vs real ARG inventory).
- Generator is **failure-tolerant** — a single mis-shaped ARG resource never
  breaks the whole repo; it gets an honest `# Renderer error on …` stub.

### Honesty

The in-browser repo is a fast **baseline**. The PowerShell module +
`aztfexport` remain the production path because they import resources into
Terraform state so `terraform plan` shows _No changes_. The web tab explicitly
links to that flow.

## [0.4.0] — 2026-05-26

### Added

- **Cost Management collector** (`Private/collectors/Invoke-CostCollector.ps1`)
  — one purposeful POST per subscription against
  `Microsoft.CostManagement/query`, grouped by `ResourceGroupName` +
  `ServiceName` over `MonthToDate`. Writes `out/<timestamp>/cost.json`.
- **Defender for Cloud collector** (`Invoke-SecurityCollector.ps1`) — pulls
  secure score and top unhealthy assessments per subscription. Tolerates
  Defender-disabled (404/410) and permissions errors gracefully and surfaces
  them as `subscriptionStatus` rows. Writes `out/<timestamp>/security.json`.
- **Policy compliance collector** (`Invoke-PolicyStateCollector.ps1`) — two
  ARG queries (`policyresources` for headlines + per-assignment counts) plus
  Policy Insights for detailed non-compliant findings (capped at
  `MaxFindings`, default 5000). Writes `out/<timestamp>/policy.json`.
- **Public-exposure analysis** (`Private/analysis/Invoke-ExposureAnalysis.ps1`)
  — pure model-time analysis (no Azure calls). Emits severity-graded findings
  for: NSG rules allowing 0.0.0.0/0 / `*` / `Internet` on management ports,
  Storage accounts with `publicNetworkAccess=Enabled` + public blob access,
  App Services without IP restrictions, Key Vaults with public + default-allow
  ACLs, and informational Public IP entries. Works even without Defender.
- **Access (RBAC) analysis** (`Invoke-AccessAnalysis.ps1`) — derives top
  privileged principals, orphaned assignments (deleted principals), and
  broad-scope findings (Owner / User Access Admin / Contributor at sub or RG
  level). Writes `out/<timestamp>/access.json`.
- **Markdown report** now has dedicated sections for Cost, Security, Policy
  compliance, Public exposure and Access (RBAC) findings.
- **HTML dashboard** gets new headline cards (cost total, secure score %,
  policy compliance %, exposure-findings count) plus sections for Cost,
  Security, Policy, Exposure and RBAC. Pills are colour-coded by severity.
- **`outputs.tf`** in every `terraform-repo/infra/<rg>/` folder — generated
  from `aztfexportResourceMapping.json` with meaningful names derived from
  each Azure resource. Lets other Terraform repos consume the IDs of the
  imported resources without reaching into the raw `res-N` naming.
- **`-SkipCost`, `-SkipSecurity`, `-SkipPolicy`** opt-out switches on
  `Export-AzureEstate` for restricted-permissions or cost-throttled runs.
- **PowerShell Gallery publish workflow** (`.github/workflows/release.yml`)
  triggered on `v*.*.*` tags. Validates the manifest with
  `Test-ModuleManifest` and publishes via `Publish-Module` when the
  `PSGALLERY_API_KEY` secret is set; safely skips otherwise.
- **10 new Pester tests** (`tests/Analysis.Tests.ps1`) covering both
  analysis functions with synthetic fixtures.

### Changed

- `ConvertTo-EstateModel` now exposes `Cost`, `Security`, `Policy`,
  `Exposure`, and `Access` slots on the normalised model. Each is null when
  the corresponding collector / analysis step is skipped or fails.
- `Export-AzureEstate` writes additional per-area JSON artifacts:
  `cost.json`, `security.json`, `policy.json`, `exposure.json`,
  `access.json`.

### Notes

- All new collectors are **best-effort**: any per-sub failure ends up in
  `errors.json` and the run proceeds.
- The exposure analyser is intentionally conservative — it does NOT replace
  Defender for Cloud, but gives you something actionable even on subs that
  cannot enable Defender (e.g. dev / pay-as-you-go).
- Cost Management API throttling: we deliberately use ONE grouped query per
  subscription rather than slicing by tag — avoids the per-tenant rate limit.

## [0.3.1] — 2026-05-26

### Added

- **Deployable Terraform repo** generated automatically alongside the raw
  `aztfexport` output. Each Azure run now writes a
  `out/<timestamp>/terraform-repo/` folder that is a self-contained git-ready
  baseline you can clone and run:
  - `infra/<rg>/` per resource group with `main.tf`, parameterised
    `provider.tf` (uses `var.subscription_id`), `variables.tf`,
    `terraform.tfvars.example`, `.terraform.lock.hcl`, and a
    **`bootstrap-import.ps1`** that idempotently runs `terraform import` for
    every resource so the first `terraform plan` shows _No changes_.
  - `imports.md` per RG with the raw `terraform import …` list for non-Windows
    users.
  - Root `README.md`, `.gitignore`, `backend.tf.example` (Azure Storage stub),
    and aggregated `docs/coverage.md` listing every resource `aztfexport`
    skipped.
- **`New-AzureEstateTerraformRepo`** public cmdlet — repackage any existing
  `out/<timestamp>/` folder into the new repo shape without re-running
  `aztfexport`. Supports `-InitGit`, `-Force`, `-WhatIf`.
- **`-NoTerraformRepo`** switch on `Export-AzureEstate` to opt out of the
  packaging step.
- Web UI **Terraform tab** rewritten with 4 numbered steps (install →
  export → deploy → re-package) and one-click copy buttons for each block.
- 14 new Pester tests covering the packager (`tests/TerraformRepo.Tests.ps1`)
  with fixture-based `aztfexport` output, including parser validation of the
  generated bootstrap script.

### Fixed

- `scripts/create-app-reg.ps1` — `az rest --body <inline JSON>` from Windows
  PowerShell stripped the `Content-Type` header so the SPA-platform PATCH
  silently failed. The script now writes the body to a temp file and uses
  `--body "@$path"`, which works on Windows / Linux / macOS.

### Notes

- The generated repo is a **baseline**, not a perfect clone. `aztfexport
  --hcl-only` does not capture secrets, data-plane contents, runtime config
  or unsupported resource types. The root README and `docs/coverage.md` make
  this explicit.
- `provider.tf` is parameterised through `var.subscription_id`, but ARM
  resource IDs embedded in `main.tf` (cross-RG Key Vault references, subnet
  IDs, etc.) are NOT rewritten. If you deploy to a different subscription,
  the root README surfaces a warning that lists every source-subscription
  GUID still present in the HCL.

## [0.3.0] — 2026-05-26

### Added

- **Web UI** (`web/`) — Vite + React + TypeScript SPA. Sign in with Entra,
  pick a tenant / subscription / resource group, see:
  - interactive resource map (React Flow + dagre + 33 hand-drawn open-source
    Azure category icons)
  - sortable, filterable resource table with a JSON side panel
  - Terraform CLI handoff (replaced in v0.3.1 by a full deployable repo)
- Azure Static Web Apps managed Function (`web/api/`) that proxies
  `/api/arm/*` to `https://management.azure.com/*` so the SPA can call ARM
  despite its missing CORS headers. Local dev uses a Vite proxy.
- `scripts/create-app-reg.ps1` — bring-your-own Entra app registration with
  the SPA platform + `Azure Service Management → user_impersonation` delegated
  permission.
- New CI workflow `.github/workflows/web.yml` (lint + build on Ubuntu).

## [0.2.0] — 2026-05-25

### Added

- Self-contained HTML dashboard (`index.html`) with embedded Mermaid.
- `Compare-AzureEstateRun` cmdlet — diff two runs and emit a `changelog.md` +
  `changelog.json`, surfacing only property paths that changed (no values, to
  preserve redaction).
- Regression test suite (`tests/Regression.Tests.ps1`) covering the ARG
  single-line KQL invariant, edge schema v2, and the IDict-before-iterable
  walker.
- Devcontainer with `az`, `terraform`, `aztfexport`, PowerShell 7 and Pester.

## [0.1.0] — initial release

- PowerShell 7 module with `Export-AzureEstate`.
- ARG primary collector + supplementary ARM collectors (diagnostic settings,
  role assignments, locks).
- Markdown report, Mermaid diagram, Excalidraw diagram.
- Terraform baseline via `aztfexport`.
- Secret redaction by default; `-NoRedact` switch warns.
- Failure-tolerant per-RG collection with `out/errors.json`.
