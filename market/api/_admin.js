// Shared admin auth helper (not an endpoint — underscore-prefixed files are
// ignored by Vercel).
//
// Two ways to be an admin:
//   1. Classic: ADMIN_API_KEY header/body field.
//   2. GitHub session: signed x-gh-token header / ghToken body field whose
//      payload.login is listed in ADMIN_GITHUB_LOGINS (comma-separated,
//      default "H4F8").

const crypto = require('crypto');

function hmac(secret, data) {
  return crypto.createHmac('sha256', secret).update(data).digest('base64url');
}

function verifyGhToken(token, secret) {
  if (typeof token !== 'string' || !token.includes('.')) return null;
  const [payloadB64, sig] = token.split('.');
  try {
    const payload = Buffer.from(payloadB64, 'base64url').toString('utf-8');
    const a = Buffer.from(sig);
    const b = Buffer.from(hmac(secret, payload));
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
    const user = JSON.parse(payload);
    if (!user.exp || Date.now() > user.exp) return null;
    return user;
  } catch (_) {
    return null;
  }
}

function adminLogins() {
  return (process.env.ADMIN_GITHUB_LOGINS || 'H4F8')
    .split(',')
    .map(s => s.trim().toLowerCase())
    .filter(Boolean);
}

// The XunCode app authenticates via GitHub Device Flow and stores the raw
// OAuth access token (gho_/ghp_/github_pat_…). Web visitors instead carry our
// signed session token. Both are accepted:
//   1. signed session (fast, no network)
//   2. raw access token validated live against api.github.com/user
const GH_TOKEN_RE = /^(gho_|ghp_|ghu_|ghs_|github_pat_)/;

async function ghUserFromAccessToken(accessToken) {
  if (typeof accessToken !== 'string' || !GH_TOKEN_RE.test(accessToken)) return null;
  try {
    const r = await fetch('https://api.github.com/user', {
      headers: {
        authorization: `Bearer ${accessToken}`,
        'user-agent': 'xuncode-market',
        accept: 'application/vnd.github+json',
      },
    });
    if (!r.ok) return null;
    const u = await r.json();
    if (!u || !u.login) return null;
    return {
      login: String(u.login),
      name: typeof u.name === 'string' ? u.name : '',
      avatar: typeof u.avatar_url === 'string' ? u.avatar_url : '',
      created: typeof u.created_at === 'string' ? u.created_at : '',
      admin: adminLogins().includes(String(u.login).toLowerCase()),
    };
  } catch (_) {
    return null;
  }
}

function extractToken(req, body) {
  return (
    req.headers['x-gh-token'] ||
    (body && typeof body === 'object' ? body.ghToken : undefined)
  );
}

// Returns { ok: true } or { ok: false, error } — await it from endpoints.
async function checkAdmin(req, body) {
  const keyHeader = req.headers['x-admin-key'];
  const keyBody = body && typeof body === 'object' ? body.adminKey : undefined;
  const expectedKey = process.env.ADMIN_API_KEY;
  if (expectedKey && (keyHeader === expectedKey || keyBody === expectedKey)) {
    return { ok: true };
  }

  const secret = process.env.AUTH_SECRET || process.env.ADMIN_API_KEY;
  if (!secret) return { ok: false, error: 'admin auth not configured' };

  const token = extractToken(req, body);
  let user =
    (typeof token === 'string' ? verifyGhToken(token, secret) : null) ||
    (await ghUserFromAccessToken(token));
  if (!user) return { ok: false, error: 'GitHub session required' };

  if (!adminLogins().includes(String(user.login).toLowerCase())) {
    return { ok: false, error: `${user.login} is not an admin` };
  }
  return { ok: true };
}

// Verifies the request carries a valid signed session OR a real GitHub
// access token; returns the user payload or null.
async function requireGhUser(req, body) {
  const secret = process.env.AUTH_SECRET || process.env.ADMIN_API_KEY;
  if (!secret) return null;
  const token = extractToken(req, body);
  if (typeof token !== 'string' || !token) return null;
  const sess = verifyGhToken(token, secret);
  if (sess) return sess;
  return ghUserFromAccessToken(token);
}

// Minimum GitHub account age for public write actions (anti-abuse).
const MIN_ACCOUNT_AGE_MS = 90 * 24 * 60 * 60 * 1000;

function accountTooYoung(user) {
  if (!user || !user.created) return true; // old session without created_at → re-login
  return Date.now() - Date.parse(user.created) < MIN_ACCOUNT_AGE_MS;
}

module.exports = { verifyGhToken, adminLogins, checkAdmin, hmac, requireGhUser, accountTooYoung };
