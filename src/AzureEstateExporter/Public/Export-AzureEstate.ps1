function Export-AzureEstate {
    <#
    .SYNOPSIS
        Inventories an Azure scope and produces a Markdown report, diagrams,
        and a Terraform HCL baseline.
    .DESCRIPTION
        Orchestrator. Three explicit layers: collectors (ARG + ARM) -> normalized
        model -> renderers (markdown, mermaid, excalidraw, terraform-via-aztfexport).

        Scope semantics — pick exactly one:
          * -SubscriptionId           : one subscription.
          * -SubscriptionId -RG       : one resource group.
          * -TenantId  -ConfirmLargeExport : every subscription the caller can see.
                                       Does NOT include Entra ID or management
                                       groups in v0.1 (roadmap).

        Modes (combinable, default = everything):
          -InventoryOnly  -DiagramOnly  -TerraformOnly

        Safety:
          * Redaction is on by default. Disable with -NoRedact (warns).
          * For scopes that resolve to more than -ResourceLimit resources, the
            run aborts unless -ConfirmLargeExport is also passed.

    .EXAMPLE
        Export-AzureEstate -OutputPath ./out
        # Uses the currently selected `az` subscription.

    .EXAMPLE
        Export-AzureEstate -SubscriptionId <guid> -ResourceGroup my-rg -InventoryOnly

    .EXAMPLE
        Export-AzureEstate -TenantId <guid> -ConfirmLargeExport -ResourceLimit 5000
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Subscription')]
    param(
        [Parameter(ParameterSetName = 'Subscription')]
        [Parameter(ParameterSetName = 'ResourceGroup', Mandatory)]
        [string]$SubscriptionId,

        [Parameter(ParameterSetName = 'ResourceGroup', Mandatory)]
        [string]$ResourceGroup,

        [Parameter(ParameterSetName = 'Tenant', Mandatory)]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Tenant', Mandatory)]
        [switch]$ConfirmLargeExport,

        [string]$OutputPath = './out',

        [switch]$InventoryOnly,
        [switch]$DiagramOnly,
        [switch]$TerraformOnly,

        [ValidateSet('Mermaid', 'Excalidraw', 'Both')]
        [string]$Diagram = 'Mermaid',

        [switch]$WithImport,
        [switch]$NoRedact,
        [switch]$NoTerraformRepo,

        # Customer-grade collectors (v0.4.0). All on by default; opt-out switches.
        [switch]$SkipCost,
        [switch]$SkipSecurity,
        [switch]$SkipPolicy,

        [int]$ResourceLimit = 500
    )

    $ErrorActionPreference = 'Stop'

    # --- 1. Preconditions ------------------------------------------------------
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI (`az`) is required and was not found on PATH. See https://learn.microsoft.com/cli/azure/install-azure-cli'
    }

    try {
        $account = & az account show --output json 2>&1 | ConvertFrom-Json
    }
    catch {
        throw 'Not logged in. Run `az login` first.'
    }
    Write-EstateLog "Authenticated as $($account.user.name) on tenant $($account.tenantId)" -Level Info

    # Ensure required az extensions are present; install non-interactively if missing.
    # `resource-graph` powers Invoke-ArgCollector.
    $extJson = & az extension list --output json 2>$null
    $installedExts = @()
    if ($extJson) { $installedExts = ($extJson | ConvertFrom-Json).name }
    if ('resource-graph' -notin $installedExts) {
        Write-EstateLog 'Installing required az extension: resource-graph' -Level Info
        if ($PSCmdlet.ShouldProcess('az extension add', 'install resource-graph')) {
            & az extension add --name resource-graph --only-show-errors --yes 2>&1 | ForEach-Object { Write-Verbose $_ }
            if ($LASTEXITCODE -ne 0) {
                throw 'Failed to install the `resource-graph` az extension. Install it manually with `az extension add --name resource-graph` and re-run.'
            }
        }
    }

    if ($NoRedact) {
        Write-EstateLog '-NoRedact set. Sensitive keys will be written to disk in clear text. Make sure this is what you want.' -Level Warn
    }

    # --- 2. Resolve scope ------------------------------------------------------
    $subIds = @()
    switch ($PSCmdlet.ParameterSetName) {
        'Tenant' {
            Write-EstateLog "Tenant-wide scope: enumerating subscriptions visible in tenant $TenantId" -Level Info
            $allSubs = & az account list --output json | ConvertFrom-Json
            $subIds = $allSubs | Where-Object { $_.tenantId -eq $TenantId } | Select-Object -ExpandProperty id
            if (-not $subIds) {
                throw "No subscriptions visible to the caller in tenant $TenantId."
            }
        }
        'ResourceGroup' {
            $subIds = @($SubscriptionId)
        }
        default {
            if ($SubscriptionId) { $subIds = @($SubscriptionId) }
            else { $subIds = @($account.id) }
        }
    }
    Write-EstateLog "Scope resolved to $($subIds.Count) subscription(s)" -Level Info

    # --- 3. Preflight (cheap count) -------------------------------------------
    $rgFilter = if ($PSCmdlet.ParameterSetName -eq 'ResourceGroup') { $ResourceGroup } else { $null }
    $count = Invoke-ArgCollector -SubscriptionIds $subIds -ResourceGroup $rgFilter -CountOnly
    Write-EstateLog "Preflight: ~$count resource(s) in scope. ResourceLimit=$ResourceLimit." -Level Info

    if ($count -gt $ResourceLimit -and -not $ConfirmLargeExport) {
        throw "Scope contains $count resources, above -ResourceLimit ($ResourceLimit). Re-run with -ConfirmLargeExport (or raise -ResourceLimit) to proceed."
    }

    # --- 4. Prepare output dir -------------------------------------------------
    $stamp   = (Get-Date).ToString('yyyy-MM-ddTHH-mm-ss')
    $runRoot = Join-Path $OutputPath $stamp
    if ($PSCmdlet.ShouldProcess($runRoot, 'Create run directory')) {
        New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    }
    Write-EstateLog "Output -> $runRoot" -Level Info

    $errors = [System.Collections.ArrayList]::new()

    # --- 5. Collectors ---------------------------------------------------------
    Write-EstateLog 'Running collectors...' -Level Info
    $arg     = Invoke-ArgCollector  -SubscriptionIds $subIds -ResourceGroup $rgFilter
    $armExtras = Invoke-ArmCollector -SubscriptionIds $subIds -Errors $errors

    # --- 5b. Customer-grade collectors (v0.4.0) -------------------------------
    # Each one is best-effort: a Defender-disabled sub or a permissions error
    # surfaces as an entry in $errors and a `*SubscriptionStatus` row on the
    # collector output, never as a thrown exception.
    $cost = $null; $security = $null; $policy = $null
    if (-not $SkipCost) {
        try { $cost = Invoke-CostCollector -SubscriptionIds $subIds -Errors $errors }
        catch { Write-EstateLog "Cost collector failed: $($_.Exception.Message)" -Level Warn }
    }
    if (-not $SkipSecurity) {
        try { $security = Invoke-SecurityCollector -SubscriptionIds $subIds -Errors $errors }
        catch { Write-EstateLog "Security collector failed: $($_.Exception.Message)" -Level Warn }
    }
    if (-not $SkipPolicy) {
        try { $policy = Invoke-PolicyStateCollector -SubscriptionIds $subIds -Errors $errors }
        catch { Write-EstateLog "Policy collector failed: $($_.Exception.Message)" -Level Warn }
    }

    # --- 6. Normalize ---------------------------------------------------------
    $model = ConvertTo-EstateModel -ArgRows $arg -ArmExtras $armExtras

    # --- 6b. Derived analysis (no Azure calls; pure model functions) ----------
    $model.Cost     = $cost
    $model.Security = $security
    $model.Policy   = $policy
    try {
        $model.Exposure = Invoke-ExposureAnalysis -Inventory $model.Inventory
    } catch { Write-EstateLog "Exposure analysis failed: $($_.Exception.Message)" -Level Warn }
    try {
        $model.Access = Invoke-AccessAnalysis -RoleAssignments @($armExtras.RoleAssignments)
    } catch { Write-EstateLog "Access analysis failed: $($_.Exception.Message)" -Level Warn }

    # Redaction pass.
    $safeModel = Protect-SensitiveValue -InputObject $model -NoRedact:$NoRedact

    if ($PSCmdlet.ShouldProcess("$runRoot/inventory.json", 'Write inventory')) {
        $safeModel.Inventory | ConvertTo-Json -Depth 32 | Set-Content "$runRoot/inventory.json" -Encoding utf8
        $safeModel.Graph     | ConvertTo-Json -Depth 32 | Set-Content "$runRoot/graph.json"     -Encoding utf8
        if ($null -ne $safeModel.Cost)     { $safeModel.Cost     | ConvertTo-Json -Depth 8  | Set-Content "$runRoot/cost.json"     -Encoding utf8 }
        if ($null -ne $safeModel.Security) { $safeModel.Security | ConvertTo-Json -Depth 16 | Set-Content "$runRoot/security.json" -Encoding utf8 }
        if ($null -ne $safeModel.Policy)   { $safeModel.Policy   | ConvertTo-Json -Depth 16 | Set-Content "$runRoot/policy.json"   -Encoding utf8 }
        if ($safeModel.Exposure)           { ,@($safeModel.Exposure) | ConvertTo-Json -Depth 16 | Set-Content "$runRoot/exposure.json" -Encoding utf8 }
        if ($null -ne $safeModel.Access)   { $safeModel.Access   | ConvertTo-Json -Depth 16 | Set-Content "$runRoot/access.json"   -Encoding utf8 }
    }

    # --- 7. Renderers ---------------------------------------------------------
    $doReport    = -not ($DiagramOnly -or $TerraformOnly)
    $doDiagram   = -not ($InventoryOnly -or $TerraformOnly)
    $doTerraform = -not ($InventoryOnly -or $DiagramOnly)

    if ($doReport) {
        New-MarkdownReport -Model $safeModel -OutputPath "$runRoot/report/report.md"
    }

    if ($doDiagram) {
        if ($Diagram -in 'Mermaid', 'Both') {
            New-MermaidDiagram -Model $safeModel -OutputPath "$runRoot/diagrams/estate.mmd"
        }
        if ($Diagram -in 'Excalidraw', 'Both') {
            if ($safeModel.Inventory.Count -gt 300) {
                Write-EstateLog "Estate has $($safeModel.Inventory.Count) resources; Excalidraw is unreadable above ~300. Mermaid is recommended." -Level Warn
            }
            New-ExcalidrawDiagram -Model $safeModel -OutputPath "$runRoot/diagrams/estate.excalidraw"
        }
    }

    if ($doTerraform) {
        Invoke-TerraformExport -Model $safeModel -OutputRoot "$runRoot/terraform" -WithImport:$WithImport -Errors $errors

        if (-not $NoTerraformRepo) {
            try {
                New-TerraformRepoPackage `
                    -TerraformOutputRoot "$runRoot/terraform" `
                    -RepoPath "$runRoot/terraform-repo" `
                    -GeneratorVersion (Get-Module AzureEstateExporter | Select-Object -First 1).Version.ToString() `
                    -Force | Out-Null
            } catch {
                Write-EstateLog "Terraform repo packager failed: $($_.Exception.Message)" -Level Warn
                [void]$errors.Add([pscustomobject]@{ area = 'terraform-repo'; scope = '*'; error = $_.Exception.Message })
            }
        }
    }

    # --- 8. Collection confidence (manifest meta) ----------------------------
    # We fill this AFTER renderers so errorsByArea reflects everything we tried.
    $moduleVersion = (Get-Module AzureEstateExporter | Select-Object -First 1).Version.ToString()
    function Get-ToolVersion([string]$exe, [string]$arg = '--version') {
        $cmd = Get-Command $exe -ErrorAction SilentlyContinue
        if (-not $cmd) { return $null }
        try {
            # `az version` returns JSON; everything else returns a one-liner first.
            if ($exe -eq 'az') {
                $j = & $exe version --output json 2>$null | ConvertFrom-Json
                if ($j -and $j.'azure-cli') { return "azure-cli $($j.'azure-cli')" }
            }
            $raw = & $exe $arg 2>&1 | Select-Object -First 1
            return (("$raw") -replace '\s+', ' ').Trim()
        } catch { return $null }
    }
    $errorsByArea = @{}
    foreach ($e in $errors) {
        $area = if ($e.area) { $e.area } else { 'unknown' }
        if ($errorsByArea.ContainsKey($area)) { $errorsByArea[$area]++ } else { $errorsByArea[$area] = 1 }
    }

    $safeModel.Manifest.generator = [pscustomobject]@{
        name        = 'azure-estate-exporter'
        version     = $moduleVersion
        generatedAt = (Get-Date -Format 'o')
    }
    $safeModel.Manifest.scope = [pscustomobject]@{
        kind            = $PSCmdlet.ParameterSetName
        subscriptionIds = $subIds
        resourceGroup   = $rgFilter
        tenantId        = if ($PSCmdlet.ParameterSetName -eq 'Tenant') { $TenantId } else { $account.tenantId }
    }
    $safeModel.Manifest.collection = [pscustomobject]@{
        subscriptionsQueried = $subIds.Count
        resourceCount        = $safeModel.Inventory.Count
        edgeCount            = @($safeModel.Graph.edges).Count
        redactionEnabled     = (-not $NoRedact.IsPresent)
    }
    $safeModel.Manifest.tools = [pscustomobject]@{
        az         = (Get-ToolVersion 'az' 'version')
        aztfexport = (Get-ToolVersion 'aztfexport' '--version')
        terraform  = (Get-ToolVersion 'terraform' '-version')
        pwsh       = $PSVersionTable.PSVersion.ToString()
    }
    $safeModel.Manifest.errorsByArea = [pscustomobject]$errorsByArea

    if ($PSCmdlet.ShouldProcess("$runRoot/manifest.json", 'Write manifest')) {
        $safeModel.Manifest | ConvertTo-Json -Depth 32 | Set-Content "$runRoot/manifest.json" -Encoding utf8
    }

    # --- 9. HTML dashboard (always when diagrams ran; cheap + headline artifact) --
    if ($doDiagram -or $doReport) {
        New-HtmlDashboard -Model $safeModel -OutputPath "$runRoot/index.html"
    }

    # --- 10. Errors + index ---------------------------------------------------
    if ($PSCmdlet.ShouldProcess("$runRoot/errors.json", 'Write errors')) {
        $errors.ToArray() | ConvertTo-Json -Depth 16 | Set-Content "$runRoot/errors.json" -Encoding utf8
    }

    $index = @"
# Azure estate export — $stamp

- **Dashboard:** [``index.html``](index.html)
- Inventory: [``inventory.json``](inventory.json) ($($safeModel.Inventory.Count) resources)
- Graph: [``graph.json``](graph.json)
- Manifest (azure-id -> tf-address + collection confidence): [``manifest.json``](manifest.json)
- Errors: [``errors.json``](errors.json) ($($errors.Count))
- Report: [``report/report.md``](report/report.md)
- Diagrams: [``diagrams/``](diagrams/)
- Terraform baseline: [``terraform/``](terraform/)
- Deployable Terraform repo: [``terraform-repo/``](terraform-repo/) — clone, ``cd infra/<rg>``, ``terraform init``, run ``./bootstrap-import.ps1``, ``terraform plan``.

> Generated by azure-estate-exporter. Review before sharing.
"@
    if ($PSCmdlet.ShouldProcess("$runRoot/README.md", 'Write index')) {
        $index | Set-Content "$runRoot/README.md" -Encoding utf8
    }

    Write-EstateLog "Done. $($safeModel.Inventory.Count) resource(s), $($errors.Count) error(s). See $runRoot" -Level Success

    [pscustomobject]@{
        OutputPath    = (Resolve-Path $runRoot).Path
        ResourceCount = $safeModel.Inventory.Count
        Errors        = $errors.ToArray()
    }
}
