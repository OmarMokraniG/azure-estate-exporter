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

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write Markdown report')) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $sb.ToString() | Set-Content -Path $OutputPath -Encoding utf8
        Write-EstateLog "Markdown report -> $OutputPath" -Level Success
    }
}
