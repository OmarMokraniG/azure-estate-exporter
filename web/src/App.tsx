import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from '@azure/msal-react';
import { isMsalConfigured, pca } from './auth/msalConfig';
import { useEffect } from 'react';
import { Login } from './components/Login';
import { ScopePicker } from './components/ScopePicker';
import { EstateView } from './components/EstateView';
import { AppShell } from './components/layout/AppShell';
import { UnconfiguredBanner } from './components/UnconfiguredBanner';
import { useUi } from './state/store';

export default function App() {
  const { accounts } = useMsal();
  const scope = useUi((s) => s.scope);
  const theme = useUi((s) => s.theme);

  // Sync the theme class onto <html> so Tailwind's `dark:` variant kicks in.
  useEffect(() => {
    const root = document.documentElement;
    if (theme === 'dark') root.classList.add('dark');
    else root.classList.remove('dark');
  }, [theme]);

  useEffect(() => {
    if (accounts.length && !pca.getActiveAccount()) {
      pca.setActiveAccount(accounts[0]);
    }
  }, [accounts]);

  if (!isMsalConfigured) {
    return <UnconfiguredBanner />;
  }

  return (
    <AppShell>
      <UnauthenticatedTemplate>
        <Login />
      </UnauthenticatedTemplate>
      <AuthenticatedTemplate>
        {scope.subscriptionId ? <EstateView /> : <ScopePicker />}
      </AuthenticatedTemplate>
    </AppShell>
  );
}
