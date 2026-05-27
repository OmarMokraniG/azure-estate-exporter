function New-AzureEstateTerraformRepo {
    <#
    .SYNOPSIS
        Packages an existing `Export-AzureEstate` output into a deployable
        Terraform baseline repository.

    .DESCRIPTION
        Standalone entry point so users can repackage an existing export folder
        (e.g. one they downloaded, or one produced earlier) without re-running
        `aztfexport`. Internally calls the same packager that `Export-AzureEstate`
        invokes after its Terraform phase.

        The generated repo is a *baseline*, not a perfect clone of the estate.
        See the README at the root of the output for what is and is not covered.

    .PARAMETER InputPath
        Path to an existing `Export-AzureEstate` output folder (one that
        contains a `terraform/` subdirectory with `<sub>/<rg>/main.tf` files).
        Defaults to the most recent `out/<timestamp>/` if not provided.

    .PARAMETER OutputPath
        Where to create the packaged repo. Defaults to
        `<InputPath>/terraform-repo/`.

    .PARAMETER InitGit
        Run `git init` (and `git commit -m "Initial export ..."` if git identity
        is configured) in the generated folder. Off by default.

    .PARAMETER RenameResources
        Rename the per-resource Terraform addresses from aztfexport`s default
        `res-0`, `res-1` style to meaningful names derived from the Azure
        resource name (sanitised to fit Terraform identifier rules).
        Rewrites `main.tf`, `outputs.tf`, `bootstrap-import.ps1` and
        `imports.md` consistently. Off by default — opt-in because the
        rewrite uses targeted regex on HCL.

    .PARAMETER Force
        Overwrite `OutputPath` if it already exists.

    .EXAMPLE
        New-AzureEstateTerraformRepo -InputPath ./out/2026-05-26T09-45-06

    .EXAMPLE
        # The "give me a customer-grade repo" form
        New-AzureEstateTerraformRepo -InputPath ./out/2026-05-26T09-45-06 `
            -OutputPath ./my-tf-repo -RenameResources -InitGit -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [switch]$InitGit,
        [switch]$RenameResources,
        [switch]$Force
    )

    if (-not $InputPath) {
        $candidates = Get-ChildItem -Path './out' -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'terraform') } |
            Sort-Object Name -Descending
        if (-not $candidates) {
            throw 'No -InputPath provided and no ./out/<timestamp>/terraform/ folder found.'
        }
        $InputPath = $candidates[0].FullName
        Write-EstateLog "Using most recent export: $InputPath" -Level Info
    }

    if (-not (Test-Path $InputPath)) {
        throw "InputPath '$InputPath' does not exist."
    }

    $terraformRoot = Join-Path $InputPath 'terraform'
    if (-not (Test-Path $terraformRoot)) {
        throw "InputPath '$InputPath' does not contain a 'terraform/' subdirectory. Run Export-AzureEstate first (without -InventoryOnly / -DiagramOnly)."
    }

    if (-not $OutputPath) {
        $OutputPath = Join-Path $InputPath 'terraform-repo'
    }

    if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Create Terraform repo package')) { return }

    # Surface the module version so the generated README is accurate.
    $version = (Get-Module AzureEstateExporter | Select-Object -First 1).Version.ToString()

    New-TerraformRepoPackage `
        -TerraformOutputRoot $terraformRoot `
        -RepoPath $OutputPath `
        -GeneratorVersion $version `
        -InitGit:$InitGit `
        -RenameResources:$RenameResources `
        -Force:$Force
}
