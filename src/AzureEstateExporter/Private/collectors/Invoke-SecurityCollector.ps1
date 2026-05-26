function Invoke-SecurityCollector {
    <#
    .SYNOPSIS
        Collects Microsoft Defender for Cloud secure score and top
        recommendations per subscription.
    .DESCRIPTION
        Defender for Cloud is a paid product and many subscriptions do not
        have it enabled. The collector handles that gracefully:
          * 404 / 410 / "subscription not registered" -> marked as `disabled`
          * 401 / 403 -> marked as `unauthorized`
          * Anything else -> marked as `error`, appended to `Errors`

        We pull:
          1. secureScores/ascScore                -> overall sub score
          2. assessments?$top=N (severity desc)   -> top recommendations

        Assessments are capped per-sub to avoid blowing the report.

    .PARAMETER SubscriptionIds
        Subscriptions to query.

    .PARAMETER Errors
        Failure ArrayList. Caller owns it.

    .PARAMETER AssessmentsPerSub
        Max number of unhealthy assessments to keep per subscription.
        Default 50.

    .OUTPUTS
        [pscustomobject] with members:
          .SecureScores            — { subscriptionId, score, max, percentage, weight }
          .Assessments             — { subscriptionId, id, displayName, severity, status, resourceId, description }
          .SubscriptionStatus      — { subscriptionId, status, message }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$SubscriptionIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Errors,

        [int]$AssessmentsPerSub = 50
    )

    $result = [pscustomobject]@{
        SecureScores       = New-Object System.Collections.ArrayList
        Assessments        = New-Object System.Collections.ArrayList
        SubscriptionStatus = New-Object System.Collections.ArrayList
    }

    foreach ($sub in $SubscriptionIds) {
        Write-EstateLog "Defender query for $sub" -Level Verbose

        $scoreUri = "/subscriptions/$sub/providers/Microsoft.Security/secureScores/ascScore?api-version=2020-01-01"
        $assessUri = "/subscriptions/$sub/providers/Microsoft.Security/assessments?api-version=2020-01-01"

        # --- Secure score ----------------------------------------------------
        try {
            $raw = & az rest --method get --uri $scoreUri 2>&1
            if ($LASTEXITCODE -ne 0) {
                $msg = ($raw | Out-String).Trim()
                if ($msg -match '\b(404|SubscriptionNotRegistered|NotFound|410)\b') {
                    [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                        subscriptionId = $sub; status = 'defender-disabled'
                        message = 'Defender for Cloud not enabled on this subscription.'
                    })
                    continue
                }
                if ($msg -match '\b(401|403|Forbidden|Unauthorized)\b') {
                    [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                        subscriptionId = $sub; status = 'unauthorized'
                        message = 'Caller lacks Microsoft.Security/securescores read permissions.'
                    })
                    continue
                }
                throw $msg
            }
            $score = $raw | ConvertFrom-Json -Depth 16
            [void]$result.SecureScores.Add([pscustomobject]@{
                subscriptionId = $sub
                score          = [double]$score.properties.score.current
                max            = [double]$score.properties.score.max
                percentage     = [double]$score.properties.score.percentage
                weight         = [int]$score.properties.weight
            })
        }
        catch {
            [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                subscriptionId = $sub; status = 'error'; message = $_.Exception.Message
            })
            [void]$Errors.Add([pscustomobject]@{
                area = 'secureScore'; scope = "/subscriptions/$sub"; error = $_.Exception.Message
            })
            continue
        }

        # --- Assessments (unhealthy only) -----------------------------------
        try {
            $raw = & az rest --method get --uri $assessUri 2>&1
            if ($LASTEXITCODE -ne 0) {
                $msg = ($raw | Out-String).Trim()
                # If score succeeded but assessments didn't, soft-fail.
                [void]$Errors.Add([pscustomobject]@{
                    area = 'securityAssessments'; scope = "/subscriptions/$sub"
                    error = $msg.Substring(0, [Math]::Min(500, $msg.Length))
                })
                continue
            }
            $resp = $raw | ConvertFrom-Json -Depth 32
            $unhealthy = @($resp.value | Where-Object {
                $_.properties.status.code -in @('Unhealthy', 'NotApplicable') -eq $false -and $_.properties.status.code -ne 'Healthy'
            } | Sort-Object @{ Expression = {
                switch ($_.properties.metadata.severity) {
                    'High'   { 0 }; 'Medium' { 1 }; 'Low' { 2 }; default { 3 }
                }
            } } | Select-Object -First $AssessmentsPerSub)
            foreach ($a in $unhealthy) {
                [void]$result.Assessments.Add([pscustomobject]@{
                    subscriptionId = $sub
                    id             = $a.id
                    displayName    = $a.properties.displayName
                    severity       = $a.properties.metadata.severity
                    status         = $a.properties.status.code
                    cause          = $a.properties.status.cause
                    description    = $a.properties.metadata.description
                    resourceId     = $a.properties.resourceDetails.id
                })
            }
            [void]$result.SubscriptionStatus.Add([pscustomobject]@{
                subscriptionId = $sub; status = 'ok'
                message = ('{0} unhealthy assessment(s) returned (capped to {1}).' -f $unhealthy.Count, $AssessmentsPerSub)
            })
        }
        catch {
            [void]$Errors.Add([pscustomobject]@{
                area = 'securityAssessments'; scope = "/subscriptions/$sub"; error = $_.Exception.Message
            })
        }
    }

    return $result
}
