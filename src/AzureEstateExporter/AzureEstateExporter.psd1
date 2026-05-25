@{
    RootModule        = 'AzureEstateExporter.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a4f4f6c8-3b3a-4b5a-9f4c-1d2e3f4a5b6c'
    Author            = 'Omar Mokrani and contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 azure-estate-exporter contributors. MIT licensed.'
    Description       = 'Inventory, diagram and Terraform-baseline any Azure tenant or subscription.'
    PowerShellVersion = '7.2'

    FunctionsToExport = @(
        'Export-AzureEstate'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Azure', 'Terraform', 'aztfexport', 'IaC', 'Inventory', 'Diagram', 'Mermaid', 'Excalidraw')
            LicenseUri   = 'https://github.com/OmarMokraniG/azure-estate-exporter/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/OmarMokraniG/azure-estate-exporter'
            ReleaseNotes = 'See CHANGELOG.md'
        }
    }
}
