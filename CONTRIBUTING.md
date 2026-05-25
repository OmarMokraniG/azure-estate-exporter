# Contributing to azure-estate-exporter

Thanks for considering a contribution! This project follows the standard fork → branch → PR flow.

## Ways to contribute

- **Bug reports** — file an [issue](../../issues/new?template=bug.md) with a minimal reproduction.
- **New collectors** — add an ARM collector under `src/AzureEstateExporter/Private/collectors/` to cover a gap left by Azure Resource Graph (RBAC, policies, diagnostic settings, …).
- **New renderers** — Mermaid C4, Graphviz DOT, draw.io, etc.
- **Provider support** — wrap an alternative Terraform exporter (e.g. Terraformer) as a renderer.
- **Docs & examples** — even fixing a typo helps.

## Development setup

```powershell
git clone https://github.com/OmarMokraniG/azure-estate-exporter.git
cd azure-estate-exporter
Import-Module ./src/AzureEstateExporter -Force
Invoke-Pester ./tests
```

## Style

- PowerShell 7+, cross-platform safe (no `cmdlet`-only-on-Windows constructs).
- Shell out to `az` instead of taking a dependency on the `Az.*` PowerShell modules.
- Public functions are `Verb-Noun` with proper `[CmdletBinding()]` and comment-based help.
- Private helpers go under `Private/` and are dot-sourced by the module.
- Run `Invoke-ScriptAnalyzer -Path src -Recurse` before sending a PR.

## Commit messages

Conventional commits preferred:

```
feat(collector): add policy assignment collector
fix(renderer): handle resource groups with > 200 nodes in mermaid
docs: clarify -ConfirmLargeExport semantics
```

## Code of Conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
