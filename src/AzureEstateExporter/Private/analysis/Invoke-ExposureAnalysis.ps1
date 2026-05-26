function Invoke-ExposureAnalysis {
    <#
    .SYNOPSIS
        Derives internet-exposure findings from the already-collected inventory.
    .DESCRIPTION
        Pure analysis step — NO Azure calls. Walks the normalized inventory
        and emits structured findings with severity, evidence and a one-line
        recommendation. This works even when the caller has zero Defender
        coverage.

        The signals it covers in v0.4.0:

          1. NSG security rules that allow Inbound traffic from 0.0.0.0/0
             on management ports (SSH/RDP/WinRM) or on a wildcard range.
          2. Public IP addresses assigned to network interfaces or
             standalone (they will carry SOMETHING into the internet).
          3. Storage accounts with `allowBlobPublicAccess = true` AND
             `publicNetworkAccess = Enabled` AND no IP/subnet restrictions.
          4. App Services / Function Apps where `publicNetworkAccess` is
             Enabled and no IP-restriction rules are configured.
          5. Key Vaults with `publicNetworkAccess` Enabled and a default
             firewall allow.

        Each finding is a [pscustomobject]:
          severity     — 'High' | 'Medium' | 'Low' | 'Info'
          type         — short machine-readable identifier
          title        — one-line human label
          resourceId   — the offending resource id
          subscriptionId
          resourceGroup
          evidence     — quoted excerpt from the resource for the report
          recommendation
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]]$Inventory
    )

    $findings = New-Object System.Collections.Generic.List[pscustomobject]

    # Helper to build a finding.
    $add = {
        param($severity, $type, $title, $r, $evidence, $recommendation)
        $findings.Add([pscustomobject]@{
            severity       = $severity
            type           = $type
            title          = $title
            resourceId     = $r.id
            resourceName   = $r.name
            resourceType   = $r.type
            subscriptionId = $r.subscriptionId
            resourceGroup  = $r.resourceGroup
            evidence       = $evidence
            recommendation = $recommendation
        })
    }

    foreach ($r in $Inventory) {
        $type = "$($r.type)".ToLowerInvariant()
        $props = $r.properties

        switch -Wildcard ($type) {

            'microsoft.network/networksecuritygroups' {
                $rules = @()
                if ($props.securityRules) { $rules += @($props.securityRules) }
                if ($props.defaultSecurityRules) { $rules += @($props.defaultSecurityRules) }
                foreach ($rule in $rules) {
                    $p = $rule.properties
                    if (-not $p) { continue }
                    if ($p.access -ne 'Allow' -or $p.direction -ne 'Inbound') { continue }
                    $sources = @()
                    if ($p.sourceAddressPrefix)   { $sources += $p.sourceAddressPrefix }
                    if ($p.sourceAddressPrefixes) { $sources += @($p.sourceAddressPrefixes) }
                    $isInternet = $sources | Where-Object {
                        $_ -in @('*', '0.0.0.0/0', 'Internet', 'Any')
                    }
                    if (-not $isInternet) { continue }
                    $ports = @()
                    if ($p.destinationPortRange)   { $ports += $p.destinationPortRange }
                    if ($p.destinationPortRanges)  { $ports += @($p.destinationPortRanges) }
                    $portStr = $ports -join ', '
                    $mgmtPorts = $ports | Where-Object { $_ -in @('22', '3389', '5985', '5986') -or $_ -eq '*' -or $_ -like '*-*' }
                    $severity = if ($mgmtPorts) { 'High' } else { 'Medium' }
                    $typeId = if ($mgmtPorts) { 'OpenManagementPort' } else { 'OpenInternetIngress' }
                    & $add $severity $typeId `
                        ("NSG ``{0}`` allows {1} from {2}" -f $r.name, $portStr, ($sources -join '/')) `
                        $r `
                        ("rule ``{0}``: allow {1}/{2} -> {3} (priority {4})" -f $rule.name, $p.protocol, $portStr, ($sources -join '/'), $p.priority) `
                        ('Restrict source to a corporate CIDR, replace with Azure Bastion / JIT / Private Link.')
                }
                break
            }

            'microsoft.network/publicipaddresses' {
                # Standalone PIP — informational, the linked resource is the real story.
                & $add 'Info' 'PublicIpExists' `
                    ("Public IP ``{0}``" -f $r.name) `
                    $r `
                    ("sku={0}, allocation={1}, address={2}" -f $r.sku.name, $props.publicIPAllocationMethod, $props.ipAddress) `
                    ('Each public IP is an internet entry point. Confirm it is intentional and protected by NSG/Firewall.')
                break
            }

            'microsoft.storage/storageaccounts' {
                $publicNet = "$($props.publicNetworkAccess)"
                $allowBlob = [bool]$props.allowBlobPublicAccess
                $rules     = $props.networkAcls
                $defAllow  = "$($rules.defaultAction)" -eq 'Allow'
                if ($publicNet -eq 'Enabled' -and $defAllow) {
                    $severity = if ($allowBlob) { 'High' } else { 'Medium' }
                    $typeId   = if ($allowBlob) { 'PublicBlobAccess' } else { 'StoragePublicNetwork' }
                    & $add $severity $typeId `
                        ("Storage account ``{0}`` is reachable from the internet" -f $r.name) `
                        $r `
                        ("publicNetworkAccess={0}, allowBlobPublicAccess={1}, networkAcls.defaultAction={2}" -f $publicNet, $allowBlob, $rules.defaultAction) `
                        ('Set publicNetworkAccess=Disabled, allowBlobPublicAccess=false, or restrict with IP/subnet rules / Private Endpoint.')
                }
                break
            }

            'microsoft.web/sites' {
                $publicNet = "$($props.publicNetworkAccess)"
                $restrict  = @($props.siteConfig.ipSecurityRestrictions)
                $hasRestr  = ($restrict.Count -gt 0 -and -not ($restrict | Where-Object { $_.ipAddress -eq 'Any' -and $_.action -eq 'Allow' }))
                if ($publicNet -eq 'Enabled' -and -not $hasRestr) {
                    & $add 'Medium' 'AppServiceUnrestricted' `
                        ("App Service ``{0}`` is publicly reachable without IP restrictions" -f $r.name) `
                        $r `
                        ("publicNetworkAccess={0}, ipSecurityRestrictions.count={1}" -f $publicNet, $restrict.Count) `
                        ('Configure ipSecurityRestrictions / Access Restrictions or front with App Gateway / Front Door.')
                }
                break
            }

            'microsoft.keyvault/vaults' {
                $publicNet = "$($props.publicNetworkAccess)"
                $defAllow  = "$($props.networkAcls.defaultAction)" -eq 'Allow'
                if ($publicNet -eq 'Enabled' -and $defAllow) {
                    & $add 'High' 'KeyVaultPublicAccess' `
                        ("Key Vault ``{0}`` allows public network access" -f $r.name) `
                        $r `
                        ("publicNetworkAccess={0}, networkAcls.defaultAction={1}" -f $publicNet, $props.networkAcls.defaultAction) `
                        ('Set publicNetworkAccess=Disabled (preferred) or restrict networkAcls to specific IPs / VNets / Private Endpoint.')
                }
                break
            }
        }
    }

    # Order: High -> Medium -> Low -> Info, then by type, then by resource name.
    $sevOrder = @{ 'High' = 0; 'Medium' = 1; 'Low' = 2; 'Info' = 3 }
    return @($findings | Sort-Object @{ Expression = { $sevOrder[$_.severity] } }, type, resourceName)
}
