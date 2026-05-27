import type { ReactNode } from 'react';
import { useMsal } from '@azure/msal-react';
import {
  Cloud,
  LogOut,
  Moon,
  Sun,
  ChevronRight,
} from 'lucide-react';
import { useUi } from '@/state/store';
import { armScopes } from '@/auth/msalConfig';

/**
 * Application shell — sticky header, persistent footer, theme + auth controls.
 * Sidebar navigation lives inside EstateView because the nav items only
 * make sense once a scope is selected.
 */
export function AppShell({ children }: { children: ReactNode }) {
  const { instance, accounts } = useMsal();
  const account = accounts[0];
  const theme = useUi((s) => s.theme);
  const toggleTheme = useUi((s) => s.toggleTheme);
  const scope = useUi((s) => s.scope);
  const clearScope = useUi((s) => s.clearScope);

  return (
    <div className="flex h-full min-h-screen flex-col bg-page">
      <header className="sticky top-0 z-30 border-b border-default bg-surface/80 backdrop-blur">
        <div className="mx-auto flex w-full max-w-[1400px] items-center gap-3 px-4 py-2.5 md:px-6">
          <button
            type="button"
            className="flex items-center gap-2.5"
            onClick={() => clearScope()}
            aria-label="Home"
            title="Reset scope"
          >
            <div
              className="grid h-8 w-8 place-items-center rounded-lg bg-accent text-white shadow-glow"
              aria-hidden
            >
              <Cloud className="h-4 w-4" />
            </div>
            <div className="hidden text-left sm:block">
              <h1 className="text-sm font-semibold leading-tight text-fg">Azure Estate Exporter</h1>
              <p className="text-[11px] leading-tight text-subtle">Inventory · IaC · FinOps</p>
            </div>
          </button>

          {scope.subscriptionId && (
            <div className="ml-2 hidden items-center gap-1 text-xs text-muted md:flex">
              <ChevronRight className="h-3.5 w-3.5 text-subtle" />
              <span className="truncate font-medium text-fg">
                {scope.subscriptionName ?? scope.subscriptionId}
              </span>
              {scope.resourceGroup && (
                <>
                  <ChevronRight className="h-3.5 w-3.5 text-subtle" />
                  <span className="truncate font-mono text-[11px]">{scope.resourceGroup}</span>
                </>
              )}
            </div>
          )}

          <div className="ml-auto flex items-center gap-1">
            <button
              type="button"
              onClick={toggleTheme}
              className="btn-ghost !p-1.5"
              title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
              aria-label="Toggle theme"
            >
              {theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
            </button>
            {account && (
              <>
                <span
                  className="hidden h-7 items-center rounded-full bg-surface-2 px-3 text-[12px] font-medium text-fg sm:inline-flex"
                  title={account.username}
                >
                  {account.username}
                </span>
                <button
                  type="button"
                  className="btn-ghost !p-1.5"
                  onClick={() => instance.logoutPopup({ account })}
                  title="Sign out"
                  aria-label="Sign out"
                >
                  <LogOut className="h-4 w-4" />
                </button>
              </>
            )}
          </div>
        </div>
      </header>

      <main className="mx-auto flex w-full max-w-[1400px] flex-1 flex-col gap-4 p-4 md:p-6">
        {children}
      </main>

      <footer className="border-t border-default bg-surface/60 backdrop-blur">
        <div className="mx-auto flex w-full max-w-[1400px] items-center justify-between gap-3 px-4 py-2.5 text-[11px] text-subtle md:px-6">
          <span>
            Open source ·{' '}
            <a
              className="text-accent hover:underline"
              href="https://github.com/OmarMokraniG/azure-estate-exporter"
              target="_blank"
              rel="noreferrer"
            >
              github.com/OmarMokraniG/azure-estate-exporter
            </a>
          </span>
          <span className="hidden font-mono md:inline">scope: {armScopes[0]}</span>
        </div>
      </footer>
    </div>
  );
}
