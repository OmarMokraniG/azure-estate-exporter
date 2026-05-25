# Security policy

## What this tool reads from Azure

`azure-estate-exporter` calls the **Azure Resource Manager** and **Resource Graph** APIs read-only using the credentials of the principal that ran `az login`. It does **not** write to Azure, does **not** read data-plane secrets (Key Vault values, Storage keys, etc.) and does **not** transmit data anywhere outside the machine that runs it.

When invoked with the Terraform exporter, [`aztfexport`](https://github.com/Azure/aztfexport) may need slightly broader read permissions to introspect provider-specific properties. See [`docs/permissions.md`](docs/permissions.md) for the role matrix.

## What the generated artifacts contain

The output under `out/` may include:

- Resource names, IDs, locations, SKUs, tags.
- Diagnostic settings and role assignment **identifiers** (not key material).
- Terraform HCL referencing those identifiers.

By default, the tool **redacts** any property whose key or value matches the patterns `password|secret|connectionString|key|sas|token|certificate|clientSecret` before writing to disk. The `-NoRedact` switch disables redaction and prints a clear warning.

Even with redaction, treat `out/` as potentially confidential. The default `.gitignore` excludes it.

## Reporting a vulnerability

If you find a security issue (e.g. a secret leak in generated artifacts, or a way to exfiltrate credentials), please **do not open a public issue**. Instead:

1. Open a private GitHub security advisory on this repository, or
2. Email the maintainer listed in the repo's GitHub profile.

We will respond within 5 business days.
