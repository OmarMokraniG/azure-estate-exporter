function New-TerraformRepoPackage {
    <#
    .SYNOPSIS
        Packages per-RG aztfexport outputs into a deployable Terraform "baseline"
        repository folder.

    .DESCRIPTION
        Post-processor (NOT a renderer in the strict sense — it consumes a previous
        renderer`s output, not the normalized model alone). Takes the per-RG
        `aztfexport` artifacts under `<TerraformOutputRoot>/<sub>/<rg>/` and
        produces a single repo-shaped folder you can clone, init and plan:

            <RepoPath>/
            +-- README.md                # how to use, what is and is not exported
            +-- .gitignore               # standard Terraform .gitignore (state, .terraform/, tfvars)
            +-- backend.tf.example       # Azure Storage backend template
            +-- docs/
            |   +-- coverage.md          # aggregated skipped resources across all RGs
            +-- infra/
                +-- <rg-name>/           # one self-contained Terraform working dir
                    +-- main.tf
                    +-- provider.tf      # rewritten: subscription_id via var
                    +-- terraform.tf     # rewritten: backend block removed (defaults to local)
                    +-- variables.tf
                    +-- terraform.tfvars.example
                    +-- .terraform.lock.hcl
                    +-- aztfexportResourceMapping.json
                    +-- aztfexportSkippedResources.txt   (only if present)
                    +-- bootstrap-import.ps1             # idempotent state bootstrapper
                    +-- imports.md                       # raw `terraform import ...` list
                    +-- README.md

        Honesty: the generated repo is a documentation-oriented BASELINE. It will
        not perfectly recreate the estate in a different tenant because:
          * `aztfexport --hcl-only` skips secrets, data-plane contents, some
            policy/role/diag edge cases and any provider gap.
          * `main.tf` may still embed the source subscription/tenant GUIDs or
            absolute resource IDs (e.g. a Key Vault reference). The package
            scans for these and surfaces warnings in the per-RG README.

    .PARAMETER TerraformOutputRoot
        The `<runRoot>/terraform/` folder produced by `Invoke-TerraformExport`.
        Must contain `<sub>/<rg>/` subdirectories with `main.tf` files.

    .PARAMETER RepoPath
        Destination folder for the packaged repo. Will be created.

    .PARAMETER GeneratorVersion
        Version string written into headers and README. Falls back to module version.

    .PARAMETER InitGit
        Run `git init && git add -A && git commit -m "Initial export"`. Only commits
        if a git identity is configured; otherwise leaves staged changes and warns.

    .PARAMETER Force
        Overwrite the destination if it already exists.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$TerraformOutputRoot,
        [Parameter(Mandatory)] [string]$RepoPath,
        [string]$GeneratorVersion,
        [switch]$InitGit,
        [switch]$Force
    )

    if (-not (Test-Path $TerraformOutputRoot)) {
        throw "TerraformOutputRoot '$TerraformOutputRoot' does not exist."
    }

    if (Test-Path $RepoPath) {
        if (-not $Force) {
            throw "RepoPath '$RepoPath' already exists. Pass -Force to overwrite."
        }
        if ($PSCmdlet.ShouldProcess($RepoPath, 'Remove existing repo folder')) {
            Remove-Item -Path $RepoPath -Recurse -Force
        }
    }

    if (-not $GeneratorVersion) {
        $mod = Get-Module AzureEstateExporter | Select-Object -First 1
        $GeneratorVersion = if ($mod) { $mod.Version.ToString() } else { 'dev' }
    }

    if (-not $PSCmdlet.ShouldProcess($RepoPath, 'Create Terraform repo package')) { return }

    # --- Discover per-RG aztfexport output folders --------------------------
    $rgDirs = Get-ChildItem -Path $TerraformOutputRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue } |
        Where-Object { Test-Path (Join-Path $_.FullName 'main.tf') }

    if (-not $rgDirs -or @($rgDirs).Count -eq 0) {
        Write-EstateLog "No usable aztfexport output under '$TerraformOutputRoot' (no main.tf found). Skipping repo package." -Level Warn
        return
    }

    New-Item -ItemType Directory -Path $RepoPath -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $RepoPath 'docs')  -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $RepoPath 'infra') -Force | Out-Null

    # Aggregate per-RG summaries for the root README + coverage doc
    $rgSummaries = New-Object System.Collections.Generic.List[pscustomobject]
    $hardcodedSubsAggregate = @{}

    foreach ($rgDir in $rgDirs) {
        $rgName = $rgDir.Name
        # Walk up one level to find the subscription folder
        $subId  = (Split-Path $rgDir.FullName -Parent | Split-Path -Leaf)
        $dest   = Join-Path $RepoPath "infra/$rgName"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null

        $rawMain      = Join-Path $rgDir.FullName 'main.tf'
        $rawProvider  = Join-Path $rgDir.FullName 'provider.tf'
        $rawTerraform = Join-Path $rgDir.FullName 'terraform.tf'
        $rawLock      = Join-Path $rgDir.FullName '.terraform.lock.hcl'
        $rawMapping   = Join-Path $rgDir.FullName 'aztfexportResourceMapping.json'
        $rawSkipped   = Join-Path $rgDir.FullName 'aztfexportSkippedResources.txt'

        # 1. Copy main.tf untouched (this is the actual HCL).
        Copy-Item -Path $rawMain -Destination (Join-Path $dest 'main.tf') -Force

        # 2. Rewrite provider.tf: replace hardcoded subscription_id with var.
        $providerHcl = if (Test-Path $rawProvider) { Get-Content $rawProvider -Raw } else { '' }
        $rewrittenProvider = $providerHcl -replace 'subscription_id\s*=\s*"[0-9a-fA-F-]{36}"', 'subscription_id                 = var.subscription_id'
        if (-not $rewrittenProvider) {
            $rewrittenProvider = @"
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
"@
        }
        Set-Content -Path (Join-Path $dest 'provider.tf') -Value $rewrittenProvider -Encoding utf8

        # 3. Rewrite terraform.tf: strip the `backend "local" {}` block so the
        #    repo defaults to local state but users can drop in their own backend.
        if (Test-Path $rawTerraform) {
            $tfBlock = Get-Content $rawTerraform -Raw
            # Remove `backend "local" {}` (with optional whitespace/newlines).
            $tfBlock = $tfBlock -replace '(?ms)\s*backend\s+"local"\s*\{\s*\}', ''
            Set-Content -Path (Join-Path $dest 'terraform.tf') -Value $tfBlock -Encoding utf8
        }

        # 4. Lock file: keep it for reproducibility.
        if (Test-Path $rawLock) { Copy-Item $rawLock (Join-Path $dest '.terraform.lock.hcl') -Force }

        # 5. Mapping + skipped: keep both for traceability.
        if (Test-Path $rawMapping) { Copy-Item $rawMapping (Join-Path $dest 'aztfexportResourceMapping.json') -Force }
        if (Test-Path $rawSkipped) { Copy-Item $rawSkipped (Join-Path $dest 'aztfexportSkippedResources.txt') -Force }

        # 6. variables.tf + terraform.tfvars.example
        @"
variable "subscription_id" {
  description = "Target Azure subscription ID. Set per-environment in terraform.tfvars."
  type        = string
}
"@ | Set-Content -Path (Join-Path $dest 'variables.tf') -Encoding utf8

        @"
# Copy this file to terraform.tfvars (gitignored) and fill in your values.
# Original source subscription was: $subId
subscription_id = "$subId"
"@ | Set-Content -Path (Join-Path $dest 'terraform.tfvars.example') -Encoding utf8

        # 6b. outputs.tf — meaningful output names per resource.
        # Generated from `aztfexportResourceMapping.json` so the user can
        # consume IDs of the imported resources in other Terraform repos.
        if ($mappingObj) {
            $outLines = New-Object System.Collections.Generic.List[string]
            $usedNames = New-Object System.Collections.Generic.HashSet[string]
            foreach ($azId in ($mappingObj.Keys | Sort-Object)) {
                $entry = $mappingObj[$azId]
                $tfType = $null; $tfName = $null
                if ($entry -is [string] -and $entry -match '^([^.]+)\.(.+)$') { $tfType = $Matches[1]; $tfName = $Matches[2] }
                elseif ($entry.ContainsKey('resource_type')) { $tfType = $entry.resource_type; $tfName = $entry.resource_name }
                if (-not $tfType -or -not $tfName) { continue }

                # Build a meaningful output identifier from the actual Azure
                # resource name (last segment of the ARM id). Terraform output
                # names must match [a-z_][a-z0-9_]*.
                $azName = ($azId -split '/')[-1]
                $base = ($azName.ToLower() -replace '[^a-z0-9]+', '_').Trim('_')
                if ([string]::IsNullOrEmpty($base) -or $base -match '^\d') { $base = "r_$base" }
                # Disambiguate (same name across two resource types).
                $candidate = $base
                $i = 2
                while ($usedNames.Contains($candidate)) {
                    $candidate = "${base}_$i"; $i++
                }
                [void]$usedNames.Add($candidate)

                $outLines.Add(@"
output "${candidate}_id" {
  description = "Azure resource ID for $azName ($tfType)."
  value       = $tfType.$tfName.id
}
"@)
            }
            if ($outLines.Count -gt 0) {
                $header = "# Generated by azure-estate-exporter. Per-resource outputs let other`n# Terraform repos consume IDs of resources imported in this folder.`n`n"
                $header + ($outLines -join "`n`n") | Set-Content -Path (Join-Path $dest 'outputs.tf') -Encoding utf8
            }
        }

        # 7. Scan main.tf for hardcoded subscription GUIDs (warn in per-RG README).
        $mainContent = Get-Content (Join-Path $dest 'main.tf') -Raw -ErrorAction SilentlyContinue
        $foundSubs = @()
        if ($mainContent) {
            $foundSubs = [regex]::Matches($mainContent, '/subscriptions/([0-9a-fA-F-]{36})/') |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
        }
        foreach ($s in $foundSubs) { $hardcodedSubsAggregate[$s] = $true }

        # 8. Generate bootstrap-import.ps1 + imports.md from the mapping file.
        $importedCount = 0
        $skippedCount  = 0
        $mappingObj    = $null
        if (Test-Path $rawMapping) {
            try {
                $mappingObj = Get-Content $rawMapping -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            } catch {
                $mappingObj = $null
                Write-EstateLog "Could not parse mapping file for '$rgName': $($_.Exception.Message)" -Level Warn
            }
        }
        if ($mappingObj) {
            $importedCount = $mappingObj.Keys.Count
            $importLines     = New-Object System.Collections.Generic.List[string]
            $bootstrapLines  = New-Object System.Collections.Generic.List[string]
            foreach ($azId in ($mappingObj.Keys | Sort-Object)) {
                $entry = $mappingObj[$azId]
                # aztfexport mapping schema: { "<az-id>": { "resource_type": "...", "resource_name": "...", "resource_id": "<az-id>" } }
                # or older: { "<az-id>": "<resource_type.resource_name>" }
                $tfAddr = if ($entry -is [string]) { $entry }
                          elseif ($entry.ContainsKey('resource_type') -and $entry.ContainsKey('resource_name')) { "$($entry.resource_type).$($entry.resource_name)" }
                          else { $null }
                if (-not $tfAddr) { continue }
                $importLines.Add(("terraform import '{0}' '{1}'" -f $tfAddr, $azId))
                $bootstrapLines.Add(("Invoke-Import -Address '{0}' -AzureId '{1}'" -f $tfAddr.Replace("'", "''"), $azId.Replace("'", "''")))
            }
        }
        if (Test-Path $rawSkipped) {
            $skippedCount = @(Get-Content $rawSkipped | Where-Object { $_ -match '/subscriptions/' }).Count
        }

        $bootstrapBody = if ($mappingObj) { ($bootstrapLines | ForEach-Object { "    $_" }) -join "`n" } else { '    # (no mapping file found)' }
        $bootstrapTemplate = @'
#Requires -Version 7.2
<#
.SYNOPSIS
    Imports every aztfexport-mapped resource into local Terraform state.
.DESCRIPTION
    Use this when you cloned the repo and want `terraform plan` to show NO
    changes against the existing Azure estate. Runs `terraform import` once per
    resource and tolerates per-resource failures (logs them, continues).

    First run, in this folder:
        terraform init
        ./bootstrap-import.ps1 -WhatIf      # dry run
        ./bootstrap-import.ps1              # actually import
        terraform plan                      # should show: No changes.

    Generated by azure-estate-exporter __VERSION__ on __TIMESTAMP__.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    throw 'terraform CLI not found on PATH. Install from https://developer.hashicorp.com/terraform/install.'
}

if (-not (Test-Path '.terraform')) {
    Write-Host '> terraform init' -ForegroundColor Cyan
    & terraform init
    if ($LASTEXITCODE -ne 0) { throw 'terraform init failed.' }
}

$script:succeeded = 0
$script:failed    = New-Object System.Collections.Generic.List[pscustomobject]
$script:skipped   = 0
$script:stateList = @(& terraform state list 2>$null)

function Invoke-Import {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Address, [Parameter(Mandatory)][string]$AzureId)

    if ($script:stateList -contains $Address) {
        Write-Host "[skip] $Address (already in state)" -ForegroundColor DarkGray
        $script:skipped++
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Address, "terraform import $AzureId")) { return }

    & terraform import -input=false $Address $AzureId 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -eq 0) {
        $script:succeeded++
        Write-Host "[ok] $Address" -ForegroundColor Green
    } else {
        $script:failed.Add([pscustomobject]@{ address = $Address; azureId = $AzureId; exit = $LASTEXITCODE })
        Write-Host "[fail] $Address (exit $LASTEXITCODE)" -ForegroundColor Red
    }
}

# --- Import block (auto-generated) ----------------------------------------
__BODY__
# --------------------------------------------------------------------------

Write-Host ''
Write-Host "Done. Imported: $script:succeeded, skipped: $script:skipped, failed: $($script:failed.Count)" -ForegroundColor Cyan
if ($script:failed.Count) {
    Write-Host 'Failed imports (re-run after fixing or remove the resource from main.tf):' -ForegroundColor Yellow
    $script:failed | Format-Table -AutoSize
    exit 1
}
'@
        $bootstrapScript = $bootstrapTemplate.
            Replace('__VERSION__',   $GeneratorVersion).
            Replace('__TIMESTAMP__', (Get-Date -Format 'o')).
            Replace('__BODY__',      $bootstrapBody)
        Set-Content -Path (Join-Path $dest 'bootstrap-import.ps1') -Value $bootstrapScript -Encoding utf8

        if ($importLines.Count -gt 0) {
            @"
# Terraform imports for ``$rgName``

If you cannot run the PowerShell ``bootstrap-import.ps1`` script (e.g. you only
have ``bash``), here is the raw list of ``terraform import`` commands. Run them
one at a time, or pipe to a shell script.

``````bash
$($importLines -join "`n")
``````
"@ | Set-Content -Path (Join-Path $dest 'imports.md') -Encoding utf8
        }

        # 9. Per-RG README
        $foundSubsBlock = if ($foundSubs.Count -gt 1) {
            "`n> WARNING: ``main.tf`` references **$($foundSubs.Count) distinct subscription GUIDs**. The provider`s ``subscription_id`` is parameterised, but cross-subscription resource IDs in HCL are NOT rewritten. Review before deploying to a different target.`n"
        } elseif ($foundSubs.Count -eq 1 -and $foundSubs[0] -ne $subId) {
            "`n> WARNING: ``main.tf`` references subscription ``$($foundSubs[0])`` which differs from the export source ``$subId``. Review before deploying.`n"
        } else { '' }

        $skippedBlock = if ($skippedCount -gt 0) {
            "`n## Resources that were NOT exported`n`n``$skippedCount`` resource(s) in this RG could not be translated by ``aztfexport``. See ``aztfexportSkippedResources.txt`` for the full list. You will need to author HCL for them by hand or use ``terraform import`` against a manual block.`n"
        } else { '' }

        @"
# ``$rgName``

Source subscription: ``$subId``
Resources mapped: $importedCount
Resources skipped: $skippedCount
$foundSubsBlock
## Use

``````powershell
# 1. point provider at your target subscription
Copy-Item terraform.tfvars.example terraform.tfvars
#    edit subscription_id

# 2. init + import existing resources into state
terraform init
./bootstrap-import.ps1 -WhatIf   # dry run first
./bootstrap-import.ps1

# 3. should now show: No changes.
terraform plan
``````
$skippedBlock
"@ | Set-Content -Path (Join-Path $dest 'README.md') -Encoding utf8

        # Track summary for root files
        $rgSummaries.Add([pscustomobject]@{
            name              = $rgName
            sourceSubscription = $subId
            exported          = $importedCount
            skipped           = $skippedCount
            hardcodedSubs     = $foundSubs
        })
    }

    # --- Root files ---------------------------------------------------------
    $totalExported = ($rgSummaries | Measure-Object -Property exported -Sum).Sum
    $totalSkipped  = ($rgSummaries | Measure-Object -Property skipped  -Sum).Sum
    $sourceSubs    = $rgSummaries | Select-Object -ExpandProperty sourceSubscription -Unique

    @'
# Local state (do not commit)
*.tfstate
*.tfstate.*
*.tfstate.backup
.terraform/
crash.log
crash.*.log

# Variable files with secrets — keep `.example` files committed
*.tfvars
!*.tfvars.example

# OS / editor noise
.DS_Store
Thumbs.db
.vscode/
.idea/
'@ | Set-Content -Path (Join-Path $RepoPath '.gitignore') -Encoding utf8

    @'
# Drop your remote backend here. Example for Azure Storage:
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-tfstate"
#     storage_account_name = "sttfstate0001"
#     container_name       = "tfstate"
#     key                  = "azure-estate-exporter/<rg-name>.tfstate"
#   }
# }
#
# Copy this file to each `infra/<rg>/` folder as `backend.tf` and run
# `terraform init -migrate-state`.
'@ | Set-Content -Path (Join-Path $RepoPath 'backend.tf.example') -Encoding utf8

    # Aggregated coverage doc
    $skippedLines = New-Object System.Collections.Generic.List[string]
    foreach ($s in $rgSummaries | Where-Object { $_.skipped -gt 0 }) {
        $skippedFile = Join-Path $RepoPath "infra/$($s.name)/aztfexportSkippedResources.txt"
        if (Test-Path $skippedFile) {
            $skippedLines.Add("`n## ``$($s.name)`` ($($s.skipped) skipped)`n")
            Get-Content $skippedFile | ForEach-Object {
                $line = ($_ -replace '^\s*-\s*', '').Trim()
                if ($line -like '/subscriptions/*') { $skippedLines.Add("- ``$line``") }
            }
        }
    }
    $skippedBody = if ($skippedLines.Count -gt 0) { $skippedLines -join "`n" } else { '_No resources were skipped — every resource in the source estate was translated to HCL._' }

    @"
# Terraform export coverage

Generated by **azure-estate-exporter $GeneratorVersion** from ``aztfexport`` output.

- Total exported resources: **$totalExported**
- Total skipped resources:  **$totalSkipped**
- Resource groups packaged: **$($rgSummaries.Count)**

## What ``aztfexport`` does NOT cover

Even when an export succeeds, the following are **never** part of the generated
HCL and you must add them manually if you need a faithful clone of the estate:

- **Secrets and key material** (Key Vault contents, storage account keys, app
  settings flagged as secret, automatically generated passwords).
- **Data-plane contents** (blob/file contents, queue messages, Cosmos DB data,
  SQL database rows, container images in ACR).
- **Runtime configuration** of compute resources (VM disk contents beyond OS
  reference, AKS cluster workloads, App Service app code).
- **Generated values** like managed identity client IDs of resources that did
  not exist before apply — Terraform will mint new ones on apply.
- **Resource types unsupported by aztfexport** for the version we used. See
  the per-RG breakdown below and ``aztfexportSkippedResources.txt`` files.

## Skipped resources (per resource group)
$skippedBody
"@ | Set-Content -Path (Join-Path $RepoPath 'docs/coverage.md') -Encoding utf8

    # Hardcoded source-subscription warning for the root README
    $sourceSubsWarning = if (@($hardcodedSubsAggregate.Keys).Count -gt 0) {
        $list = ($hardcodedSubsAggregate.Keys | ForEach-Object { "> - ``$_``" }) -join "`n"
        @"

> **Heads up — hardcoded resource IDs.** The packaged HCL still references the
> source subscription(s):
>
$list
>
> The ``provider`` block is parameterised through ``var.subscription_id`` but
> ARM resource IDs embedded in ``main.tf`` (e.g. Key Vault, subnet, log workspace
> references) are NOT rewritten. If you deploy to a different subscription you
> must edit those manually. See ``docs/coverage.md`` for more.

"@
    } else { '' }

    $rgTable = ($rgSummaries | Sort-Object name | ForEach-Object {
        "| ``$($_.name)`` | $($_.exported) | $($_.skipped) | ``$($_.sourceSubscription)`` |"
    }) -join "`n"

    @"
# Terraform baseline — generated by azure-estate-exporter $GeneratorVersion

> **Baseline, not a clone.** This repository is a documentation-oriented
> Terraform baseline of an Azure estate, exported by [``aztfexport``](https://github.com/Azure/aztfexport).
> Review every resource before running ``terraform apply``.

## What is in here

| Resource group | Exported | Skipped | Source sub |
|----------------|---------:|--------:|------------|
$rgTable

Each ``infra/<rg>/`` folder is a **self-contained Terraform working
directory**: own state, own ``terraform init``, no cross-RG dependencies in
HCL. There is no estate-wide ``terraform apply``.

## Quick start (one RG)

``````powershell
cd infra/<rg-name>

# 1. Point the provider at your target subscription
Copy-Item terraform.tfvars.example terraform.tfvars
#    Edit subscription_id

# 2. Initialise + import existing resources into local state
terraform init
./bootstrap-import.ps1 -WhatIf   # dry run, no changes
./bootstrap-import.ps1           # imports each resource

# 3. terraform plan should now say: No changes.
terraform plan
``````

## Remote backend (recommended for teams)

The repo ships with no active backend block, so Terraform defaults to local
state. To use Azure Storage instead, copy ``backend.tf.example`` into each
``infra/<rg>/`` folder as ``backend.tf``, edit, then run
``terraform init -migrate-state``.

## What this baseline is NOT
$sourceSubsWarning
- Not a full IaC replica — see [``docs/coverage.md``](docs/coverage.md) for
  what is intentionally out of scope (secrets, data plane, runtime config,
  unsupported resource types).
- Not parameterised beyond ``subscription_id``. Region, naming, tags etc. are
  baked in.
- Not multi-RG. Cross-RG references in HCL would break the per-RG isolation;
  ``aztfexport`` does not produce them by default.

## Reproducing this output

This repo was generated from an [``azure-estate-exporter``](https://github.com/OmarMokraniG/azure-estate-exporter)
run. To regenerate from a fresh Azure read:

``````powershell
Import-Module azure-estate-exporter
Export-AzureEstate -SubscriptionId <guid> -ResourceGroup <rg>
#    -> out/<timestamp>/terraform-repo/  (this folder)
``````

## License

The HCL itself describes your infrastructure and belongs to you. The scaffolding
files (this README, ``.gitignore``, ``bootstrap-import.ps1`` template, etc.)
are MIT-licensed by ``azure-estate-exporter``.
"@ | Set-Content -Path (Join-Path $RepoPath 'README.md') -Encoding utf8

    # --- Optional git init -------------------------------------------------
    if ($InitGit) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-EstateLog 'git not found on PATH; skipping -InitGit.' -Level Warn
        } else {
            Push-Location $RepoPath
            try {
                & git init -q
                & git add -A
                $hasIdentity = (& git config user.name 2>$null) -and (& git config user.email 2>$null)
                if (-not $hasIdentity) {
                    Write-EstateLog 'git user.name / user.email not configured; staged files but skipped commit.' -Level Warn
                } else {
                    & git commit -q -m "Initial export from azure-estate-exporter $GeneratorVersion"
                    Write-EstateLog "git repo initialised at $RepoPath" -Level Success
                }
            } finally { Pop-Location }
        }
    }

    Write-EstateLog ("Terraform repo packaged: {0} ({1} RG(s), {2} exported, {3} skipped)" -f $RepoPath, $rgSummaries.Count, $totalExported, $totalSkipped) -Level Success
    return [pscustomobject]@{
        repoPath        = $RepoPath
        resourceGroups  = $rgSummaries
        exportedTotal   = $totalExported
        skippedTotal    = $totalSkipped
        sourceSubs      = @($sourceSubs)
        hardcodedSubs   = @($hardcodedSubsAggregate.Keys)
    }
}
