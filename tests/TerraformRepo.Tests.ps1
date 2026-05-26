#Requires -Version 7.2
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'AzureEstateExporter' 'AzureEstateExporter.psd1'
    Import-Module $modulePath -Force

    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' 'terraform-sample'
    $script:tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('aee-tfrepo-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:tmpRoot -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:tmpRoot) {
        Remove-Item -Path $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'New-AzureEstateTerraformRepo' {
    BeforeAll {
        # Reconstruct the canonical out/<timestamp>/terraform/<sub>/<rg>/ layout
        # the public cmdlet expects.
        $script:exportRoot = Join-Path $script:tmpRoot 'export'
        $script:terraformDest = Join-Path $script:exportRoot 'terraform'
        Copy-Item -Path $script:fixtureRoot -Destination $script:terraformDest -Recurse -Force
        $script:outputRepo = Join-Path $script:tmpRoot 'repo'
        $script:result = New-AzureEstateTerraformRepo `
            -InputPath $script:exportRoot `
            -OutputPath $script:outputRepo `
            -Force
    }

    It 'returns a summary object with the expected counts' {
        $script:result.exportedTotal | Should -Be 2
        $script:result.skippedTotal  | Should -Be 1
        $script:result.resourceGroups.Count | Should -Be 1
    }

    It 'creates the repo skeleton' {
        Test-Path (Join-Path $script:outputRepo 'README.md')              | Should -BeTrue
        Test-Path (Join-Path $script:outputRepo '.gitignore')             | Should -BeTrue
        Test-Path (Join-Path $script:outputRepo 'backend.tf.example')     | Should -BeTrue
        Test-Path (Join-Path $script:outputRepo 'docs/coverage.md')       | Should -BeTrue
        Test-Path (Join-Path $script:outputRepo 'infra/rg-sample/main.tf') | Should -BeTrue
    }

    It 'rewrites the provider subscription_id to a variable' {
        $provider = Get-Content (Join-Path $script:outputRepo 'infra/rg-sample/provider.tf') -Raw
        $provider | Should -Match 'subscription_id\s*=\s*var\.subscription_id'
        $provider | Should -Not -Match '"11111111-1111-1111-1111-111111111111"'
    }

    It 'removes the `backend "local" {}` block from terraform.tf' {
        $tf = Get-Content (Join-Path $script:outputRepo 'infra/rg-sample/terraform.tf') -Raw
        $tf | Should -Not -Match 'backend\s+"local"'
        $tf | Should -Match 'required_providers'
    }

    It 'generates a parseable bootstrap-import.ps1 with one Invoke-Import per mapped resource' {
        $bootstrapPath = Join-Path $script:outputRepo 'infra/rg-sample/bootstrap-import.ps1'
        Test-Path $bootstrapPath | Should -BeTrue
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
        $bootstrap = Get-Content $bootstrapPath -Raw
        ($bootstrap | Select-String -Pattern 'Invoke-Import\s+-Address' -AllMatches).Matches.Count | Should -Be 2
        $bootstrap | Should -Match "azurerm_resource_group\.res-0"
        $bootstrap | Should -Match "azurerm_storage_account\.res-1"
    }

    It 'generates a variables.tf that declares subscription_id' {
        $vars = Get-Content (Join-Path $script:outputRepo 'infra/rg-sample/variables.tf') -Raw
        $vars | Should -Match 'variable\s+"subscription_id"'
    }

    It 'generates a .tfvars.example file but no real .tfvars' {
        Test-Path (Join-Path $script:outputRepo 'infra/rg-sample/terraform.tfvars.example') | Should -BeTrue
        Test-Path (Join-Path $script:outputRepo 'infra/rg-sample/terraform.tfvars')         | Should -BeFalse
    }

    It 'preserves the .terraform.lock.hcl for reproducibility' {
        Test-Path (Join-Path $script:outputRepo 'infra/rg-sample/.terraform.lock.hcl') | Should -BeTrue
    }

    It 'gitignores tfstate, .terraform and tfvars (but NOT *.tfvars.example)' {
        $gi = Get-Content (Join-Path $script:outputRepo '.gitignore') -Raw
        $gi | Should -Match '\*\.tfstate'
        $gi | Should -Match '\.terraform/'
        $gi | Should -Match '\*\.tfvars'
        $gi | Should -Match '!\*\.tfvars\.example'
    }

    It 'aggregates skipped resources in docs/coverage.md' {
        $cov = Get-Content (Join-Path $script:outputRepo 'docs/coverage.md') -Raw
        $cov | Should -Match 'rg-sample'
        $cov | Should -Match 'storageAccounts/stsample0001'
    }

    It 'flags hardcoded source subscription IDs in the root README' {
        $readme = Get-Content (Join-Path $script:outputRepo 'README.md') -Raw
        $readme | Should -Match '11111111-1111-1111-1111-111111111111'
        $readme | Should -Match 'Heads up'
    }

    It 'fails without -Force when the output exists' {
        { New-AzureEstateTerraformRepo -InputPath $script:exportRoot -OutputPath $script:outputRepo } |
            Should -Throw
    }
}

Describe 'New-AzureEstateTerraformRepo edge cases' {
    It 'throws when -InputPath has no terraform/ subdirectory' {
        $empty = Join-Path $script:tmpRoot ('empty-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        { New-AzureEstateTerraformRepo -InputPath $empty -OutputPath (Join-Path $empty 'repo') } |
            Should -Throw -ExpectedMessage '*terraform*'
    }

    It 'is exposed by the module manifest' {
        (Get-Module AzureEstateExporter).ExportedFunctions.Keys | Should -Contain 'New-AzureEstateTerraformRepo'
    }
}
