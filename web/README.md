# azure-estate-exporter — web UI (v0.3)

Visual companion for the [azure-estate-exporter PowerShell module](../README.md).

Sign in with Entra, pick a tenant or subscription or resource group, and get:

- an interactive **resource map** (React Flow + heuristic edges + Azure-style icons),
- a sortable, filterable **resource table** with a JSON side panel,
- a one-click **Terraform CLI handoff** that runs `aztfexport` locally.

> **Position**: this is an _Azure resource discovery map_, not a hand-crafted
> reference architecture diagram. Auto-layout based on heuristic edges.

## Quick start

```bash
# 1. From the repo root, create your Entra app registration (one-off).
pwsh -File scripts/create-app-reg.ps1
# Copy the printed appId.

# 2. Configure the web app.
cd web
cp .env.example .env.local
#   Paste the appId into VITE_AZURE_CLIENT_ID

# 3. Install + run.
npm install
npm run dev
#   open http://localhost:5173
```

## How it works

```
Browser SPA  ──/api/arm/*──▶  Vite dev proxy  ──▶  https://management.azure.com
                                  (or SWA Function in prod)
```

We can't call ARM directly from the browser because the public Resource
Manager endpoint does **not** expose CORS for arbitrary origins. The Vite
dev server proxies `/api/arm/*` straight through to `management.azure.com`
preserving the user's Bearer token. In production the same path is served by
the Static Web Apps managed Function in `web/api/`.

The token itself is acquired by MSAL.js in the user's browser, scoped to
`https://management.azure.com/user_impersonation`. The proxy is a pure
passthrough — it neither mints nor stores tokens.

## Deploy your own

Use Azure Static Web Apps to host the SPA + ARM-proxy Function together:

```bash
# Create a Static Web App that builds from this repo
az staticwebapp create \
  --name aee-web \
  --resource-group <rg> \
  --location westeurope \
  --source https://github.com/<you>/azure-estate-exporter \
  --branch main \
  --app-location web \
  --api-location web/api \
  --output-location dist \
  --login-with-github
```

Add the redirect URI for your SWA hostname to the Entra app registration:

```powershell
pwsh -File scripts/create-app-reg.ps1 -RedirectUri 'https://<your-swa>.azurestaticapps.net'
```

Configure the build-time `VITE_AZURE_CLIENT_ID` env var on the SWA before
publishing.

## Architecture icons

This repo ships generic, open-source SVG placeholders under `public/icons/`.
They give each node a category color (compute green, network blue, security
red, etc.) and a shape hint, but they are **not** Microsoft's official Azure
icons.

To use the official icons locally:

```bash
npm run fetch-icons
```

…and follow the printed instructions. The icons are subject to Microsoft's
license terms and are not redistributed in this repo.

## Project layout

```
web/
├── api/                       # SWA Functions
│   └── src/functions/arm.js   # ARM passthrough proxy
├── public/icons/              # generic SVG placeholders
├── src/
│   ├── api/arm.ts             # ARM + ARG REST helpers
│   ├── auth/                  # MSAL config + token helper
│   ├── components/
│   │   ├── EstateView.tsx     # Tabs + side panel
│   │   ├── Login.tsx
│   │   ├── ScopePicker.tsx
│   │   ├── ResourceDetail.tsx
│   │   ├── icons/ResourceNode.tsx
│   │   └── tabs/{Diagram,Resources,Terraform}Tab.tsx
│   ├── lib/
│   │   ├── inferEdges.ts      # heuristic edge inference (port of PS)
│   │   ├── layout.ts          # dagre layout
│   │   └── resourceTypes.ts   # type → icon + category map
│   └── state/store.ts         # Zustand UI state
├── staticwebapp.config.json
└── vite.config.ts
```

## What's intentionally NOT here yet (v0.3.1)

- Policy assignments + compliance tab
- Per-resource ARM detail enrichment (we use ARG only for now)
- Compound VNet/subnet nodes
- Server-side aztfexport runner (today the Terraform tab just hands you a
  command to run locally)
