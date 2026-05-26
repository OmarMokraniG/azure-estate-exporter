function New-MarkdownReport {
    <#
    .SYNOPSIS
        Renders the normalized estate model into a single Markdown document.
    .DESCRIPTION
        Output is grouped subscription -> resource group -> resource type, with
        compact tables and inline Azure-portal links. Designed to be readable
        in a PR review and friendly to grep.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Model,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Azure Estate Report')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("_Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') by azure-estate-exporter._")
    [void]$sb.AppendLine()

    $byType = $Model.Inventory | Group-Object type | Sort-Object Count -Descending
    [void]$sb.AppendLine('## Summary')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("- Subscriptions: **$(($Model.Inventory | Select-Object -ExpandProperty subscriptionId -Unique).Count)**")
    [void]$sb.AppendLine("- Resource groups: **$(($Model.Inventory | Select-Object -ExpandProperty resourceGroup -Unique).Count)**")
    [void]$sb.AppendLine("- Resources: **$($Model.Inventory.Count)**")
    [void]$sb.AppendLine("- Distinct types: **$($byType.Count)**")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('### Top resource types')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Type | Count |')
    [void]$sb.AppendLine('|------|------:|')
    foreach ($g in $byType | Select-Object -First 15) {
        [void]$sb.AppendLine("| ``$($g.Name)`` | $($g.Count) |")
    }
    [void]$sb.AppendLine()

    foreach ($subGroup in $Model.Inventory | Group-Object subscriptionId | Sort-Object Name) {
        [void]$sb.AppendLine("## Subscription ``$($subGroup.Name)``")
        [void]$sb.AppendLine()

        foreach ($rgGroup in $subGroup.Group | Group-Object resourceGroup | Sort-Object Name) {
            [void]$sb.AppendLine("### Resource group ``$($rgGroup.Name)``")
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Name | Type | Location | Tags |')
            [void]$sb.AppendLine('|------|------|----------|------|')

            foreach ($r in $rgGroup.Group | Sort-Object type, name) {
                $portalUrl = "https://portal.azure.com/#@/resource$($r.id)"
                $tagText = ''
                if ($r.tags) {
                    $tagText = ($r.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
                }
                [void]$sb.AppendLine("| [``$($r.name)``]($portalUrl) | $($r.type) | $($r.location) | $tagText |")
            }
            [void]$sb.AppendLine()
        }
    }

    if ($Model.Extras.RoleAssignments.Count -gt 0) {
        [void]$sb.AppendLine('## Role assignments (sample, first 50)')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Principal | Role | Scope |')
        [void]$sb.AppendLine('|-----------|------|-------|')
        foreach ($ra in $Model.Extras.RoleAssignments | Select-Object -First 50) {
            [void]$sb.AppendLine("| $($ra.principalName) ($($ra.principalType)) | $($ra.roleDefinitionName) | $($ra.scope) |")
        }
        [void]$sb.AppendLine()
    }

    # ----- v0.4.0 customer-grade sections -----------------------------------

    if ($Model.Cost) {
        [void]$sb.AppendLine('## Cost (Cost Management — ' + $Model.Cost.Timeframe + ')')
        [void]$sb.AppendLine()
        $totalsLines = foreach ($t in $Model.Cost.Totals) { "- ``$($t.subscriptionId)``: **$($t.cost) $($t.currency)**" }
        if ($totalsLines) { foreach ($l in $totalsLines) { [void]$sb.AppendLine($l) }; [void]$sb.AppendLine() }
        if ($Model.Cost.ByService.Count -gt 0) {
            [void]$sb.AppendLine('### Top services')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Subscription | Service | Cost | Currency |')
            [void]$sb.AppendLine('|--------------|---------|-----:|----------|')
            foreach ($r in $Model.Cost.ByService | Sort-Object cost -Descending | Select-Object -First 15) {
                [void]$sb.AppendLine("| ``$($r.subscriptionId)`` | $($r.serviceName) | $($r.cost) | $($r.currency) |")
            }
            [void]$sb.AppendLine()
        }
        if ($Model.Cost.ByResourceGroup.Count -gt 0) {
            [void]$sb.AppendLine('### Top resource groups')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Subscription | RG | Cost | Currency |')
            [void]$sb.AppendLine('|--------------|----|-----:|----------|')
            foreach ($r in $Model.Cost.ByResourceGroup | Sort-Object cost -Descending | Select-Object -First 15) {
                [void]$sb.AppendLine("| ``$($r.subscriptionId)`` | ``$($r.resourceGroup)`` | $($r.cost) | $($r.currency) |")
            }
            [void]$sb.AppendLine()
        }
        $failed = @($Model.Cost.SubscriptionStatus | Where-Object { $_.status -ne 'ok' })
        if ($failed.Count -gt 0) {
            [void]$sb.AppendLine('> :warning: Cost data missing for some subscriptions:')
            foreach ($f in $failed) { [void]$sb.AppendLine("> - ``$($f.subscriptionId)``: $($f.status) — $($f.message)") }
            [void]$sb.AppendLine()
        }
    }

    if ($Model.Security) {
        [void]$sb.AppendLine('## Security (Microsoft Defender for Cloud)')
        [void]$sb.AppendLine()
        if ($Model.Security.SecureScores.Count -gt 0) {
            [void]$sb.AppendLine('### Secure score')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Subscription | Score | Max | % |')
            [void]$sb.AppendLine('|--------------|------:|----:|--:|')
            foreach ($s in $Model.Security.SecureScores) {
                [void]$sb.AppendLine("| ``$($s.subscriptionId)`` | $($s.score) | $($s.max) | $([math]::Round($s.percentage, 1)) |")
            }
            [void]$sb.AppendLine()
        }
        if ($Model.Security.Assessments.Count -gt 0) {
            [void]$sb.AppendLine('### Top unhealthy assessments')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Severity | Title | Resource |')
            [void]$sb.AppendLine('|----------|-------|----------|')
            foreach ($a in $Model.Security.Assessments | Select-Object -First 25) {
                $resName = if ($a.resourceId) { ($a.resourceId -split '/')[-1] } else { '_(subscription scope)_' }
                [void]$sb.AppendLine("| **$($a.severity)** | $($a.displayName) | ``$resName`` |")
            }
            [void]$sb.AppendLine()
        }
        $defNo = @($Model.Security.SubscriptionStatus | Where-Object { $_.status -in @('defender-disabled', 'unauthorized') })
        if ($defNo.Count -gt 0) {
            [void]$sb.AppendLine('> :warning: Defender for Cloud not available for:')
            foreach ($f in $defNo) { [void]$sb.AppendLine("> - ``$($f.subscriptionId)``: $($f.status) — $($f.message)") }
            [void]$sb.AppendLine()
        }
    }

    if ($Model.Policy -and $Model.Policy.Headline) {
        $h = $Model.Policy.Headline
        [void]$sb.AppendLine('## Policy compliance')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("- **$($h.compliancePercent)%** compliant — $($h.nonCompliantResources) non-compliant out of $($h.totalResources) policy states.")
        [void]$sb.AppendLine()
        if ($Model.Policy.ByAssignment.Count -gt 0) {
            [void]$sb.AppendLine('### Top failing assignments')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Assignment | Definition | Non-compliant |')
            [void]$sb.AppendLine('|------------|------------|--------------:|')
            foreach ($a in $Model.Policy.ByAssignment | Select-Object -First 15) {
                [void]$sb.AppendLine("| ``$($a.assignmentName)`` | ``$($a.policyDefinitionName)`` | $($a.nonCompliantCount) |")
            }
            [void]$sb.AppendLine()
        }
        if ($Model.Policy.Truncated) {
            [void]$sb.AppendLine('> :warning: Detailed findings were truncated to the configured cap. Re-run with a higher `MaxFindings` to see all rows.')
            [void]$sb.AppendLine()
        }
    }

    if ($Model.Exposure -and $Model.Exposure.Count -gt 0) {
        [void]$sb.AppendLine('## Public exposure findings')
        [void]$sb.AppendLine()
        $bySev = $Model.Exposure | Group-Object severity
        $sevLine = ($bySev | ForEach-Object { "**$($_.Name)**: $($_.Count)" }) -join '  ·  '
        [void]$sb.AppendLine($sevLine)
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Severity | Type | Resource | Evidence | Recommendation |')
        [void]$sb.AppendLine('|----------|------|----------|----------|----------------|')
        foreach ($f in $Model.Exposure | Select-Object -First 30) {
            $port = "https://portal.azure.com/#@/resource$($f.resourceId)"
            $ev = if ($f.evidence) { $f.evidence -replace '\|', '\|' } else { '' }
            [void]$sb.AppendLine("| **$($f.severity)** | $($f.type) | [``$($f.resourceName)``]($port) | $ev | $($f.recommendation) |")
        }
        [void]$sb.AppendLine()
    }

    if ($Model.Access) {
        if ($Model.Access.Findings -and $Model.Access.Findings.Count -gt 0) {
            [void]$sb.AppendLine('## Access (RBAC) findings')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Severity | Title | Recommendation |')
            [void]$sb.AppendLine('|----------|-------|----------------|')
            foreach ($f in $Model.Access.Findings) {
                [void]$sb.AppendLine("| **$($f.severity)** | $($f.title) | $($f.recommendation) |")
            }
            [void]$sb.AppendLine()
        }
        if ($Model.Access.ByPrincipal -and $Model.Access.ByPrincipal.Count -gt 0) {
            [void]$sb.AppendLine('### Top principals by assignment count')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Principal | Type | Assignments | Top severity |')
            [void]$sb.AppendLine('|-----------|------|------------:|--------------|')
            foreach ($p in $Model.Access.ByPrincipal | Select-Object -First 15) {
                $name = if ($p.principalName) { $p.principalName } else { $p.principalId }
                [void]$sb.AppendLine("| ``$name`` | $($p.principalType) | $($p.assignmentCount) | $($p.topSeverity) |")
            }
            [void]$sb.AppendLine()
        }
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write Markdown report')) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $sb.ToString() | Set-Content -Path $OutputPath -Encoding utf8
        Write-EstateLog "Markdown report -> $OutputPath" -Level Success
    }
}
