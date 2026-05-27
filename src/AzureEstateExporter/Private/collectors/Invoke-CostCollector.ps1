function Invoke-CostCollector {
    <#
    .SYNOPSIS
        Collects Cost Management data for the requested subscription(s).
    .DESCRIPTION
        One purposeful POST per subscription to
        `/providers/Microsoft.CostManagement/query` grouped by `ResourceGroup`
        and `ServiceName`, over `MonthToDate`. We deliberately do NOT add a
        per-tag dimension — the resulting row count can explode and trigger
        throttling (the Cost Management API has tight per-tenant limits).

        The caller needs `Cost Management Reader` (or `Reader`) at the
        subscription scope. Lack of permissions, throttling and "no usage
        yet" are all treated as best-effort: the per-sub failure is appended
        to `Errors` and the collector moves on.

    .PARAMETER SubscriptionIds
        Subscriptions to query.

    .PARAMETER Errors
        Failure ArrayList. Caller owns it.

    .PARAMETER Timeframe
        Cost Management timeframe enum. Defaults to MonthToDate; BillingMonthToDate,
        TheLastMonth, TheLastBillingMonth also valid (see Microsoft docs).

    .OUTPUTS
        [pscustomobject] with members:
          .ByResourceGroup       — array of { subscriptionId, resourceGroup, currency, cost }
          .ByService             — array of { subscriptionId, serviceName, currency, cost }
          .Totals                — array of { subscriptionId, currency, cost }
          .SubscriptionStatus    — array of { subscriptionId, status, message }
          .Timeframe             — the requested timeframe
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$SubscriptionIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Errors,

        [ValidateSet('MonthToDate', 'BillingMonthToDate', 'TheLastMonth', 'TheLastBillingMonth', 'WeekToDate', 'TheLastWeek')]
        [string]$Timeframe = 'MonthToDate'
    )

    $result = [pscustomobject]@{
        ByResourceGroup    = New-Object System.Collections.ArrayList
        ByService          = New-Object System.Collections.ArrayList
        ByResource         = New-Object System.Collections.ArrayList
        Totals             = New-Object System.Collections.ArrayList
        SubscriptionStatus = New-Object System.Collections.ArrayList
        Timeframe          = $Timeframe
    }

    # One purposeful query grouped by RG and ServiceName so we can produce
    # both a per-RG and a per-service summary client-side from the same rows.
    $body = @{
        type      = 'Usage'
        timeframe = $Timeframe
        dataset   = @{
            granularity = 'None'
            aggregation = @{
                totalCost = @{ name = 'Cost'; function = 'Sum' }
            }
            grouping    = @(
                @{ type = 'Dimension'; name = 'ResourceGroupName' },
                @{ type = 'Dimension'; name = 'ServiceName'       }
            )
        }
    } | ConvertTo-Json -Depth 8 -Compress

    foreach ($sub in $SubscriptionIds) {
        $uri = "/subscriptions/$sub/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
        Write-EstateLog "Cost query for $sub ($Timeframe)" -Level Verbose

        # az rest --body inline JSON is mauled on Windows PowerShell — write to temp file.
        $bodyFile = New-TemporaryFile
        try {
            Set-Content -Path $bodyFile.FullName -Value $body -Encoding ascii -NoNewline
            $raw = & az rest --method post `
                --uri $uri `
                --headers 'Content-Type=application/json' `
                --body "@$($bodyFile.FullName)" 2>&1
            if ($LASTEXITCODE -ne 0) {
                $msg = ($raw | Out-String).Trim()
                $status = if ($msg -match '\b(401|403|Forbidden|Unauthorized)\b') { 'unauthorized' }
                          elseif ($msg -match '\b(429|TooManyRequests|throttle)\b') { 'throttled' }
                          elseif ($msg -match '\b(404)\b') { 'unavailable' }
                          else { 'error' }
                [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                    subscriptionId = $sub; status = $status; message = $msg.Substring(0, [Math]::Min(500, $msg.Length))
                })
                [void]$Errors.Add([pscustomobject]@{
                    area = 'cost'; scope = "/subscriptions/$sub"; error = $msg.Substring(0, [Math]::Min(500, $msg.Length))
                })
                continue
            }
            $resp = $raw | ConvertFrom-Json -Depth 32
        }
        catch {
            [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                subscriptionId = $sub; status = 'error'; message = $_.Exception.Message
            })
            [void]$Errors.Add([pscustomobject]@{
                area = 'cost'; scope = "/subscriptions/$sub"; error = $_.Exception.Message
            })
            continue
        }
        finally {
            Remove-Item -Path $bodyFile.FullName -ErrorAction SilentlyContinue
        }

        # Map column names → index. Cost Management always returns:
        #   columns: [{name: 'Cost'}, {name: 'ResourceGroupName'}, {name: 'ServiceName'}, {name: 'Currency'}]
        $cols = @{}
        if ($resp.properties.columns) {
            for ($i = 0; $i -lt $resp.properties.columns.Count; $i++) {
                $cols[$resp.properties.columns[$i].name] = $i
            }
        }
        $rows = @($resp.properties.rows)

        # If the API returned no rows, surface that explicitly. "No spend yet"
        # is a legitimate state for trial subs.
        if ($rows.Count -eq 0) {
            [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                subscriptionId = $sub; status = 'empty'; message = 'No usage data returned for the timeframe.'
            })
            continue
        }

        $rgTotals  = @{}
        $svcTotals = @{}
        $subTotal  = 0.0
        $currency  = $null

        foreach ($row in $rows) {
            $cost = [double]$row[$cols['Cost']]
            $rg   = [string]$row[$cols['ResourceGroupName']]
            $svc  = [string]$row[$cols['ServiceName']]
            $cur  = [string]$row[$cols['Currency']]
            if (-not $currency) { $currency = $cur }
            $subTotal += $cost
            $rgKey  = if ($rg)  { $rg }  else { '(unknown)' }
            $svcKey = if ($svc) { $svc } else { '(unknown)' }
            if ($rgTotals.ContainsKey($rgKey))   { $rgTotals[$rgKey]   += $cost } else { $rgTotals[$rgKey]   = $cost }
            if ($svcTotals.ContainsKey($svcKey)) { $svcTotals[$svcKey] += $cost } else { $svcTotals[$svcKey] = $cost }
        }

        foreach ($rg in $rgTotals.Keys) {
            [void]$result.ByResourceGroup.Add([pscustomobject]@{
                subscriptionId = $sub; resourceGroup = $rg; currency = $currency; cost = [math]::Round($rgTotals[$rg], 2)
            })
        }
        foreach ($svc in $svcTotals.Keys) {
            [void]$result.ByService.Add([pscustomobject]@{
                subscriptionId = $sub; serviceName = $svc; currency = $currency; cost = [math]::Round($svcTotals[$svc], 2)
            })
        }
        [void]$result.Totals.Add([pscustomobject]@{
            subscriptionId = $sub; currency = $currency; cost = [math]::Round($subTotal, 2)
        })
        [void]$result.SubscriptionStatus.Add([pscustomobject]@{
            subscriptionId = $sub; status = 'ok'; message = "$($rows.Count) row(s)"
        })

        # --- 2nd query: by ResourceId — gives per-resource attribution -----
        # Surface as best-effort: a failure here doesn`t invalidate the RG/service
        # data we already have.
        $bodyResource = @{
            type      = 'Usage'
            timeframe = $Timeframe
            dataset   = @{
                granularity = 'None'
                aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
                grouping    = @(@{ type = 'Dimension'; name = 'ResourceId' })
            }
        } | ConvertTo-Json -Depth 8 -Compress
        $resBody = New-TemporaryFile
        try {
            Set-Content -Path $resBody.FullName -Value $bodyResource -Encoding ascii -NoNewline
            $rawR = & az rest --method post --uri $uri --headers 'Content-Type=application/json' --body "@$($resBody.FullName)" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $respR = $rawR | ConvertFrom-Json -Depth 32
                $colsR = @{}
                if ($respR.properties.columns) {
                    for ($i = 0; $i -lt $respR.properties.columns.Count; $i++) {
                        $colsR[$respR.properties.columns[$i].name] = $i
                    }
                }
                foreach ($row in @($respR.properties.rows)) {
                    $rid = [string]$row[$colsR['ResourceId']]
                    if (-not $rid) { continue }
                    [void]$result.ByResource.Add([pscustomobject]@{
                        subscriptionId = $sub
                        resourceId     = $rid
                        cost           = [math]::Round([double]$row[$colsR['Cost']], 2)
                        currency       = [string]$row[$colsR['Currency']]
                    })
                }
            } else {
                [void]$Errors.Add([pscustomobject]@{
                    area = 'costByResource'; scope = "/subscriptions/$sub"
                    error = (($rawR | Out-String).Trim()).Substring(0, [Math]::Min(300, ($rawR | Out-String).Length))
                })
            }
        }
        finally { Remove-Item -Path $resBody.FullName -ErrorAction SilentlyContinue }
    }

    return $result
}
