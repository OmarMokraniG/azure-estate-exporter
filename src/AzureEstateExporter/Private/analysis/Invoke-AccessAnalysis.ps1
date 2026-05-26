function Invoke-AccessAnalysis {
    <#
    .SYNOPSIS
        Derives "who can do what" findings from already-collected role
        assignments.
    .DESCRIPTION
        Pure analysis step — NO Azure calls. Consumes the role-assignment
        rows that `Invoke-ArmCollector` already pulled. Produces:

          .ByPrincipal       — table of principals with their assignment count and
                               the most privileged role they hold.
          .PrivilegedAtScope — list of broad-scope privileged assignments
                               (Owner / User Access Administrator at sub-level,
                               Contributor at sub-level).
          .OrphanedAssignments — assignments whose principal has been deleted
                                 (shows up as `principalName = $null` and
                                 `principalType = Unknown`).
          .Findings          — severity-graded findings consumable by the report.

        Heuristic: if a role definition is one of:
          - Owner
          - User Access Administrator
          - Contributor
          - Storage Blob Data Owner
        and the scope is a subscription (`/subscriptions/<guid>` exactly),
        we emit a `High` finding. Same role at RG scope is `Medium`.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$RoleAssignments
    )

    $privilegedRoles = @{
        'Owner'                     = 'High'
        'User Access Administrator' = 'High'
        'Contributor'               = 'Medium'
        'Storage Blob Data Owner'   = 'Medium'
    }

    $byPrincipal = @{}
    $privilegedAtScope = New-Object System.Collections.Generic.List[pscustomobject]
    $orphaned = New-Object System.Collections.Generic.List[pscustomobject]
    $findings = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($ra in $RoleAssignments) {
        # az role assignment list shapes vary slightly across versions; we tolerate both.
        $principalId   = $ra.principalId
        $principalName = if ($ra.principalName) { $ra.principalName }
                         elseif ($ra.displayName) { $ra.displayName }
                         else { $null }
        $principalType = if ($ra.principalType) { $ra.principalType } else { 'Unknown' }
        $role          = if ($ra.roleDefinitionName) { $ra.roleDefinitionName }
                         elseif ($ra.properties.roleDefinitionName) { $ra.properties.roleDefinitionName }
                         else { $null }
        $scope         = if ($ra.scope) { $ra.scope } else { $ra.properties.scope }

        if (-not $principalId -or -not $role -or -not $scope) { continue }

        $key = "$principalId|$principalType"
        if (-not $byPrincipal.ContainsKey($key)) {
            $byPrincipal[$key] = [pscustomobject]@{
                principalId    = $principalId
                principalName  = $principalName
                principalType  = $principalType
                assignmentCount = 0
                roles          = New-Object System.Collections.Generic.HashSet[string]
                topSeverity    = 'None'
            }
        }
        $entry = $byPrincipal[$key]
        $entry.assignmentCount++
        [void]$entry.roles.Add($role)
        if ($privilegedRoles.ContainsKey($role)) {
            $sev = $privilegedRoles[$role]
            if ($sev -eq 'High' -or ($sev -eq 'Medium' -and $entry.topSeverity -ne 'High')) {
                $entry.topSeverity = $sev
            }
        }

        # Orphan detection — principal not resolvable (deleted).
        if (-not $principalName) {
            $orphaned.Add([pscustomobject]@{
                principalId   = $principalId
                principalType = $principalType
                role          = $role
                scope         = $scope
            })
        }

        # Broad-scope privileged assignments.
        if ($privilegedRoles.ContainsKey($role)) {
            $isSubScope = $scope -match '^/subscriptions/[0-9a-fA-F-]{36}$'
            $isRgScope  = $scope -match '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$'
            if ($isSubScope -or $isRgScope) {
                $sev = if ($isSubScope) { $privilegedRoles[$role] }
                       else { if ($privilegedRoles[$role] -eq 'High') { 'Medium' } else { 'Low' } }
                $entry2 = [pscustomobject]@{
                    severity      = $sev
                    role          = $role
                    scope         = $scope
                    scopeKind     = if ($isSubScope) { 'subscription' } else { 'resource group' }
                    principalName = $principalName
                    principalType = $principalType
                    principalId   = $principalId
                }
                $privilegedAtScope.Add($entry2)
                $findings.Add([pscustomobject]@{
                    severity       = $sev
                    type           = 'BroadScopeRoleAssignment'
                    title          = ("{0} ``{1}`` is **{2}** at {3} ``{4}``" -f $principalType, ($principalName ?? $principalId), $role, $entry2.scopeKind, ($scope -split '/')[-1])
                    resourceId     = $scope
                    evidence       = ("scope={0}; role={1}" -f $scope, $role)
                    recommendation = if ($isSubScope) { 'Replace broad sub-level grants with RG-scoped or resource-scoped role assignments where possible. Audit Owner grants quarterly.' }
                                     else { 'RG-scoped grants are tighter than sub-scoped but still review whether resource-scope would suffice.' }
                })
            }
        }
    }

    # Orphan finding.
    if ($orphaned.Count -gt 0) {
        $findings.Add([pscustomobject]@{
            severity       = 'Medium'
            type           = 'OrphanedRoleAssignment'
            title          = ("{0} role assignment(s) point to principals that no longer exist" -f $orphaned.Count)
            resourceId     = $null
            evidence       = "$($orphaned.Count) assignments have null principalName / type=Unknown."
            recommendation = 'Run `az role assignment list --include-inherited --output table` and clean up unresolvable principalIds.'
        })
    }

    return [pscustomobject]@{
        ByPrincipal         = @($byPrincipal.Values | Sort-Object assignmentCount -Descending)
        PrivilegedAtScope   = @($privilegedAtScope)
        OrphanedAssignments = @($orphaned)
        Findings            = @($findings)
    }
}
