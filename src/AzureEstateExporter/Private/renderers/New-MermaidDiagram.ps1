function New-MermaidDiagram {
    <#
    .SYNOPSIS
        Renders the estate graph as a Mermaid `graph LR` document.
    .DESCRIPTION
        Default renderer. Mermaid auto-layouts for free and handles a few
        hundred nodes well. For very large estates we still output a single
        file, but group nodes into one `subgraph` per resource group so
        viewers can collapse them.

        Edges come from the normalized graph; node IDs are sanitised so
        Mermaid accepts them.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Model,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # Deterministic Mermaid node id derived from the Azure resource id.
    function Get-MermaidId([string]$azureId) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($azureId.ToLowerInvariant())
        $sha   = [System.Security.Cryptography.SHA1]::Create()
        $hex   = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 10).ToLower()
        return "n_$hex"
    }

    $idMap = @{}

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('```mermaid')
    [void]$sb.AppendLine('graph LR')

    foreach ($rgGroup in $Model.Graph.nodes | Group-Object rg | Sort-Object Name) {
        $rgId = ('rg_' + ($rgGroup.Name -replace '[^A-Za-z0-9]', '_'))
        [void]$sb.AppendLine("  subgraph $rgId[`"RG: $($rgGroup.Name)`"]")
        foreach ($n in $rgGroup.Group | Sort-Object type, label) {
            $mid = Get-MermaidId $n.id
            $idMap[$n.id] = $mid
            $shortType = ($n.type -split '/')[-1]
            $label = "$($n.label)\n[$shortType]"
            [void]$sb.AppendLine("    $mid[`"$label`"]")
        }
        [void]$sb.AppendLine('  end')
    }

    foreach ($e in $Model.Graph.edges) {
        if (-not $idMap.ContainsKey($e.from) -or -not $idMap.ContainsKey($e.to)) { continue }
        # Prefer the v0.2 `relation` field; fall back to v0.1's `kind` for older inputs.
        $rel = if ($e.PSObject.Properties['relation']) { $e.relation } else { $e.kind }
        if ($rel -and $rel -ne 'reference' -and $rel -ne 'references') {
            # Escape pipe character which is significant in Mermaid edge labels.
            $safeRel = ($rel -replace '\|', '/')
            [void]$sb.AppendLine("  $($idMap[$e.from]) -->|$safeRel| $($idMap[$e.to])")
        } else {
            [void]$sb.AppendLine("  $($idMap[$e.from]) --> $($idMap[$e.to])")
        }
    }

    [void]$sb.AppendLine('```')

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write Mermaid diagram')) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $sb.ToString() | Set-Content -Path $OutputPath -Encoding utf8
        Write-EstateLog "Mermaid diagram -> $OutputPath" -Level Success
    }
}
