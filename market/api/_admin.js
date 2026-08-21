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

  const token =
    req.headers['x-gh-token'] || (body && typeof body === 'object' ? body.ghToken : undefined);
  const user = verifyGhToken(token, secret);
  if (!user) return { ok: false, error: 'GitHub session required' };

  if (!adminLogins().includes(String(user.login).toLowerCase())) {
    return { ok: false, error: `${user.login} is not an admin` };
  }
  return { ok: true };
}

// Verifies the request carries a valid signed GitHub session and returns its
// payload ({login,name,avatar,admin,created,exp}) or null.
function requireGhUser(req, body) {
  const secret = process.env.AUTH_SECRET || process.env.ADMIN_API_KEY;
  if (!secret) return null;
  const token =
    req.headers['x-gh-token'] || (body && typeof body === 'object' ? body.ghToken : undefined);
  return verifyGhToken(token, secret);
}

// Minimum GitHub account age for public write actions (anti-abuse).
const MIN_ACCOUNT_AGE_MS = 90 * 24 * 60 * 60 * 1000;

function accountTooYoung(user) {
  if (!user || !user.created) return true; // old session without created_at → re-login
  return Date.now() - Date.parse(user.created) < MIN_ACCOUNT_AGE_MS;
}

module.exports = { verifyGhToken, adminLogins, checkAdmin, hmac, requireGhUser, accountTooYoung };
