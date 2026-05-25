function Invoke-ArmCollector {
    <#
    .SYNOPSIS
        Supplemental ARM collector — fills gaps that Azure Resource Graph
        does not expose well (diagnostic settings, role assignments, locks,
        policy assignments).
    .DESCRIPTION
        Best-effort. Each sub-collector is wrapped in try/catch so a failure
        in one area does not abort the others. Errors are appended to the
        caller-supplied Errors collection rather than thrown.
    .PARAMETER SubscriptionIds
        Subscriptions to enumerate.
    .PARAMETER Errors
        A [System.Collections.ArrayList] the collector appends per-item
        failure objects to. Must be created by the caller.
    .OUTPUTS
        [pscustomobject] with members .DiagnosticSettings, .RoleAssignments,
        .Locks, .PolicyAssignments — each an array (possibly empty).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$SubscriptionIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$Errors
    )

    $result = [pscustomobject]@{
        DiagnosticSettings = @()
        RoleAssignments    = @()
        Locks              = @()
        PolicyAssignments  = @()
    }

    foreach ($sub in $SubscriptionIds) {
        Write-EstateLog "ARM supplemental collectors for sub $sub" -Level Verbose

        # Role assignments (subscription scope).
        try {
            $ra = & az role assignment list --subscription $sub --all --output json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.RoleAssignments += ($ra | ConvertFrom-Json -Depth 16)
            }
            else {
                throw "az role assignment list exit $LASTEXITCODE`: $ra"
            }
        }
        catch {
            [void]$Errors.Add([pscustomobject]@{
                area = 'roleAssignments'; scope = "/subscriptions/$sub"; error = $_.Exception.Message
            })
        }

        # Resource locks.
        try {
            $locks = & az lock list --subscription $sub --output json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.Locks += ($locks | ConvertFrom-Json -Depth 16)
            }
            else {
                throw "az lock list exit $LASTEXITCODE`: $locks"
            }
        }
        catch {
            [void]$Errors.Add([pscustomobject]@{
                area = 'locks'; scope = "/subscriptions/$sub"; error = $_.Exception.Message
            })
        }

        # Policy assignments.
        try {
            $pa = & az policy assignment list --subscription $sub --disable-scope-strict-match --output json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.PolicyAssignments += ($pa | ConvertFrom-Json -Depth 16)
            }
            else {
                throw "az policy assignment list exit $LASTEXITCODE`: $pa"
            }
        }
        catch {
            [void]$Errors.Add([pscustomobject]@{
                area = 'policyAssignments'; scope = "/subscriptions/$sub"; error = $_.Exception.Message
            })
        }

        # Diagnostic settings: not subscription-wide; resolved per-resource later.
        # In v0.1 we expose only the discovery hook; the renderer can fan out
        # to `az monitor diagnostic-settings list --resource <id>` for hot resources.
    }

    return $result
}
