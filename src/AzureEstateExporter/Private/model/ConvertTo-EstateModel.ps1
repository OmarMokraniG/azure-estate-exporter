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

    # Edge inference v0.2:
    #   - schema: { from, to, relation, sourceProperty, kind }
    #     `kind` is kept for v0.1 back-compat; renderers should prefer `relation`.
    #   - heuristics applied:
    #       1. managedBy: a managed resource points at its manager.
    #       2. any string property value that is itself a resource ID we know.
    #   - we DO NOT claim semantic relationships we cannot infer cheaply; the
    #     property path (sourceProperty) is recorded so consumers can interpret.

    function Get-RelationFromPath([string]$path) {
        # Heuristic mapping from common Azure property paths to human-readable labels.
        # Kept intentionally small; renderers fall back to "references" when no rule matches.
        $rules = @(
            @{ Pattern = 'serverFarmId$';                 Relation = 'hosted-on' }
            @{ Pattern = 'storageAccount';                Relation = 'uses-storage' }
            @{ Pattern = 'keyVault';                      Relation = 'uses-key-vault' }
            @{ Pattern = 'subnet\b|subnet\.id';           Relation = 'in-subnet' }
            @{ Pattern = 'networkSecurityGroup';          Relation = 'protected-by' }
            @{ Pattern = 'privateLinkServiceId';          Relation = 'private-endpoint-to' }
            @{ Pattern = 'virtualNetwork\b';              Relation = 'in-vnet' }
            @{ Pattern = 'remoteVirtualNetwork';          Relation = 'peered-with' }
            @{ Pattern = 'workspaceResourceId|workspaceId$'; Relation = 'logs-to' }
            @{ Pattern = 'sourceId|sourceResource';       Relation = 'sourced-from' }
        )
        foreach ($r in $rules) {
            if ($path -match $r.Pattern) { return $r.Relation }
        }
        return 'references'
    }

    foreach ($row in $ArgRows) {
        # Heuristic 1: managedBy field at the top level.
        if ($row.managedBy -and $row.managedBy -like '/subscriptions/*' `
            -and $idSet.ContainsKey($row.managedBy.ToLower()) `
            -and $row.managedBy.ToLower() -ne $row.id.ToLower()) {
            [void]$edges.Add([pscustomobject]@{
                from           = $row.id
                to             = $row.managedBy
                relation       = 'managed-by'
                sourceProperty = 'managedBy'
                kind           = 'reference'
            })
        }

        # Heuristic 2: walk properties; any string that is itself a known resource id is an edge.
        $props = $row.properties
        if ($null -eq $props) { continue }
        $stack = New-Object System.Collections.Stack
        # Each stack frame is a [pscustomobject]@{ Value; Path }
        $stack.Push([pscustomobject]@{ Value = $props; Path = 'properties' })
        while ($stack.Count -gt 0) {
            $frame = $stack.Pop()
            $cur = $frame.Value
            $path = $frame.Path
            if ($null -eq $cur) { continue }
            if ($cur -is [string]) {
                if ($cur -like '/subscriptions/*' `
                    -and $idSet.ContainsKey($cur.ToLower()) `
                    -and $cur.ToLower() -ne $row.id.ToLower()) {
                    [void]$edges.Add([pscustomobject]@{
                        from           = $row.id
                        to             = $cur
                        relation       = (Get-RelationFromPath $path)
                        sourceProperty = $path
                        kind           = 'reference'
                    })
                }
            }
            elseif ($cur -is [System.Collections.IDictionary]) {
                # MUST come before IEnumerable: PowerShell's foreach treats
                # IDictionary as a single item, which would loop forever.
                foreach ($k in $cur.Keys) { $stack.Push([pscustomobject]@{ Value = $cur[$k]; Path = "$path.$k" }) }
            }
            elseif ($cur -is [pscustomobject]) {
                foreach ($p in $cur.PSObject.Properties) { $stack.Push([pscustomobject]@{ Value = $p.Value; Path = "$path.$($p.Name)" }) }
            }
            elseif ($cur -is [System.Collections.IEnumerable]) {
                $i = 0
                foreach ($child in $cur) {
                    $stack.Push([pscustomobject]@{ Value = $child; Path = "$path[$i]" })
                    $i++
                }
            }
        }
    }

    $graph = [pscustomobject]@{
        nodes = $nodes
        # Deduplicate by from+to+relation (we may have multiple property paths pointing the same way).
        edges = $edges.ToArray() | Sort-Object from, to, relation, sourceProperty -Unique
    }

    # ----- Manifest (per-resource entries; orchestrator augments with meta) ----
    # Stable per-resource hash so Compare-AzureEstateRun can detect modifications
    # across runs even when output ordering or noise fields change.
    $manifestResources = $inventory | ForEach-Object {
        $safe = ($_.name -replace '[^A-Za-z0-9_]', '_').ToLower()
        $tfType = $_.type -replace '\..*/', '' -replace '/', '_'

        # Canonicalize: strip transient/redacted fields, sort keys via ConvertTo-Json.
        # We deliberately exclude `properties` from the hash to avoid noisy diffs on
        # benign timestamps; `properties` changes surface as propertiesChanged paths
        # computed at compare time instead.
        $canonical = [pscustomobject]@{
            id             = $_.id.ToLower()
            type           = $_.type.ToLower()
            kind           = $_.kind
            location       = $_.location
            resourceGroup  = $_.resourceGroup
            subscriptionId = $_.subscriptionId
            sku            = $_.sku
            identityType   = $_.identityType
            tags           = $_.tags
        }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($canonical | ConvertTo-Json -Depth 8 -Compress))
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hash = 'sha256:' + ([BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace '-', '').ToLower()

        [pscustomobject]@{
            azureId   = $_.id
            tfAddress = "$tfType.$safe"
            rgFolder  = "terraform/$($_.subscriptionId)/$($_.resourceGroup)"
            hash      = $hash
        }
    }

    return [pscustomobject]@{
        Inventory = $inventory
        Graph     = $graph
        Manifest  = [pscustomobject]@{
            # `meta`, `scope`, `tools`, `errorsByArea` are filled by Export-AzureEstate
            # since they are scope/run concerns, not model concerns.
            generator     = $null
            scope         = $null
            collection    = $null
            tools         = $null
            errorsByArea  = $null
            resources     = $manifestResources
        }
        Extras    = $ArmExtras
        # v0.4.0 — customer-grade sections, populated by Export-AzureEstate after
        # the collectors / analysis steps have run.
        Cost      = $null
        Security  = $null
        Policy    = $null
        Exposure  = @()
        Access    = $null
    }
}
