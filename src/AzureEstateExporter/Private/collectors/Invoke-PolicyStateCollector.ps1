function Invoke-PolicyStateCollector {
    <#
    .SYNOPSIS
        Collects Azure Policy compliance state, both as aggregated headlines
        and as top non-compliant findings.

    .DESCRIPTION
        Two queries per scope:

          1. Headline counts from Resource Graph `policyresources` table.
             Cheap, ARG-paginated. Gives the dashboard a one-line
             "X out of Y resources non-compliant".

          2. Detailed non-compliant findings via the Policy Insights API,
             filtered to `complianceState eq 'NonCompliant'`. Capped at
             `MaxFindings` rows total across all subscriptions to avoid
             blowing up the report on big estates.

        Both queries are best-effort: per-sub failures are appended to
        `Errors` and the collector keeps going.

    .PARAMETER SubscriptionIds
        Subscriptions to query.

    .PARAMETER Errors
        Failure ArrayList. Caller owns it.

    .PARAMETER MaxFindings
        Hard ceiling on detailed non-compliant findings. Default 5000.

    .OUTPUTS
        [pscustomobject] with members:
          .Headline          — { totalResources, nonCompliantResources, compliancePercent }
          .ByAssignment      — { assignmentName, policyDefinitionName, nonCompliantCount }
          .NonCompliant      — { resourceId, policyAssignmentName, policyDefinitionName, complianceState, subscriptionId }
          .Truncated         — bool, set to true when MaxFindings was hit
          .SubscriptionStatus— { subscriptionId, status, message }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$SubscriptionIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Errors,

        [int]$MaxFindings = 5000
    )

    $result = [pscustomobject]@{
        Headline           = $null
        ByAssignment       = New-Object System.Collections.ArrayList
        NonCompliant       = New-Object System.Collections.ArrayList
        Truncated          = $false
        SubscriptionStatus = New-Object System.Collections.ArrayList
    }

    # --- 1. Headline counts via ARG -----------------------------------------
    # ARG MUST be single-line on Windows (cmd.exe truncates at LF).
    $kqlHeadline = @(
        'policyresources',
        "where type =~ 'microsoft.policyinsights/policystates'",
        "summarize total=count(), nonCompliant=countif(properties.complianceState =~ 'NonCompliant') by subscriptionId"
    ) -join ' | '

    $argv = @('graph', 'query', '--graph-query', $kqlHeadline, '--output', 'json')
    foreach ($s in $SubscriptionIds) { $argv += @('--subscriptions', $s) }

    try {
        $raw = & az @argv 2>&1
        if ($LASTEXITCODE -ne 0) { throw "az graph query (policy headline) failed: $raw" }
        $resp = $raw | ConvertFrom-Json -Depth 16
        $totalAll  = 0
        $ncAll     = 0
        foreach ($row in @($resp.data)) {
            $totalAll += [int]$row.total
            $ncAll    += [int]$row.nonCompliant
        }
        $compliancePct = if ($totalAll -gt 0) { [math]::Round(100 * (1 - $ncAll / $totalAll), 1) } else { $null }
        $result.Headline = [pscustomobject]@{
            totalResources         = $totalAll
            nonCompliantResources  = $ncAll
            compliancePercent      = $compliancePct
        }
    }
    catch {
        [void]$Errors.Add([pscustomobject]@{
            area = 'policyHeadline'; scope = '*'; error = $_.Exception.Message
        })
    }

    # --- 2. By-assignment aggregation (also ARG) ----------------------------
    $kqlByAssignment = @(
        'policyresources',
        "where type =~ 'microsoft.policyinsights/policystates'",
        "where properties.complianceState =~ 'NonCompliant'",
        'summarize nonCompliantCount=count() by tostring(properties.policyAssignmentName), tostring(properties.policyDefinitionName)',
        'order by nonCompliantCount desc'
    ) -join ' | '

    $argv = @('graph', 'query', '--graph-query', $kqlByAssignment, '--first', '100', '--output', 'json')
    foreach ($s in $SubscriptionIds) { $argv += @('--subscriptions', $s) }

    try {
        $raw = & az @argv 2>&1
        if ($LASTEXITCODE -ne 0) { throw "az graph query (by assignment) failed: $raw" }
        $resp = $raw | ConvertFrom-Json -Depth 16
        foreach ($row in @($resp.data)) {
            [void]$result.ByAssignment.Add([pscustomobject]@{
                assignmentName       = $row.properties_policyAssignmentName
                policyDefinitionName = $row.properties_policyDefinitionName
                nonCompliantCount    = [int]$row.nonCompliantCount
            })
        }
    }
    catch {
        [void]$Errors.Add([pscustomobject]@{
            area = 'policyByAssignment'; scope = '*'; error = $_.Exception.Message
        })
    }

    # --- 3. Detailed non-compliant findings (Policy Insights REST) ----------
    foreach ($sub in $SubscriptionIds) {
        if ($result.NonCompliant.Count -ge $MaxFindings) {
            $result.Truncated = $true
            break
        }
        $remaining = $MaxFindings - $result.NonCompliant.Count
        $uri = "/subscriptions/$sub/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults?api-version=2019-10-01&`$filter=complianceState eq 'NonCompliant'&`$top=$remaining"
        try {
            $raw = & az rest --method post --uri $uri --headers 'Content-Type=application/json' 2>&1
            if ($LASTEXITCODE -ne 0) {
                $msg = ($raw | Out-String).Trim()
                $status = if ($msg -match '\b(401|403|Forbidden|Unauthorized)\b') { 'unauthorized' } else { 'error' }
                [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                    subscriptionId = $sub; status = $status; message = $msg.Substring(0, [Math]::Min(500, $msg.Length))
                })
                [void]$Errors.Add([pscustomobject]@{
                    area = 'policyInsights'; scope = "/subscriptions/$sub"
                    error = $msg.Substring(0, [Math]::Min(500, $msg.Length))
                })
                continue
            }
            $resp = $raw | ConvertFrom-Json -Depth 32
            foreach ($row in @($resp.value)) {
                if ($result.NonCompliant.Count -ge $MaxFindings) {
                    $result.Truncated = $true
                    break
                }
                [void]$result.NonCompliant.Add([pscustomobject]@{
                    resourceId           = $row.resourceId
                    policyAssignmentName = $row.policyAssignmentName
                    policyDefinitionName = $row.policyDefinitionName
                    complianceState      = $row.complianceState
                    subscriptionId       = $row.subscriptionId
                    resourceGroup        = $row.resourceGroup
                    resourceType         = $row.resourceType
                })
            }
            [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                subscriptionId = $sub; status = 'ok'; message = "$($resp.value.Count) non-compliant row(s)"
            })
        }
        catch {
            [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                subscriptionId = $sub; status = 'error'; message = $_.Exception.Message
            })
            [void]$Errors.Add([pscustomobject]@{
                area = 'policyInsights'; scope = "/subscriptions/$sub"; error = $_.Exception.Message
            })
        }
    }

    return $result
}
