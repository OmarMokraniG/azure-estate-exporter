function Invoke-ArgCollector {
    <#
    .SYNOPSIS
        Primary inventory collector — queries Azure Resource Graph (ARG).
    .DESCRIPTION
        Pulls every resource visible to the caller in the requested scope using
        a single KQL query, paginating with --skip-token. Output is the raw ARG
        rows; normalization to the estate model happens later in
        ConvertTo-EstateModel.

        Shells out to `az graph query` rather than the Az.* PowerShell modules.
    .PARAMETER SubscriptionIds
        One or more subscription IDs. ARG is fastest when the scope is bounded.
    .PARAMETER ResourceGroup
        Optional. When supplied, the KQL `where` clause is narrowed.
    .PARAMETER CountOnly
        When set, runs a `summarize count()` query and returns a single
        integer (the total resource count in scope) instead of full rows.
        Used by the orchestrator for the cheap preflight check.
    .OUTPUTS
        [pscustomobject[]] of ARG rows, or [int] when -CountOnly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SubscriptionIds,

        [string]$ResourceGroup,

        [switch]$CountOnly
    )

    if ($CountOnly) {
        $kqlParts = @('resources')
        if ($ResourceGroup) { $kqlParts += "where resourceGroup =~ '$ResourceGroup'" }
        $kqlParts += 'summarize count()'
        $kql = $kqlParts -join ' | '

        $argv = @('graph', 'query', '--graph-query', $kql, '--output', 'json')
        foreach ($s in $SubscriptionIds) { $argv += @('--subscriptions', $s) }

        $raw = & az @argv 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "az graph query (count) failed (exit $LASTEXITCODE): $raw"
        }
        $resp = $raw | ConvertFrom-Json -Depth 8
        return [int]$resp.data[0].count_
    }

    # KQL MUST be a single line.
    # On Windows, multi-line strings passed via argv are truncated at the first LF
    # by the cmd.exe shim used by the `az` Python entrypoint, which silently drops
    # any pipeline stages after the first newline.
    $kqlParts = @(
        'resources',
        'project id, name, type, kind, location, resourceGroup, subscriptionId, managedBy, tags, sku, identity, properties'
    )
    if ($ResourceGroup) {
        $kqlParts += "where resourceGroup =~ '$ResourceGroup'"
    }
    $kqlParts += 'order by subscriptionId asc, resourceGroup asc, type asc, name asc'
    $kql = $kqlParts -join ' | '

    Write-EstateLog "ARG query against $($SubscriptionIds.Count) subscription(s)" -Level Verbose

    $rows = New-Object System.Collections.ArrayList
    $skipToken = $null
    $page = 0

    do {
        $page++
        $argv = @(
            'graph', 'query',
            '--graph-query', $kql,
            '--first', '1000',
            '--output', 'json'
        )
        foreach ($s in $SubscriptionIds) {
            $argv += @('--subscriptions', $s)
        }
        if ($skipToken) {
            $argv += @('--skip-token', $skipToken)
        }

        try {
            $raw = & az @argv 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "az graph query failed (exit $LASTEXITCODE): $raw"
            }
            $resp = $raw | ConvertFrom-Json -Depth 32
        }
        catch {
            Write-EstateLog "ARG page $page failed: $($_.Exception.Message)" -Level Error
            throw
        }

        if ($resp.data) {
            foreach ($r in $resp.data) { [void]$rows.Add($r) }
        }
        $skipToken = $resp.skip_token
        if (-not $skipToken) { $skipToken = $resp.'$skipToken' }
        Write-EstateLog ("ARG page {0}: +{1} (total {2}), more={3}" -f $page, $resp.data.Count, $rows.Count, [bool]$skipToken) -Level Verbose
    } while ($skipToken)

    Write-EstateLog "ARG collected $($rows.Count) resource(s)" -Level Success
    return , $rows.ToArray()
}

