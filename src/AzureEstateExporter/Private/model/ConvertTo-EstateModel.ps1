function ConvertTo-EstateModel {
    <#
    .SYNOPSIS
        Normalizes raw collector output into the estate model consumed by every renderer.
    .DESCRIPTION
        The output is a stable, sorted, ID-keyed structure with three top-level shapes:

          .Inventory  — flat list, one record per resource (the renderers' workhorse).
          .Graph      — { nodes, edges } describing inferred relationships.
          .Manifest   — deterministic mapping: azure_resource_id -> tf_address -> file.
                        Used to keep Terraform output stable across re-runs.

        Edge inference in v0.1 is heuristic (NIC -> VM via id matching, etc.); it is
        designed to be additive. New rules go in the `$edgeRules` block.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]]$ArgRows,

        [Parameter(Mandatory)]
        [pscustomobject]$ArmExtras
    )

    Write-EstateLog "Normalising $($ArgRows.Count) ARG row(s)" -Level Verbose

    # ----- Inventory ---------------------------------------------------------
    $inventory = $ArgRows |
        Sort-Object subscriptionId, resourceGroup, type, name |
        ForEach-Object {
            [pscustomobject]@{
                id             = $_.id
                name           = $_.name
                type           = $_.type
                kind           = $_.kind
                location       = $_.location
                resourceGroup  = $_.resourceGroup
                subscriptionId = $_.subscriptionId
                managedBy      = $_.managedBy
                tags           = $_.tags
                sku            = $_.sku
                identityType   = $_.identity.type
                properties     = $_.properties
            }
        }

    # ----- Graph -------------------------------------------------------------
    $nodes = $inventory | ForEach-Object {
        [pscustomobject]@{
            id    = $_.id
            label = $_.name
            type  = $_.type
            rg    = $_.resourceGroup
            sub   = $_.subscriptionId
        }
    }

    $edges = New-Object System.Collections.ArrayList
    $idSet = @{}
    foreach ($n in $nodes) { $idSet[$n.id.ToLower()] = $true }

    foreach ($row in $ArgRows) {
        # Heuristic 1: any property value that looks like a resource ID we know.
        # Walk shallow properties only to keep this O(n).
        $props = $row.properties
        if ($null -eq $props) { continue }
        $stack = New-Object System.Collections.Stack
        $stack.Push($props)
        while ($stack.Count -gt 0) {
            $cur = $stack.Pop()
            if ($null -eq $cur) { continue }
            if ($cur -is [string]) {
                if ($cur -like '/subscriptions/*' -and $idSet.ContainsKey($cur.ToLower()) -and $cur.ToLower() -ne $row.id.ToLower()) {
                    [void]$edges.Add([pscustomobject]@{
                        from = $row.id
                        to   = $cur
                        kind = 'reference'
                    })
                }
            }
            elseif ($cur -is [System.Collections.IDictionary]) {
                # Must come BEFORE IEnumerable: PowerShell's foreach treats
                # hashtables as a single item, which would loop forever.
                foreach ($v in $cur.Values) { $stack.Push($v) }
            }
            elseif ($cur -is [pscustomobject]) {
                foreach ($p in $cur.PSObject.Properties) { $stack.Push($p.Value) }
            }
            elseif ($cur -is [System.Collections.IEnumerable]) {
                foreach ($child in $cur) { $stack.Push($child) }
            }
        }
    }

    $graph = [pscustomobject]@{
        nodes = $nodes
        edges = $edges.ToArray() | Sort-Object from, to -Unique
    }

    # ----- Manifest ----------------------------------------------------------
    $manifest = $inventory | ForEach-Object {
        $safe = ($_.name -replace '[^A-Za-z0-9_]', '_').ToLower()
        $tfType = $_.type -replace '\..*/', '' -replace '/', '_'
        [pscustomobject]@{
            azureId   = $_.id
            tfAddress = "$tfType.$safe"
            rgFolder  = "terraform/$($_.subscriptionId)/$($_.resourceGroup)"
        }
    }

    return [pscustomobject]@{
        Inventory = $inventory
        Graph     = $graph
        Manifest  = $manifest
        Extras    = $ArmExtras
    }
}
