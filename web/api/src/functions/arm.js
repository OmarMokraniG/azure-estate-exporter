const { app } = require('@azure/functions');

// Static Web Apps Function that proxies every `/api/arm/*` request through to
// `https://management.azure.com/*`. The user's Bearer token is forwarded as-is.
// This exists because the Azure Resource Manager API does not expose CORS for
// arbitrary origins — we cannot call it directly from the SPA.
//
// IMPORTANT: This proxy does NOT mint, store or log tokens. It only relays the
// `Authorization` header the browser already has from MSAL. Deploy your own
// instance so the tokens never leave your infrastructure.

const ARM = 'https://management.azure.com';

app.http('arm', {
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  authLevel: 'anonymous',
  route: 'arm/{*restOfPath}',
  handler: async (request, context) => {
    const url = new URL(request.url);
    const tail = url.pathname.replace(/^\/api\/arm/, '') + url.search;
    const target = `${ARM}${tail}`;

    const headers = {};
    const auth = request.headers.get('authorization');
    if (auth) headers['Authorization'] = auth;
    const ct = request.headers.get('content-type');
    if (ct) headers['Content-Type'] = ct;

    let body;
    if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method)) {
      body = await request.text();
    }

    context.log(`ARM proxy: ${request.method} ${tail}`);

    const upstream = await fetch(target, { method: request.method, headers, body });
    const text = await upstream.text();

    return {
      status: upstream.status,
      headers: {
        'Content-Type': upstream.headers.get('content-type') ?? 'application/json',
      },
      body: text,
    };
  },
});
