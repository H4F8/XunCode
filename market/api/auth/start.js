// GET /api/auth/start → redirects the browser to GitHub's authorize page.
//
// Env:
//   GITHUB_CLIENT_ID            – OAuth App client id (required)
//   AUTH_SECRET | ADMIN_API_KEY – HMAC secret for the signed state
//
// The state parameter carries a timestamp + nonce signed with the secret so
// the callback can reject forged or stale responses without server storage.

const crypto = require('crypto');

function hmac(secret, data) {
  return crypto.createHmac('sha256', secret).update(data).digest('base64url');
}

module.exports = (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });

  const clientId = process.env.GITHUB_CLIENT_ID;
  const secret = process.env.AUTH_SECRET || process.env.ADMIN_API_KEY;
  if (!clientId || !secret) {
    return res.status(500).json({ error: 'GitHub auth is not configured (GITHUB_CLIENT_ID / AUTH_SECRET missing)' });
  }

  const ts = Date.now().toString(36);
  const nonce = crypto.randomBytes(8).toString('hex');
  const state = `${ts}.${nonce}.${hmac(secret, `${ts}.${nonce}`)}`;

  const proto = req.headers['x-forwarded-proto'] || 'https';
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const redirectUri = `${proto}://${host}/api/auth/callback`;

  const url =
    'https://github.com/login/oauth/authorize' +
    `?client_id=${encodeURIComponent(clientId)}` +
    `&redirect_uri=${encodeURIComponent(redirectUri)}` +
    `&scope=${encodeURIComponent('read:user')}` +
    `&state=${encodeURIComponent(state)}` +
    '&allow_signup=true';

  res.writeHead(302, { Location: url });
  res.end();
};
