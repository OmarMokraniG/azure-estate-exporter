#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Creates the Entra app registration used by azure-estate-exporter's web UI.

.DESCRIPTION
    Run this once per tenant you want to be able to sign in to the web app.
    It produces an SPA app registration with the right redirect URIs and the
    delegated Azure Service Management permission (`user_impersonation`).

    The script PRINTS the client id at the end. Paste it into
    `web/.env.local`:
        VITE_AZURE_CLIENT_ID=<your-client-id>

.PARAMETER DisplayName
    The Entra display name. Default: 'Azure Estate Exporter (web)'.

.PARAMETER RedirectUri
    Extra SPA redirect URI(s) to register in addition to
    `http://localhost:5173`. Use this to add your deployed SWA URL.
#>
[CmdletBinding()]
param(
    [string]$DisplayName = 'Azure Estate Exporter (web)',
    [string[]]$RedirectUri = @()
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required. Install from https://aka.ms/azurecli.'
}

$account = az account show --query "{tenantId:tenantId,userName:user.name}" -o json | ConvertFrom-Json
if (-not $account) { throw 'You are not signed in. Run `az login` first.' }
Write-Host "Signed in as $($account.userName) on tenant $($account.tenantId)" -ForegroundColor Cyan

$redirects = @('http://localhost:5173') + $RedirectUri | Select-Object -Unique

Write-Host "Creating app registration '$DisplayName'..." -ForegroundColor Cyan
$created = az ad app create `
    --display-name $DisplayName `
    --sign-in-audience AzureADMultipleOrgs `
    --enable-id-token-issuance true `
    --enable-access-token-issuance false `
    -o json | ConvertFrom-Json

$appId = $created.appId
Write-Host "  appId: $appId" -ForegroundColor Green

# Configure the SPA platform with our redirect URIs (az CLI doesn't expose this
# cleanly, so we PATCH via the Microsoft Graph endpoint).
#
# NOTE: on Windows PowerShell, `az rest --body '<inline JSON>'` strips the
# Content-Type header and the Graph API rejects the payload as malformed.
# Writing the body to a temp file and referencing it with `@path` avoids
# the issue on all platforms.
$spa = @{ spa = @{ redirectUris = $redirects } } | ConvertTo-Json -Compress -Depth 5
$bodyFile = New-TemporaryFile
try {
    Set-Content -Path $bodyFile.FullName -Value $spa -Encoding ascii -NoNewline
    az rest --method PATCH `
        --uri "https://graph.microsoft.com/v1.0/applications/$($created.id)" `
        --headers 'Content-Type=application/json' `
        --body "@$($bodyFile.FullName)" | Out-Null
}
finally {
    Remove-Item -Path $bodyFile.FullName -ErrorAction SilentlyContinue
}
Write-Host "  redirect URIs: $($redirects -join ', ')" -ForegroundColor Green

# Add delegated permission: Azure Service Management → user_impersonation
# Well-known IDs:
#   ARM resource id    : 797f4846-ba00-4fd7-ba43-dac1f8f63013
#   user_impersonation : 41094075-9dad-400e-a0bd-54e686782033 (scope, type=Scope)
az ad app permission add `
    --id $appId `
    --api 797f4846-ba00-4fd7-ba43-dac1f8f63013 `
    --api-permissions '41094075-9dad-400e-a0bd-54e686782033=Scope' | Out-Null
Write-Host "  delegated permission: ARM/user_impersonation" -ForegroundColor Green

Write-Host ''
Write-Host '----------------------------------------------------------------' -ForegroundColor Yellow
Write-Host 'Done. Next steps:' -ForegroundColor Yellow
Write-Host "  1. Add this to web/.env.local:"
Write-Host "       VITE_AZURE_CLIENT_ID=$appId"
Write-Host '  2. From the repo root:  cd web; npm install; npm run dev'
Write-Host '  3. In your tenant a user (or admin) will be prompted to consent'
Write-Host '     the first time they sign in. For locked-down tenants run:'
Write-Host "       az ad app permission admin-consent --id $appId"
Write-Host '----------------------------------------------------------------' -ForegroundColor Yellow

[pscustomobject]@{ appId = $appId; tenantId = $account.tenantId; redirectUris = $redirects }
