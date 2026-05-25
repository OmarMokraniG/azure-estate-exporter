function Invoke-TerraformExport {
    <#
    .SYNOPSIS
        Wraps `aztfexport` to produce a Terraform HCL baseline of the existing estate.
    .DESCRIPTION
        Iterates the inventory grouped by (subscription, resource group) and
        runs `aztfexport resource-group --hcl-only <RG>` once per RG. We never
        run `aztfexport subscription` directly because it scales poorly for
        non-trivial subs and is harder to recover from when it fails.

        The wrapper is deliberately tolerant:
          * Missing `aztfexport` -> print install hint and return, do not crash.
          * Per-RG failure -> append to Errors and continue with the next RG.
          * Default mode is --hcl-only (no state imported).
          * Resolves the canonical resource group name (with original casing)
            via `az group show`. aztfexport's internal ARG predicate is case-
            sensitive, so passing the ARG-lowercased name silently returns
            "no resource found".
          * Parses `aztfexportSkippedResources.txt` after each run and emits a
            per-RG `tf-report.json` so downstream tools can see what was
            skipped vs. exported without grepping logs.
    .PARAMETER Model
        The normalized estate model.
    .PARAMETER OutputRoot
        Folder where per-RG HCL subfolders will be created.
    .PARAMETER WithImport
        When set, drops --hcl-only and lets aztfexport import resources into
        a local terraform.tfstate inside each per-RG folder. Off by default.
    .PARAMETER Errors
        ArrayList for per-RG failure objects.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Model,
        [Parameter(Mandatory)] [string]$OutputRoot,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.ArrayList]$Errors,
        [switch]$WithImport
    )

    $aztf = Get-Command aztfexport -ErrorAction SilentlyContinue
    if (-not $aztf) {
        Write-EstateLog 'aztfexport not found on PATH. Install with one of:' -Level Warn
        Write-EstateLog '  winget install Microsoft.Azure.aztfexport' -Level Warn
        Write-EstateLog '  brew install aztfexport' -Level Warn
        Write-EstateLog '  go install github.com/Azure/aztfexport@latest' -Level Warn
        Write-EstateLog 'Skipping Terraform export.' -Level Warn
        [void]$Errors.Add([pscustomobject]@{ area = 'terraform'; scope = '*'; error = 'aztfexport not installed' })
        return
    }

    # Capture version once for tf-report.json files.
    $versionLine = (& aztfexport --version 2>&1 | Select-Object -First 1)

    # @(...) forces array semantics even when only one group survives, otherwise
    # $groups.Count returns the single group's item count instead of 1.
    $groups = @($Model.Inventory | Group-Object subscriptionId, resourceGroup)
    Write-EstateLog "aztfexport will run for $($groups.Count) resource group(s)" -Level Info

    foreach ($g in $groups) {
        $parts = $g.Name -split ', '
        $subId = $parts[0]
        $rg    = $parts[1]
        if (-not $rg) { continue }

        # Resolve the canonical RG name (correct casing) — aztfexport is case-sensitive.
        $canonicalRg = $rg
        try {
            $canonicalRg = (& az group show --name $rg --subscription $subId --query name -o tsv 2>$null).Trim()
            if (-not $canonicalRg) { $canonicalRg = $rg }
        }
        catch {
            Write-EstateLog "Could not resolve canonical RG name for '$rg'; using ARG-normalised value." -Level Warn
            $canonicalRg = $rg
        }
        if ($canonicalRg -cne $rg) {
            Write-EstateLog "Resolved RG case: '$rg' -> '$canonicalRg'" -Level Verbose
        }

        $dest = Join-Path $OutputRoot ("$subId/$canonicalRg")
        if (-not $PSCmdlet.ShouldProcess($dest, "aztfexport resource-group $canonicalRg")) { continue }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        $argv = @(
            'resource-group',
            '--subscription-id', $subId,
            '--output-dir', $dest,
            '--non-interactive',
            '--plain-ui',
            '--continue',
            '--use-azure-cli-cred'
        )
        if (-not $WithImport) { $argv += '--hcl-only' }
        # Positional <resource-group> MUST come last in aztfexport's CLI; earlier
        # positions are treated as flags and skipped silently.
        $argv += $canonicalRg

        Write-EstateLog "aztfexport $($argv -join ' ')" -Level Verbose

        $report = [pscustomobject]@{
            subscriptionId       = $subId
            resourceGroup        = $canonicalRg
            tool                 = 'aztfexport'
            toolVersion          = $versionLine
            mode                 = if ($WithImport) { 'import' } else { 'hcl-only' }
            exitCode             = $null
            success              = $false
            exportedResources    = 0
            unsupportedResources = @()
            stderrTail           = $null
        }

        try {
            $stderr = [System.Collections.ArrayList]::new()
            & aztfexport @argv 2>&1 | ForEach-Object {
                Write-Verbose $_
                if ($_ -is [System.Management.Automation.ErrorRecord] -or "$_" -match '^(Error|level=(ERROR|WARN))') {
                    [void]$stderr.Add("$_")
                }
            }
            $report.exitCode = $LASTEXITCODE
            if ($LASTEXITCODE -ne 0) {
                $report.stderrTail = ($stderr | Select-Object -Last 8) -join "`n"
                throw "aztfexport exit $LASTEXITCODE"
            }

            # Parse aztfexport mapping + skipped files for a structured summary.
            $mappingFile = Join-Path $dest 'aztfexportResourceMapping.json'
            $skippedFile = Join-Path $dest 'aztfexportSkippedResources.txt'
            if (Test-Path $mappingFile) {
                $mapping = Get-Content $mappingFile -Raw | ConvertFrom-Json
                if ($mapping -is [System.Collections.IDictionary]) {
                    $report.exportedResources = $mapping.Keys.Count
                } else {
                    $report.exportedResources = ($mapping.PSObject.Properties | Measure-Object).Count
                }
            }
            if (Test-Path $skippedFile) {
                # Format: lines look like "- /subscriptions/..." (markdown bullet).
                # Older aztfexport versions used plain "/subscriptions/..." lines, so accept both.
                $report.unsupportedResources = @(
                    Get-Content $skippedFile |
                        ForEach-Object { ($_ -replace '^\s*-\s*', '').Trim() } |
                        Where-Object { $_ -like '/subscriptions/*' } |
                        Sort-Object -Unique
                )
            }
            $report.success = $true

            $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $dest 'tf-report.json') -Encoding utf8
            Write-EstateLog ("Terraform baseline written: {0} ({1} exported, {2} unsupported)" -f $dest, $report.exportedResources, $report.unsupportedResources.Count) -Level Success
        }
        catch {
            Write-EstateLog "aztfexport failed for $canonicalRg : $($_.Exception.Message)" -Level Error
            $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $dest 'tf-report.json') -Encoding utf8
            [void]$Errors.Add([pscustomobject]@{
                area       = 'terraform'
                scope      = "/subscriptions/$subId/resourceGroups/$canonicalRg"
                error      = $_.Exception.Message
                stderrTail = $report.stderrTail
            })
        }
    }
}
