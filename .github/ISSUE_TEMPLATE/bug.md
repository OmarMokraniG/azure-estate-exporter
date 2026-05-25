---
name: Bug report
about: Something went wrong while exporting
labels: bug
---

**Environment**

- OS:
- PowerShell version (`$PSVersionTable.PSVersion`):
- Azure CLI version (`az version`):
- Terraform version (`terraform -version`):
- `aztfexport` version (`aztfexport --version`):

**Scope used**

- `-SubscriptionId` / `-ResourceGroup` / `-TenantId` (please redact GUIDs as needed):

**Command run**

```powershell
Export-AzureEstate ...
```

**What I expected**

**What happened**

Attach (with secrets redacted) the relevant portion of `out/<timestamp>/errors.json` and any error message.
