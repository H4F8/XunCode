// /api/reports/submit
//   POST { category, text } → bug report from the XunCode app.
//     • valid signed GitHub session required (x-gh-token)
//     • no account-age limit: any signed-in user may report bugs
//     • per-login cooldown (REPORT_COOLDOWN_MIN, default 3 minutes)
//   Reports are private: visible to admins via /api/reports/list only.
//
// Storage via api/_store.js — Upstash Redis in production, fs locally.

const store = require('../../_store.js');
const { requireGhUser } = require('../../_admin.js');

const MAX_TEXT_LEN = 8000;
const MAX_CATEGORY_LEN = 32;
const COOLDOWN_MS =
    (parseInt(process.env.REPORT_COOLDOWN_MIN || '3', 10) || 3) * 60 * 1000;
const MAX_REPORTS = 500;

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method not allowed' });
  }

  let body = req.body;
  if (!body) {
    try { body = await readBody(req); } catch (_) { body = {}; }
  }
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }

  const user = await requireGhUser(req, body);
  if (!user || !user.login) {
    return res.status(401).json({ error: 'auth_required' });
  }

  const waitMs =
      await store.claimRateLimit(`rl:report:${user.login.toLowerCase()}`, COOLDOWN_MS);
  if (waitMs > 0) {
    return res.status(429).json({
      error: 'rate_limited',
      retryAfterMin: Math.ceil(waitMs / 60000),
      limitMin: Math.round(COOLDOWN_MS / 60000),
    });
  }

  const text =
      typeof body?.text === 'string' ? body.text.trim().slice(0, MAX_TEXT_LEN) : '';
  const category =
      typeof body?.category === 'string'
          ? body.category.trim().slice(0, MAX_CATEGORY_LEN)
          : 'bug';
  if (!text) return res.status(400).json({ error: 'text required' });

  let list = await store.readJson('reports.json', []);
  if (!Array.isArray(list)) list = [];
  list.unshift({
    id: 'r_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36),
    login: user.login,
    author: '@' + user.login,
    name: typeof user.name === 'string' ? user.name.slice(0, 120) : '',
    category,
    text,
    date: new Date().toISOString(),
  });
  if (list.length > MAX_REPORTS) list = list.slice(0, MAX_REPORTS);

  try {
    await store.writeJson('reports.json', list);
  } catch (e) {
    return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
  }

  res.status(200).json({ ok: true });
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; });
    req.on('end', () => resolve(data ? JSON.parse(data) : {}));
    req.on('error', reject);
  });
}
