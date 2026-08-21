// GET /api/auth/callback?code=…&state=…
//
// Exchanges the OAuth code for an access token, loads the GitHub profile and
// redirects back to the site with a stateless signed session token:
//   /#auth=<base64url(payload)>.<hmac>
//
// Payload: { login, name, avatar, exp } — exp is 30 days out. No server-side
// session storage is needed (Vercel FS is read-only); anything that needs to
// trust the identity can verify via POST /api/auth/me.

const crypto = require('crypto');
const { adminLogins } = require('../../_admin.js');

const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;

function hmac(secret, data) {
  return crypto.createHmac('sha256', secret).update(data).digest('base64url');
}

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });

  const secret = process.env.AUTH_SECRET || process.env.ADMIN_API_KEY;
  if (!secret) return redirectErr(res, 'GitHub auth is not configured');

  const { code, state } = req.query || {};
  if (!code || !state) return redirectErr(res, 'missing code/state');

  // Verify signed state (max 10 minutes old).
  const parts = String(state).split('.');
  if (parts.length !== 3) return redirectErr(res, 'bad state');
  const [ts, nonce, sig] = parts;
  try {
    const expected = hmac(secret, `${ts}.${nonce}`);
    const a = Buffer.from(sig);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return redirectErr(res, 'state signature mismatch');
    }
    if (Date.now() - parseInt(ts, 36) > 10 * 60 * 1000) {
      return redirectErr(res, 'state expired, try again');
    }
  } catch (_) {
    return redirectErr(res, 'state verification failed');
  }

  const proto = req.headers['x-forwarded-proto'] || 'https';
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const redirectUri = `${proto}://${host}/api/auth/callback`;

  // Code → access token.
  let accessToken = '';
  try {
    const r = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({
        client_id: process.env.GITHUB_CLIENT_ID,
        client_secret: process.env.GITHUB_CLIENT_SECRET,
        code,
        redirect_uri: redirectUri,
      }),
    });
    const data = await r.json();
    accessToken = data.access_token || '';
    if (!accessToken) return redirectErr(res, data.error_description || 'no access_token from GitHub');
  } catch (e) {
    return redirectErr(res, 'token exchange failed');
  }

  // Access token → profile.
  let profile = null;
  try {
    const r = await fetch('https://api.github.com/user', {
      headers: { authorization: `Bearer ${accessToken}`, accept: 'application/vnd.github+json' },
    });
    if (!r.ok) return redirectErr(res, 'profile request failed');
    profile = await r.json();
  } catch (_) {
    return redirectErr(res, 'profile request failed');
  }

  const payload = JSON.stringify({
    login: String(profile.login || ''),
    name: String(profile.name || profile.login || ''),
    avatar: String(profile.avatar_url || ''),
    admin: adminLogins().includes(String(profile.login || '').toLowerCase()),
    exp: Date.now() + SESSION_TTL_MS,
  });
  const token = `${Buffer.from(payload).toString('base64url')}.${hmac(secret, payload)}`;

  res.writeHead(302, { Location: `${proto}://${host}/#auth=${encodeURIComponent(token)}` });
  res.end();
};

function redirectErr(res, message) {
  res.writeHead(302, { Location: `/#authError=${encodeURIComponent(message)}` });
  res.end();
}
