# Sample artifacts

These files are **fully anonymized** examples of what an
`azure-estate-exporter` run produces. They reference fake subscription
GUIDs (all zeros) and fictional Contoso resources so you can:

- See the JSON shapes before running anything against Azure.
- Test a new renderer or downstream tool offline.
- Demo the project to a customer without sharing real data.

## Files

| File | What it is |
|------|------------|
| [`inventory.json`](inventory.json) | Per-resource normalized inventory. |
| [`graph.json`](graph.json) | Nodes + inferred edges (with `relation` + `sourceProperty`). |
| [`manifest.json`](manifest.json) | Run metadata + collection confidence + per-resource SHA-256 hash. |
| [`changelog.md`](changelog.md) | Example output of `Compare-AzureEstateRun`. |

## Try the diff offline

```powershell
Import-Module ./src/AzureEstateExporter
$prev = New-Item -ItemType Directory -Force ./out/sample-prev
$curr = New-Item -ItemType Directory -Force ./out/sample-curr

Copy-Item samples\*.json $prev.FullName
Copy-Item samples\*.json $curr.FullName

# Tweak a hash to simulate a modification...
(Get-Content $curr/manifest.json) -replace '0000000000000000000000000000000000000000000000000000000000000001','0000000000000000000000000000000000000000000000000000000000000099' |
    Set-Content $curr/manifest.json

Compare-AzureEstateRun -Previous $prev.FullName -Current $curr.FullName
```
