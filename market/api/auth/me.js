// POST /api/auth/me  { token } → verifies the stateless session token and
// returns { login, name, avatar, exp }. Use from any trusted context; the
// browser can decode the payload itself, this endpoint validates the HMAC.

const crypto = require('crypto');

function hmac(secret, data) {
  return crypto.createHmac('sha256', secret).update(data).digest('base64url');
}

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  let body = req.body;
  if (!body) {
    try {
      body = await new Promise((resolve, reject) => {
        let d = '';
        req.on('data', c => { d += c; });
        req.on('end', () => resolve(d ? JSON.parse(d) : {}));
        req.on('error', reject);
      });
    } catch (_) { body = {}; }
  }
  const token = body && body.token;
  if (typeof token !== 'string' || !token.includes('.')) {
    return res.status(400).json({ error: 'token required' });
  }

  const secret = process.env.AUTH_SECRET || process.env.ADMIN_API_KEY;
  if (!secret) return res.status(500).json({ error: 'auth not configured' });

  const [payloadB64, sig] = token.split('.');
  try {
    const payload = Buffer.from(payloadB64, 'base64url').toString('utf-8');
    const expected = hmac(secret, payload);
    const a = Buffer.from(sig);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return res.status(401).json({ error: 'invalid signature' });
    }
    const user = JSON.parse(payload);
    if (!user.exp || Date.now() > user.exp) {
      return res.status(401).json({ error: 'session expired' });
    }
    res.status(200).json(user);
  } catch (_) {
    res.status(401).json({ error: 'invalid token' });
  }
};
