# Changelog

All notable changes to `azure-estate-exporter` are documented here.
Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
