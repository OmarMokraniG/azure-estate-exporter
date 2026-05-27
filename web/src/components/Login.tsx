import { useMsal } from '@azure/msal-react';
import { LogIn, ShieldCheck, Sparkles, Lock } from 'lucide-react';
import { armScopes } from '@/auth/msalConfig';

export function Login() {
  const { instance } = useMsal();
  const signIn = async () => {
    try {
      await instance.loginPopup({ scopes: armScopes, prompt: 'select_account' });
    } catch (e) {
      console.error(e);
    }
  };
  return (
    <div className="grid min-h-[60vh] place-items-center animate-fade-in">
      <div className="surface w-full max-w-3xl overflow-hidden">
        <div className="grid gap-8 p-8 md:grid-cols-[1.2fr_1fr] md:items-center">
          <div className="space-y-5">
            <span className="pill-accent">
              <Sparkles className="h-3 w-3" /> Azure assessment in a box
            </span>
            <h2 className="text-3xl font-semibold leading-tight tracking-tight text-fg">
              Inventory, diagram and Terraform-baseline any Azure estate.
            </h2>
            <p className="text-muted">
              Sign in with Entra, pick a subscription or resource group, get a complete
              architecture map, a per-resource cost view with FinOps recommendations, and a
              git-ready Terraform repo with import bootstrap.
            </p>
            <button type="button" className="btn-primary !px-4 !py-2 text-base" onClick={signIn}>
              <LogIn className="h-4 w-4" />
              Sign in with Microsoft
            </button>
            <ul className="space-y-1.5 pt-2 text-xs text-subtle">
              <li className="flex items-center gap-2">
                <ShieldCheck className="h-3.5 w-3.5 text-emerald-500" />
                Read-only access — nothing changes in your tenant.
              </li>
              <li className="flex items-center gap-2">
                <Lock className="h-3.5 w-3.5 text-emerald-500" />
                Token stays in your browser; no central backend.
              </li>
            </ul>
          </div>
          <div className="relative hidden md:block">
            <div className="aspect-square rounded-2xl bg-gradient-to-br from-accent to-violet-500 p-6 shadow-glow">
              <div className="flex h-full flex-col justify-between text-white">
                <div className="space-y-1 text-sm/relaxed opacity-90">
                  <div>📊 Inventory · diagrams · cost</div>
                  <div>🛡 Security · policy · access</div>
                  <div>🌍 Terraform · drawio · FinOps</div>
                </div>
                <div className="rounded-lg bg-white/10 p-3 text-[10px] backdrop-blur">
                  <div className="opacity-80">Requested scope</div>
                  <div className="mt-0.5 font-mono">{armScopes[0]}</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
