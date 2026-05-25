# Architecture

`azure-estate-exporter` is a small, opinionated PowerShell 7 module wrapped around three explicit layers:

```
            ┌─────────────────┐
  ARG  ───▶ │   Collectors    │ ───▶ raw JSON per area
  ARM  ───▶ └─────────────────┘
                    │
                    ▼
            ┌─────────────────┐
            │ Normalized      │ ───▶ inventory.json
            │ model           │ ───▶ graph.json (nodes + edges)
            │                 │ ───▶ manifest.json (id -> tf-address)
            └─────────────────┘
                    │
        ┌───────────┼─────────────┬──────────────┐
        ▼           ▼             ▼              ▼
 Markdown report  Mermaid    Excalidraw   aztfexport
                  diagram    diagram      (Terraform HCL)
```

## Why three layers

- **Collectors don't know about output.** Add a new ARM area → add a new collector. The Terraform exporter never has to know.
- **Renderers don't know about Azure.** They consume the normalized model. Replacing `aztfexport` with Terraformer one day is a single-file change.
- **The orchestrator is thin.** It resolves the scope, calls collectors, normalizes, runs renderers, and writes an index. ~150 lines.

## Collectors

| Collector | What it pulls | API |
|-----------|---------------|-----|
| `Invoke-ArgCollector` | Every resource visible to the caller (id, type, location, rg, sub, tags, sku, identity, kind, properties). | Azure Resource Graph (`az graph query`) |
| `Invoke-ArmCollector` | Role assignments, locks, policy assignments. | `az role assignment list`, `az lock list`, `az policy assignment list` |

Collectors are intentionally **best-effort**. Failures are accumulated in `errors.json`; they never abort the run.

## Normalized model

```
inventory.json   : flat array, one record per resource.
graph.json       : { nodes:[{id,label,type,rg,sub}], edges:[{from,to,kind}] }
manifest.json    : [{ azureId, tfAddress, rgFolder }]  — deterministic.
```

Edge inference in v0.1 is a single pass over `properties`: any string value that looks like a resource id we already know becomes an edge. This catches the obvious cases (NIC↔VM, Subnet↔NIC, Private Endpoint↔target) without per-type code. Future versions can add typed rules.

## Renderers

- **Markdown report**: sub → RG → table. Always safe to share after redaction.
- **Mermaid** (default): one `graph LR`, one `subgraph` per RG. Renders inline on GitHub.
- **Excalidraw**: minimal scene, grid layout per RG. Useful for slides. Skipped automatically when the estate has > 300 resources.
- **Terraform via `aztfexport`**: one `aztfexport resource-group --hcl-only` per RG. `--hcl-only` keeps the run side-effect-free (no Terraform state created). `-WithImport` opts into state generation.

## Redaction

Every renderer reads from a `safeModel` that has been passed through `Protect-SensitiveValue`. The redactor walks the JSON tree and replaces values whose **key** matches `(?i)(password|secret|connectionstring|clientsecret|key|sas|token|certificate|cert|pwd|apikey)` with `***REDACTED***`. `-NoRedact` bypasses it (with a console warning).

## Output layout

```
out/<timestamp>/
├── README.md          # human-readable index
├── inventory.json     # normalized inventory
├── graph.json         # nodes + edges
├── manifest.json      # azure-id -> tf-address
├── errors.json        # per-area failures
├── report/report.md
├── diagrams/estate.mmd
└── terraform/<sub>/<rg>/...
```

Re-runs land in a new timestamped folder. `manifest.json` keeps the Terraform address stable across runs, so a `diff` between two outputs only highlights real estate drift.
