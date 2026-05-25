function Compare-AzureEstateRun {
    <#
    .SYNOPSIS
        Diffs two azure-estate-exporter runs (added / removed / modified resources).
    .DESCRIPTION
        Reads `manifest.json` and `inventory.json` from two previous runs and
        emits a structured changelog. The match key is the Azure resource ID
        and the change signal is the manifest-level SHA-256 hash, so renames
        of files or noisy timestamps don't generate diffs.

        For `modified` resources we list the property *paths* that changed
        (`propertiesChanged: ["location","sku.name",...]`). We do NOT include
        the values, on purpose:
          - Many runs are redacted; comparing values would be misleading.
          - Path-only diffs are usually what you want for an audit log.

        Outputs:
          * <OutputPath>/changelog.json  - machine-readable
          * <OutputPath>/changelog.md    - human-readable

    .PARAMETER Previous
        Path to the older run folder (must contain manifest.json + inventory.json).
    .PARAMETER Current
        Path to the newer run folder (must contain manifest.json + inventory.json).
    .PARAMETER OutputPath
        Folder to write changelog files into. Defaults to `<Current>/diff`.

    .EXAMPLE
        Compare-AzureEstateRun -Previous out/2026-05-25T14-00-00 -Current out/2026-05-25T16-00-00
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Previous,
        [Parameter(Mandatory)] [string]$Current,
        [string]$OutputPath
    )

    function Read-Run([string]$root) {
        $man = Get-Content -Raw (Join-Path $root 'manifest.json') -ErrorAction Stop | ConvertFrom-Json
        $inv = Get-Content -Raw (Join-Path $root 'inventory.json') -ErrorAction Stop | ConvertFrom-Json
        # v0.1 manifests are a bare array; v0.2 wraps under .resources. Normalize.
        $resources = if ($man -is [System.Array]) { $man } else { $man.resources }
        $h = @{}
        foreach ($r in $resources) { $h[$r.azureId.ToLower()] = $r }
        $i = @{}
        foreach ($r in $inv) { $i[$r.id.ToLower()] = $r }
        return [pscustomobject]@{ Manifest = $h; Inventory = $i }
    }

    function Get-PropertyPath([object]$value, [string]$prefix) {
        # Flatten an object/dict/list to "key.subkey[0].name = leaf" pairs.
        $out = @{}
        $stack = New-Object System.Collections.Stack
        $stack.Push([pscustomobject]@{ V = $value; P = $prefix })
        while ($stack.Count -gt 0) {
            $f = $stack.Pop()
            $v = $f.V; $p = $f.P
            if ($null -eq $v) { $out[$p] = '<null>'; continue }
            if ($v -is [System.Collections.IDictionary]) {
                foreach ($k in $v.Keys) { $stack.Push([pscustomobject]@{ V = $v[$k]; P = "$p.$k" }) }
            }
            elseif ($v -is [pscustomobject]) {
                foreach ($pp in $v.PSObject.Properties) { $stack.Push([pscustomobject]@{ V = $pp.Value; P = "$p.$($pp.Name)" }) }
            }
            elseif ($v -is [string]) {
                $out[$p] = $v
            }
            elseif ($v -is [System.Collections.IEnumerable]) {
                $i = 0
                foreach ($c in $v) { $stack.Push([pscustomobject]@{ V = $c; P = "$p[$i]" }); $i++ }
            }
            else {
                $out[$p] = "$v"
            }
        }
        return $out
    }

    if (-not (Test-Path $Previous)) { throw "Previous run folder not found: $Previous" }
    if (-not (Test-Path $Current))  { throw "Current run folder not found: $Current" }
    if (-not $OutputPath) { $OutputPath = Join-Path $Current 'diff' }
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

    $prev = Read-Run $Previous
    $curr = Read-Run $Current

    $added    = New-Object System.Collections.ArrayList
    $removed  = New-Object System.Collections.ArrayList
    $modified = New-Object System.Collections.ArrayList

    foreach ($k in $curr.Manifest.Keys) {
        if (-not $prev.Manifest.ContainsKey($k)) {
            [void]$added.Add([pscustomobject]@{ azureId = $curr.Manifest[$k].azureId })
            continue
        }
        $prevHash = $prev.Manifest[$k].hash
        $currHash = $curr.Manifest[$k].hash
        if ($prevHash -and $currHash -and ($prevHash -ne $currHash)) {
            $pPaths = Get-PropertyPath $prev.Inventory[$k] 'resource'
            $cPaths = Get-PropertyPath $curr.Inventory[$k] 'resource'
            $changed = New-Object System.Collections.ArrayList
            $allKeys = ($pPaths.Keys + $cPaths.Keys | Sort-Object -Unique)
            foreach ($pk in $allKeys) {
                if (($pPaths[$pk] -as [string]) -ne ($cPaths[$pk] -as [string])) {
                    [void]$changed.Add($pk)
                }
            }
            [void]$modified.Add([pscustomobject]@{
                azureId            = $curr.Manifest[$k].azureId
                propertiesChanged  = @($changed)
            })
        }
    }
    foreach ($k in $prev.Manifest.Keys) {
        if (-not $curr.Manifest.ContainsKey($k)) {
            [void]$removed.Add([pscustomobject]@{ azureId = $prev.Manifest[$k].azureId })
        }
    }

    $changelog = [pscustomobject]@{
        previous    = (Resolve-Path $Previous).Path
        current     = (Resolve-Path $Current).Path
        generatedAt = (Get-Date -Format 'o')
        summary     = [pscustomobject]@{
            added    = $added.Count
            removed  = $removed.Count
            modified = $modified.Count
        }
        added    = $added.ToArray()
        removed  = $removed.ToArray()
        modified = $modified.ToArray()
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write changelog')) {
        $changelog | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputPath 'changelog.json') -Encoding utf8

        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('# Estate changelog')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("Comparing **$Previous** -> **$Current**")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("- Added: **$($added.Count)**")
        [void]$sb.AppendLine("- Removed: **$($removed.Count)**")
        [void]$sb.AppendLine("- Modified: **$($modified.Count)**")
        [void]$sb.AppendLine()
        if ($added.Count -gt 0) {
            [void]$sb.AppendLine('## Added')
            foreach ($r in $added) { [void]$sb.AppendLine("- ``$($r.azureId)``") }
            [void]$sb.AppendLine()
        }
        if ($removed.Count -gt 0) {
            [void]$sb.AppendLine('## Removed')
            foreach ($r in $removed) { [void]$sb.AppendLine("- ``$($r.azureId)``") }
            [void]$sb.AppendLine()
        }
        if ($modified.Count -gt 0) {
            [void]$sb.AppendLine('## Modified')
            foreach ($r in $modified) {
                [void]$sb.AppendLine("- ``$($r.azureId)``")
                foreach ($p in $r.propertiesChanged) { [void]$sb.AppendLine("    - $p") }
            }
            [void]$sb.AppendLine()
        }
        $sb.ToString() | Set-Content (Join-Path $OutputPath 'changelog.md') -Encoding utf8

        Write-EstateLog "Changelog -> $OutputPath" -Level Success
    }

    return $changelog
}
