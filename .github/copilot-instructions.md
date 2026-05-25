# Copilot instructions — azure-estate-exporter

## Project in one sentence

A PowerShell 7 module that reads any Azure tenant or subscription the caller can already see and produces an inventory, architecture diagrams and a Terraform HCL baseline.

## Architecture (don't regress)

Three explicit layers — keep them decoupled:

```
Collectors --> Normalized model --> Renderers / Exporters
(ARG, ARM)     (inventory.json,     (md, mermaid, excalidraw,
                graph.json,          terraform-via-aztfexport)
                manifest.json)
```

- A new gap in coverage is a **collector**, not a renderer.
- A new output format is a **renderer**, not a collector.
- The orchestrator (`Export-AzureEstate`) wires both ends; it should stay thin.

## Critical context (do not regress)

- **Shell out to `az` CLI**. Do NOT take a dependency on the `Az.*` PowerShell modules; they are heavy and painful on Linux/Mac.
- **Terraform export is `--hcl-only` by default**. `--hcl-only` does not touch local state. Importing into state is opt-in via `-WithImport`.
- **`aztfexport` may be missing**. The Terraform renderer must detect this and print install instructions, not crash.
- **Redaction is on by default**. The `-NoRedact` switch must print a warning.
- **Failure-tolerant**. One broken RG should never abort the whole run; errors go to `out/errors.json`.
- **Scope semantics**:
  - `-SubscriptionId` → one subscription
  - `-ResourceGroup` → one RG (requires `-SubscriptionId`)
  - `-TenantId -ConfirmLargeExport` → all subscriptions the caller can see (does **not** include Entra ID or management groups in v0.1)
- **No MCP at runtime.** MCP servers (`azure`, `microsoft-learn`, `github`, `excalidraw`) are dev-time aids only. Generated artifacts must work without them.

## Diagrams

- **Mermaid is the default renderer.** It auto-layouts cleanly even for 100+ nodes.
- **Excalidraw is secondary** — better for hand-edited slides, used per-RG for small RGs.
- Excalidraw files are written as plain `.excalidraw` JSON (it's just JSON). The Excalidraw MCP is a *dev* convenience to preview them; do not depend on it at runtime.

## Tooling and key commands

- **Build/test:** `Invoke-Pester ./tests`
- **Lint:** `Invoke-ScriptAnalyzer -Path src -Recurse`
- **Smoke run:** `Export-AzureEstate -SubscriptionId <id> -InventoryOnly -WhatIf`

## Conventions

- Public functions are `Verb-Noun`, have `[CmdletBinding(SupportsShouldProcess)]` where they touch the filesystem, and have comment-based help.
- Private helpers live under `Private/` and are dot-sourced by `AzureEstateExporter.psm1`.
- All filesystem writes go through helpers that respect `$PSCmdlet.ShouldProcess` and the redaction policy.
- New external tools (e.g. Terraformer) get a wrapper under `Private/renderers/` with a detection step and friendly error message.

## When extending

1. **New collector** → `Private/collectors/Invoke-<Name>Collector.ps1`, writes to `model/raw/<name>.json`, registered in `ConvertTo-EstateModel.ps1`.
2. **New renderer** → `Private/renderers/New-<Name>...ps1`, consumes the normalized model only, never raw ARG/ARM responses.
3. Update `docs/coverage.md` whenever you add or fix support for a resource type.
