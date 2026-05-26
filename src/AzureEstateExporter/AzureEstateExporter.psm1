#Requires -Version 7.2

$ErrorActionPreference = 'Stop'

$privateRoot = Join-Path $PSScriptRoot 'Private'
$publicRoot  = Join-Path $PSScriptRoot 'Public'

# Dot-source private helpers first (collectors, model, renderers, util).
Get-ChildItem -Path $privateRoot -Recurse -Filter '*.ps1' -File |
    Sort-Object FullName |
    ForEach-Object { . $_.FullName }

# Then public surface.
Get-ChildItem -Path $publicRoot -Filter '*.ps1' -File |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function 'Export-AzureEstate', 'Compare-AzureEstateRun', 'New-AzureEstateTerraformRepo'
