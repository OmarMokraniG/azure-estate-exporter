import { Configuration, PublicClientApplication, LogLevel } from '@azure/msal-browser';

// Bring-your-own Entra app registration.
// 1. Create a Single-Page Application registration in your tenant
//    (or run `scripts/create-app-reg.ps1` at the repo root).
// 2. Add redirect URIs `http://localhost:5173` (dev) and your SWA URL (prod).
// 3. Under "API permissions", add delegated permission:
//      Azure Service Management → user_impersonation
// 4. Set the client id below via Vite env var `VITE_AZURE_CLIENT_ID`.
//    Use a `.env.local` file (gitignored) — never commit your client id.
const clientId = import.meta.env.VITE_AZURE_CLIENT_ID ?? '';

// `common` lets users from any Entra tenant sign in. Override with a specific
// tenant id (`VITE_AZURE_TENANT_ID`) to lock the app down to one organization.
const tenant = import.meta.env.VITE_AZURE_TENANT_ID ?? 'common';

export const msalConfig: Configuration = {
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenant}`,
    redirectUri: window.location.origin,
    postLogoutRedirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
  system: {
    loggerOptions: {
      logLevel: LogLevel.Warning,
      piiLoggingEnabled: false,
      loggerCallback: (level, message) => {
        if (level === LogLevel.Error) console.error('[msal]', message);
        else if (level === LogLevel.Warning) console.warn('[msal]', message);
      },
    },
  },
};

export const armScopes = ['https://management.azure.com/user_impersonation'];

export const isMsalConfigured = Boolean(clientId);

// Single PublicClientApplication instance for the whole app.
export const pca = new PublicClientApplication(msalConfig);
await pca.initialize();
