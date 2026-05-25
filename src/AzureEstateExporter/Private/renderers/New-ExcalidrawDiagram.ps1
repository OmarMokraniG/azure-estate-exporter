function New-ExcalidrawDiagram {
    <#
    .SYNOPSIS
        Renders the estate graph as a plain Excalidraw JSON document.
    .DESCRIPTION
        Excalidraw files are just JSON. We emit a minimal valid scene with
        one rectangle per resource and one arrow per graph edge, laid out
        in a simple grid grouped by resource group. The result can be
        opened directly at https://excalidraw.com (File -> Open) or edited
        through the Excalidraw MCP server during development.

        For very large estates this renderer is skipped automatically by
        the orchestrator (see -Diagram threshold in Export-AzureEstate).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Model,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $elements = New-Object System.Collections.ArrayList
    $idMap    = @{}

    $cellW = 220; $cellH = 90; $gap = 40
    $cols  = 4

    $rgGroups = $Model.Graph.nodes | Group-Object rg | Sort-Object Name
    $rgY = 0

    foreach ($rgGroup in $rgGroups) {
        $rgX = 0
        $rgRowCount = [Math]::Ceiling($rgGroup.Count / $cols)
        $rgWidth = $cols * ($cellW + $gap)
        $rgHeight = $rgRowCount * ($cellH + $gap) + 60

        $rgFrameId = [Guid]::NewGuid().ToString()
        [void]$elements.Add(@{
            id          = $rgFrameId
            type        = 'rectangle'
            x           = $rgX
            y           = $rgY
            width       = $rgWidth
            height      = $rgHeight
            strokeColor = '#1971c2'
            backgroundColor = '#e7f5ff'
            fillStyle   = 'hachure'
            strokeWidth = 2
            roughness   = 1
            label       = @{ text = "RG: $($rgGroup.Name)"; fontSize = 20 }
            seed        = (Get-Random)
        })

        $i = 0
        foreach ($n in $rgGroup.Group | Sort-Object type, label) {
            $col = $i % $cols
            $row = [Math]::Floor($i / $cols)
            $nx = $rgX + 20 + $col * ($cellW + $gap)
            $ny = $rgY + 50 + $row * ($cellH + $gap)

            $nid = [Guid]::NewGuid().ToString()
            $idMap[$n.id] = $nid

            $shortType = ($n.type -split '/')[-1]
            [void]$elements.Add(@{
                id          = $nid
                type        = 'rectangle'
                x           = $nx
                y           = $ny
                width       = $cellW
                height      = $cellH
                strokeColor = '#1e1e1e'
                backgroundColor = '#ffffff'
                fillStyle   = 'solid'
                strokeWidth = 1
                roughness   = 1
                label       = @{ text = "$($n.label)`n$shortType"; fontSize = 14 }
                seed        = (Get-Random)
            })
            $i++
        }

        $rgY += $rgHeight + 80
    }

    foreach ($e in $Model.Graph.edges) {
        if (-not $idMap.ContainsKey($e.from) -or -not $idMap.ContainsKey($e.to)) { continue }
        [void]$elements.Add(@{
            id          = [Guid]::NewGuid().ToString()
            type        = 'arrow'
            startBinding = @{ elementId = $idMap[$e.from] }
            endBinding   = @{ elementId = $idMap[$e.to] }
            strokeColor = '#868e96'
            strokeWidth = 1
            roughness   = 1
            seed        = (Get-Random)
            x = 0; y = 0; width = 0; height = 0
            points = @(@(0, 0), @(100, 0))
        })
    }

    $scene = [ordered]@{
        type        = 'excalidraw'
        version     = 2
        source      = 'azure-estate-exporter'
        elements    = $elements
        appState    = @{ viewBackgroundColor = '#ffffff'; gridSize = 20 }
        files       = @{}
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write Excalidraw diagram')) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        ($scene | ConvertTo-Json -Depth 32) | Set-Content -Path $OutputPath -Encoding utf8
        Write-EstateLog "Excalidraw diagram -> $OutputPath" -Level Success
    }
}
