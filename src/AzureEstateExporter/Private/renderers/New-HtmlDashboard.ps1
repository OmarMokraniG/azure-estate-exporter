function New-HtmlDashboard {
    <#
    .SYNOPSIS
        Renders a single self-contained HTML dashboard for the estate.
    .DESCRIPTION
        Produces `index.html` with:
          * Stat cards (sub count, RG count, resource count, edge count).
          * Sortable per-resource-group table (vanilla JS, no frameworks).
          * Embedded Mermaid diagram(s) per RG + a global one, rendered via
            mermaid.js (embedded inline by default so the file works offline).

        Design goals:
          - Single file you can email a customer.
          - No JS framework; no build step; no copy-paste from another tool.
          - Mermaid is embedded inline when available; otherwise falls back to
            jsDelivr CDN with a visible banner.

        Safe to call with redacted models — values are HTML-encoded.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Model,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    function ConvertTo-HtmlText([string]$s) {
        if ($null -eq $s) { return '' }
        return [System.Net.WebUtility]::HtmlEncode($s)
    }

    function Get-MermaidNodeId([string]$azureId) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($azureId.ToLowerInvariant())
        $sha   = [System.Security.Cryptography.SHA1]::Create()
        $hex   = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 10).ToLower()
        return "n_$hex"
    }

    $generatedAt  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
    $subCount     = ($Model.Inventory | Select-Object -ExpandProperty subscriptionId -Unique).Count
    $rgCount      = ($Model.Inventory | Select-Object -ExpandProperty resourceGroup -Unique).Count
    $resCount     = $Model.Inventory.Count
    $edgeCount    = @($Model.Graph.edges).Count
    $typeCount    = ($Model.Inventory | Select-Object -ExpandProperty type -Unique).Count

    # Try to inline mermaid.js for offline portability; fall back to CDN tag.
    $mermaidJs = $null
    try { $mermaidJs = Get-MermaidScript }
    catch { Write-Verbose "Get-MermaidScript failed: $($_.Exception.Message). Falling back to CDN." }
    if ($mermaidJs) {
        $mermaidTag = "<script>$mermaidJs</script>"
        $offlineBanner = ''
    } else {
        $mermaidTag = '<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>'
        $offlineBanner = '<div class="banner">Mermaid was loaded from CDN — internet required to view diagrams.</div>'
    }

    # Build one mermaid graph per RG. Same id-derivation scheme as New-MermaidDiagram
    # so anyone cross-referencing can match nodes between artifacts.
    $rgDiagrams = New-Object System.Collections.ArrayList
    foreach ($rgGroup in $Model.Graph.nodes | Group-Object rg | Sort-Object Name) {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('graph LR')
        $localIds = @{}
        foreach ($n in $rgGroup.Group | Sort-Object type, label) {
            $mid = Get-MermaidNodeId $n.id
            $localIds[$n.id] = $mid
            $shortType = ($n.type -split '/')[-1]
            $label = "$($n.label)\n[$shortType]"
            [void]$sb.AppendLine("  $mid[`"$label`"]")
        }
        # Edges only between nodes that exist in this RG to keep per-RG diagrams readable.
        foreach ($e in $Model.Graph.edges) {
            if (-not $localIds.ContainsKey($e.from) -or -not $localIds.ContainsKey($e.to)) { continue }
            $rel = if ($e.PSObject.Properties['relation']) { $e.relation } else { $e.kind }
            if ($rel -and $rel -ne 'references' -and $rel -ne 'reference') {
                $safeRel = ($rel -replace '\|', '/')
                [void]$sb.AppendLine("  $($localIds[$e.from]) -->|$safeRel| $($localIds[$e.to])")
            } else {
                [void]$sb.AppendLine("  $($localIds[$e.from]) --> $($localIds[$e.to])")
            }
        }
        [void]$rgDiagrams.Add([pscustomobject]@{ Rg = $rgGroup.Name; Mermaid = $sb.ToString() })
    }

    # Table rows: one per resource.
    $tableRows = New-Object System.Text.StringBuilder
    foreach ($r in $Model.Inventory | Sort-Object subscriptionId, resourceGroup, type, name) {
        $portalUrl = "https://portal.azure.com/#@/resource$($r.id)"
        $tagText = ''
        if ($r.tags) {
            $tagText = ($r.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
        }
        $row = "<tr>" +
               "<td>$(ConvertTo-HtmlText $r.subscriptionId)</td>" +
               "<td>$(ConvertTo-HtmlText $r.resourceGroup)</td>" +
               "<td><a href='$portalUrl' target='_blank' rel='noopener'>$(ConvertTo-HtmlText $r.name)</a></td>" +
               "<td><code>$(ConvertTo-HtmlText $r.type)</code></td>" +
               "<td>$(ConvertTo-HtmlText $r.location)</td>" +
               "<td>$(ConvertTo-HtmlText $tagText)</td>" +
               "</tr>"
        [void]$tableRows.AppendLine($row)
    }

    # Top-types card.
    $typeRows = New-Object System.Text.StringBuilder
    foreach ($g in $Model.Inventory | Group-Object type | Sort-Object Count -Descending | Select-Object -First 10) {
        [void]$typeRows.AppendLine("<tr><td><code>$(ConvertTo-HtmlText $g.Name)</code></td><td class='num'>$($g.Count)</td></tr>")
    }

    $diagramSections = New-Object System.Text.StringBuilder
    foreach ($d in $rgDiagrams) {
        $sectionId = 'rg-' + (($d.Rg -replace '[^A-Za-z0-9]', '-').ToLower())
        [void]$diagramSections.AppendLine("<section><h3 id='$sectionId'>RG: $(ConvertTo-HtmlText $d.Rg)</h3><pre class='mermaid'>$(ConvertTo-HtmlText $d.Mermaid)</pre></section>")
    }

    # Confidence card data, only render if orchestrator filled it in.
    $confidenceBlock = ''
    if ($Model.Manifest -and $Model.Manifest.collection) {
        $c = $Model.Manifest.collection
        $t = $Model.Manifest.tools
        $scope = $Model.Manifest.scope
        $errs = $Model.Manifest.errorsByArea
        $errBits = New-Object System.Text.StringBuilder
        if ($errs) {
            foreach ($p in $errs.PSObject.Properties) {
                [void]$errBits.Append("<span class='pill'>$(ConvertTo-HtmlText $p.Name): $($p.Value)</span> ")
            }
        }
        $confidenceBlock = @"
<section class="confidence">
  <h2>Collection confidence</h2>
  <table class="kv">
    <tr><th>Scope</th><td>$(ConvertTo-HtmlText ($scope.kind))</td></tr>
    <tr><th>Subscriptions queried</th><td>$(ConvertTo-HtmlText ([string]$c.subscriptionsQueried))</td></tr>
    <tr><th>Redaction</th><td>$(ConvertTo-HtmlText ([string]$c.redactionEnabled))</td></tr>
    <tr><th>az CLI</th><td>$(ConvertTo-HtmlText ($t.az))</td></tr>
    <tr><th>aztfexport</th><td>$(ConvertTo-HtmlText ($t.aztfexport))</td></tr>
    <tr><th>terraform</th><td>$(ConvertTo-HtmlText ($t.terraform))</td></tr>
    <tr><th>Errors by area</th><td>$($errBits.ToString())</td></tr>
  </table>
</section>
"@
    }

    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Azure Estate Dashboard</title>
<meta name="generator" content="azure-estate-exporter" />
<style>
  :root { --fg:#0b1020; --muted:#6a7388; --bg:#f7f9fc; --card:#ffffff; --accent:#0067c0; --border:#e3e8f0; }
  * { box-sizing: border-box; }
  body { font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; background:var(--bg); color:var(--fg); margin:0; }
  header { background:linear-gradient(120deg,#0067c0,#1ba1e2); color:#fff; padding:24px 32px; }
  header h1 { margin:0 0 4px 0; font-size:22px; }
  header .meta { font-size:12px; opacity:.85; }
  main { padding: 16px 32px 80px; max-width:1400px; margin:0 auto; }
  .banner { background:#fff4ce; border:1px solid #ffd66e; padding:8px 12px; border-radius:6px; margin:16px 0; font-size:13px; }
  .cards { display:grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap:12px; margin:16px 0 24px; }
  .card { background:var(--card); border:1px solid var(--border); border-radius:8px; padding:14px 16px; }
  .card .v { font-size:28px; font-weight:600; color:var(--accent); }
  .card .l { font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.05em; }
  section { background:var(--card); border:1px solid var(--border); border-radius:8px; padding:16px 20px; margin: 16px 0; }
  section h2 { margin:0 0 12px 0; font-size:16px; }
  section h3 { margin:18px 0 8px 0; font-size:14px; color:var(--muted); }
  table { width:100%; border-collapse: collapse; font-size:13px; }
  th, td { padding:6px 8px; border-bottom:1px solid var(--border); text-align:left; vertical-align:top; }
  th { background:#eef2f8; cursor:pointer; user-select:none; position:sticky; top:0; }
  th.sorted-asc::after { content:" \25B2"; color:var(--muted); }
  th.sorted-desc::after { content:" \25BC"; color:var(--muted); }
  td.num { text-align:right; font-variant-numeric: tabular-nums; }
  code { background:#eef2f8; padding:1px 4px; border-radius:4px; font-size:12px; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  .filter { margin:8px 0; display:flex; gap:8px; flex-wrap:wrap; }
  .filter input { flex:1; min-width:200px; padding:6px 8px; border:1px solid var(--border); border-radius:6px; }
  .pill { background:#eef2f8; border-radius:12px; padding:2px 8px; font-size:11px; }
  .mermaid { background:#fafbfc; padding:8px; border-radius:6px; overflow:auto; }
  .columns2 { display:grid; grid-template-columns: 1fr 1fr; gap:16px; }
  @media (max-width: 900px) { .columns2 { grid-template-columns: 1fr; } }
  footer { text-align:center; color:var(--muted); font-size:11px; padding:24px 0; }
</style>
$mermaidTag
</head>
<body>
<header>
  <h1>Azure Estate Dashboard</h1>
  <div class="meta">Generated $generatedAt &middot; <code>azure-estate-exporter</code></div>
</header>
<main>
  $offlineBanner
  <div class="cards">
    <div class="card"><div class="v">$subCount</div><div class="l">Subscriptions</div></div>
    <div class="card"><div class="v">$rgCount</div><div class="l">Resource groups</div></div>
    <div class="card"><div class="v">$resCount</div><div class="l">Resources</div></div>
    <div class="card"><div class="v">$typeCount</div><div class="l">Distinct types</div></div>
    <div class="card"><div class="v">$edgeCount</div><div class="l">Inferred edges</div></div>
  </div>

  $confidenceBlock

  <div class="columns2">
    <section>
      <h2>Top resource types</h2>
      <table><thead><tr><th>Type</th><th class="num">Count</th></tr></thead><tbody>
$($typeRows.ToString())
      </tbody></table>
    </section>
    <section>
      <h2>Companion artifacts</h2>
      <ul>
        <li><a href="report.md">report.md</a> — full Markdown report</li>
        <li><a href="inventory.json">inventory.json</a> — raw normalized inventory</li>
        <li><a href="graph.json">graph.json</a> — nodes + inferred edges</li>
        <li><a href="manifest.json">manifest.json</a> — stable per-resource hashes</li>
        <li><a href="terraform/">terraform/</a> — HCL baseline (if generated)</li>
        <li><a href="errors.json">errors.json</a> — collection errors (if any)</li>
      </ul>
    </section>
  </div>

  <section>
    <h2>Resources</h2>
    <div class="filter"><input id="q" placeholder="Filter by name, type, RG, location..." /></div>
    <div style="max-height:480px; overflow:auto;">
      <table id="resources">
        <thead>
          <tr>
            <th data-key="0">Subscription</th>
            <th data-key="1">Resource group</th>
            <th data-key="2">Name</th>
            <th data-key="3">Type</th>
            <th data-key="4">Location</th>
            <th data-key="5">Tags</th>
          </tr>
        </thead>
        <tbody>
$($tableRows.ToString())
        </tbody>
      </table>
    </div>
  </section>

  <section>
    <h2>Architecture diagrams</h2>
$($diagramSections.ToString())
  </section>
</main>
<footer>Built by <a href="https://github.com/OmarMokraniG/azure-estate-exporter" target="_blank" rel="noopener">azure-estate-exporter</a> &middot; MIT</footer>
<script>
  // Filter + sort: vanilla JS, no framework. Keeps the artifact a single file.
  (function () {
    var q = document.getElementById('q');
    var table = document.getElementById('resources');
    var tbody = table.querySelector('tbody');
    var rows = Array.prototype.slice.call(tbody.querySelectorAll('tr'));

    q.addEventListener('input', function () {
      var needle = q.value.toLowerCase();
      for (var i = 0; i < rows.length; i++) {
        rows[i].style.display = rows[i].textContent.toLowerCase().indexOf(needle) >= 0 ? '' : 'none';
      }
    });

    var headers = table.querySelectorAll('th');
    headers.forEach(function (h, idx) {
      h.addEventListener('click', function () {
        var asc = !h.classList.contains('sorted-asc');
        headers.forEach(function (x) { x.classList.remove('sorted-asc', 'sorted-desc'); });
        h.classList.toggle('sorted-asc', asc);
        h.classList.toggle('sorted-desc', !asc);
        var sorted = rows.slice().sort(function (a, b) {
          var av = a.cells[idx].textContent.trim().toLowerCase();
          var bv = b.cells[idx].textContent.trim().toLowerCase();
          if (av < bv) return asc ? -1 : 1;
          if (av > bv) return asc ? 1 : -1;
          return 0;
        });
        sorted.forEach(function (r) { tbody.appendChild(r); });
      });
    });

    if (typeof mermaid !== 'undefined') {
      mermaid.initialize({ startOnLoad: true, theme: 'default', securityLevel: 'loose', maxTextSize: 200000 });
    }
  })();
</script>
</body>
</html>
"@

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write HTML dashboard')) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $html | Set-Content -Path $OutputPath -Encoding utf8
        Write-EstateLog "HTML dashboard -> $OutputPath" -Level Success
    }
}
