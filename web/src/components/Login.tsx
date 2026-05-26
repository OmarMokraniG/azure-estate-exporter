import { useMsal } from '@azure/msal-react';
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
    <div className="grid place-items-center py-16">
      <div className="card max-w-lg space-y-6 p-8 text-center">
        <h2 className="text-2xl font-semibold">Sign in with Entra</h2>
        <p className="text-slate-600">
          Browse your Azure subscriptions, see an interactive resource map and grab a Terraform
          CLI handoff. Read-only access; nothing changes in your tenant.
        </p>
        <button type="button" className="btn-primary mx-auto" onClick={signIn}>
          Sign in with Microsoft
        </button>
        <p className="text-xs text-slate-500">
          Requested scope: <code className="font-mono">{armScopes[0]}</code>
        </p>
      </div>
    </div>
  );
}
