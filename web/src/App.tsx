import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from '@azure/msal-react';
import { isMsalConfigured, armScopes, pca } from './auth/msalConfig';
import { useEffect } from 'react';
import { Login } from './components/Login';
import { ScopePicker } from './components/ScopePicker';
import { EstateView } from './components/EstateView';
import { useUi } from './state/store';

export default function App() {
  const { accounts } = useMsal();
  const scope = useUi((s) => s.scope);
  const clearScope = useUi((s) => s.clearScope);

  useEffect(() => {
    if (accounts.length && !pca.getActiveAccount()) {
      pca.setActiveAccount(accounts[0]);
    }
  }, [accounts]);

  if (!isMsalConfigured) {
    return <UnconfiguredBanner />;
  }

  return (
    <div className="flex h-full flex-col">
      <Header signedIn={accounts.length > 0} />
      <main className="mx-auto flex w-full max-w-7xl flex-1 flex-col gap-4 p-4 md:p-6">
        <UnauthenticatedTemplate>
          <Login />
        </UnauthenticatedTemplate>
        <AuthenticatedTemplate>
          {scope.subscriptionId ? (
            <EstateView onChangeScope={clearScope} />
          ) : (
            <ScopePicker />
          )}
        </AuthenticatedTemplate>
      </main>
      <Footer />
    </div>
  );
}

function Header({ signedIn }: { signedIn: boolean }) {
  const { instance, accounts } = useMsal();
  const account = accounts[0];
  return (
    <header className="border-b border-slate-200 bg-white">
      <div className="mx-auto flex w-full max-w-7xl items-center justify-between px-4 py-3 md:px-6">
        <div className="flex items-center gap-3">
          <div
            className="grid h-8 w-8 place-items-center rounded bg-azure-600 text-white"
            aria-hidden
          >
            <svg viewBox="0 0 24 24" className="h-5 w-5" fill="currentColor">
              <path d="M12 2 2 22h7l3-6 3 6h7L12 2zm0 6 4 8H8l4-8z" />
            </svg>
          </div>
          <div>
            <h1 className="text-base font-semibold leading-tight">Azure Estate Exporter</h1>
            <p className="text-xs leading-tight text-slate-500">
              Sign in, browse subscriptions, export Terraform
            </p>
          </div>
        </div>
        {signedIn && account && (
          <div className="flex items-center gap-3">
            <span className="hidden text-sm text-slate-700 sm:inline">{account.username}</span>
            <button
              type="button"
              className="btn-ghost"
              onClick={() => instance.logoutPopup({ account })}
            >
              Sign out
            </button>
          </div>
        )}
      </div>
    </header>
  );
}

function Footer() {
  return (
    <footer className="border-t border-slate-200 bg-white py-3 text-center text-xs text-slate-500">
      Open source ·{' '}
      <a
        className="text-azure-600 hover:underline"
        href="https://github.com/OmarMokraniG/azure-estate-exporter"
        target="_blank"
        rel="noreferrer"
      >
        github.com/OmarMokraniG/azure-estate-exporter
      </a>{' '}
      · Token scope: {armScopes[0]}
    </footer>
  );
}

function UnconfiguredBanner() {
  return (
    <div className="grid min-h-screen place-items-center p-6">
      <div className="card max-w-2xl space-y-4 p-8">
        <h2 className="text-xl font-semibold">Configure your Entra app registration</h2>
        <p className="text-slate-600">
          This web app is unconfigured. To use it, create an Entra app registration in your tenant
          and set the client id via the <code className="font-mono">VITE_AZURE_CLIENT_ID</code>{' '}
          environment variable.
        </p>
        <p className="text-slate-600">
          From the repo root, run:
        </p>
        <pre className="overflow-x-auto rounded bg-slate-900 p-3 text-xs text-slate-100">
{`pwsh -File scripts/create-app-reg.ps1
# then copy the printed client id into web/.env.local:
# VITE_AZURE_CLIENT_ID=<your-client-id>`}
        </pre>
        <p className="text-xs text-slate-500">
          The app needs the <code className="font-mono">Azure Service Management → user_impersonation</code>{' '}
          delegated permission and SPA redirect URI <code className="font-mono">http://localhost:5173</code>.
        </p>
      </div>
    </div>
  );
}
