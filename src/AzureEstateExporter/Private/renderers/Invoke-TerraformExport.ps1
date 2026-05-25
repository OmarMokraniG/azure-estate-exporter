function Invoke-TerraformExport {
    <#
    .SYNOPSIS
        Wraps `aztfexport` to produce a Terraform HCL baseline of the existing estate.
    .DESCRIPTION
        Iterates the inventory grouped by (subscription, resource group) and
        runs `aztfexport resource-group --hcl-only` once per RG. We never run
        `aztfexport subscription` directly because it scales poorly for
        non-trivial subs and is harder to recover from when it fails.

        The wrapper is deliberately tolerant:
          * Missing `aztfexport` -> print install hint and return, do not crash.
          * Per-RG failure -> append to Errors and continue with the next RG.
          * Default mode is --hcl-only (no state imported).
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

    $groups = $Model.Inventory | Group-Object subscriptionId, resourceGroup
    Write-EstateLog "aztfexport will run for $($groups.Count) resource group(s)" -Level Info

    foreach ($g in $groups) {
        $parts = $g.Name -split ', '
        $subId = $parts[0]
        $rg    = $parts[1]
        if (-not $rg) { continue }

        $dest = Join-Path $OutputRoot ("$subId/$rg")
        if (-not $PSCmdlet.ShouldProcess($dest, "aztfexport resource-group $rg")) { continue }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        $argv = @(
            'resource-group',
            $rg,
            '--subscription-id', $subId,
            '--output-dir', $dest,
            '--non-interactive',
            '--continue'      # don't bail on a single resource-level failure
        )
        if (-not $WithImport) { $argv += '--hcl-only' }

        Write-EstateLog "aztfexport $($argv -join ' ')" -Level Verbose

        try {
            & aztfexport @argv 2>&1 | ForEach-Object { Write-Verbose $_ }
            if ($LASTEXITCODE -ne 0) {
                throw "aztfexport exit $LASTEXITCODE"
            }
            Write-EstateLog "Terraform baseline written: $dest" -Level Success
        }
        catch {
            Write-EstateLog "aztfexport failed for $rg : $($_.Exception.Message)" -Level Error
            [void]$Errors.Add([pscustomobject]@{
                area  = 'terraform'
                scope = "/subscriptions/$subId/resourceGroups/$rg"
                error = $_.Exception.Message
            })
        }
    }
}
