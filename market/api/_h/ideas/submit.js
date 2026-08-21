// /api/ideas/submit
//   GET  → returns all ideas (newest first), public
//   POST { text } → adds an idea. Restrictions:
//     • valid signed GitHub session required (x-gh-token header or ghToken)
//     • GitHub account must be older than 90 days (anti-abuse)
//     • per-login cooldown (IDEA_COOLDOWN_MIN, default 10 minutes)
//
// Storage via api/_store.js — Upstash Redis in production, fs locally.

const store = require('../../_store.js');
const { requireGhUser, accountTooYoung } = require('../../_admin.js');

const MAX_IDEA_LEN = 2000;
const COOLDOWN_MS = (parseInt(process.env.IDEA_COOLDOWN_MIN || '10', 10) || 10) * 60 * 1000;

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();

  const rel = 'ideas.json';

  if (req.method === 'GET') {
    res.setHeader('Cache-Control', 'no-store');
    const list = await store.readJson(rel, []);
    const sorted = (Array.isArray(list) ? list : [])
      .slice()
      .sort((a, b) => String(b.date || '').localeCompare(String(a.date || '')));
    res.status(200).json(sorted);
    return;
  }

  if (req.method === 'POST') {
    let body = req.body;
    if (!body) {
      try { body = await readBody(req); } catch (_) { body = {}; }
    }
    if (typeof body === 'string') {
      try { body = JSON.parse(body); } catch (_) { body = {}; }
    }

    const user = requireGhUser(req, body);
    if (!user || !user.login) {
      return res.status(401).json({ error: 'auth_required' });
    }
    if (accountTooYoung(user)) {
      return res.status(403).json({ error: 'account_age', minDays: 90 });
    }

    const waitMs = await store.claimRateLimit(`rl:idea:${user.login.toLowerCase()}`, COOLDOWN_MS);
    if (waitMs > 0) {
      return res.status(429).json({
        error: 'rate_limited',
        retryAfterMin: Math.ceil(waitMs / 60000),
        limitMin: Math.round(COOLDOWN_MS / 60000),
      });
    }

    const text = typeof body?.text === 'string' ? body.text.trim().slice(0, MAX_IDEA_LEN) : '';
    if (!text) return res.status(400).json({ error: 'text required' });

    let list = await store.readJson(rel, []);
    if (!Array.isArray(list)) {
      return res.status(500).json({ error: 'ideas storage corrupted' });
    }
    list.push({
      id: 'i_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36),
      author: '@' + user.login,
      login: user.login,
      text,
      date: new Date().toISOString(),
    });

    try {
      await store.writeJson(rel, list);
    } catch (e) {
      return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
    }

    res.status(200).json({ ok: true });
    return;
  }

  res.status(405).json({ error: 'method not allowed' });
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; });
    req.on('end', () => resolve(data ? JSON.parse(data) : {}));
    req.on('error', reject);
  });
}
