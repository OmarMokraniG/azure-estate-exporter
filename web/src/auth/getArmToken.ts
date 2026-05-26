import { InteractionRequiredAuthError } from '@azure/msal-browser';
import { pca, armScopes } from './msalConfig';

/**
 * Acquire an ARM access token for the currently signed-in user.
 * Tries silent first; falls back to a popup on InteractionRequiredAuthError.
 * Returns the raw JWT (the caller adds the Bearer prefix).
 */
export async function getArmToken(): Promise<string> {
  const account = pca.getActiveAccount() ?? pca.getAllAccounts()[0];
  if (!account) {
    throw new Error('No active account. Sign in first.');
  }
  try {
    const result = await pca.acquireTokenSilent({ scopes: armScopes, account });
    return result.accessToken;
  } catch (err) {
    if (err instanceof InteractionRequiredAuthError) {
      const result = await pca.acquireTokenPopup({ scopes: armScopes, account });
      return result.accessToken;
    }
    throw err;
  }
}
