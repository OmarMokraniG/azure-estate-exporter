# Permissions

`azure-estate-exporter` does not need write access to Azure for any of its default modes. It does need to be able to **read** the resources you want to export.

## Quick rule of thumb

| Mode | Minimum role | Where |
|------|--------------|-------|
| `-InventoryOnly` | **Reader** | On every subscription / RG in scope. |
| `-DiagramOnly` | **Reader** | Same. |
| `-TerraformOnly` (default `--hcl-only`) | **Reader** | Same — `aztfexport --hcl-only` does not import to state. |
| `-TerraformOnly -WithImport` | **Reader** | Same; the local `terraform.tfstate` is written to disk on your machine, not in Azure. |

For tenant-wide runs (`-TenantId`), assign **Reader at the root management group** or at each subscription you want covered.

## What about role assignments, locks, policies?

The supplemental ARM collector that pulls those calls:

- `az role assignment list --all` — requires `Microsoft.Authorization/roleAssignments/read` (included in **Reader**).
- `az lock list` — requires `Microsoft.Authorization/locks/read` (included in **Reader**).
- `az policy assignment list` — requires `Microsoft.Authorization/policyAssignments/read` (included in **Reader**).

If your principal has Reader on every scope and any of those calls still fails, it will be logged to `errors.json` and the rest of the run continues.

## Data-plane reads

The tool does **not** read data-plane secrets:

- It does **not** fetch Key Vault secret values.
- It does **not** fetch Storage Account keys.
- It does **not** fetch App Service `connection strings` (their *names* may appear in `properties`, but values are redacted).

If a future renderer ever needs data-plane read, it will be opt-in and documented here.

## CI / federated identity

The recommended pattern for running this in CI is:

1. Create an Entra ID app registration.
2. Configure GitHub Actions OIDC federation (no client secret).
3. Assign **Reader** on the target subscription / MG.
4. In the workflow: `az login --service-principal --federated-token "$ID_TOKEN" --tenant <tid>`.
5. Run `Export-AzureEstate`.

See the sibling project `labMicroHackOmarSQL/scripts/bootstrap-oidc.ps1` for a working example.
