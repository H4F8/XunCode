// /api/plugins/review
//   GET ?id=<pluginId>  → returns array of reviews
//   POST { pluginId, rating, review, userToken } → adds review and recomputes rating
//
// Storage notes:
//   On Vercel the function FS is read-only on the hot path, so writes only
//   succeed on local `vercel dev` or when the data dir is mounted as a writable
//   volume. For production deployments, configure a GitHub-token-backed write
//   path (see market/README.md).

const fs = require('fs');
const path = require('path');

const MAX_REVIEW_LEN = 2000;

function readJson(file, fallback) {
  try {
    return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf-8')) : fallback;
  } catch (_) {
    return fallback;
  }
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2), 'utf-8');
}

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();

  const cwd = process.cwd();
  const reviewsDir = path.join(cwd, 'data', 'reviews');
  const pluginsFile = path.join(cwd, 'data', 'plugins.json');

  if (req.method === 'GET') {
    const id = (req.query && req.query.id) || '';
    if (!id) return res.status(400).json({ error: 'missing id' });
    const file = path.join(reviewsDir, `${id}.json`);
    const list = readJson(file, []);
    res.status(200).json(list);
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
    const { pluginId, rating, review, userToken } = body || {};
    if (!pluginId || typeof pluginId !== 'string') {
      return res.status(400).json({ error: 'pluginId required' });
    }
    const r = Number(rating);
    if (!Number.isInteger(r) || r < 1 || r > 5) {
      return res.status(400).json({ error: 'rating must be integer 1-5' });
    }
    const text = typeof review === 'string' ? review.slice(0, MAX_REVIEW_LEN) : '';
    if (!userToken || typeof userToken !== 'string') {
      return res.status(400).json({ error: 'userToken required' });
    }

    const file = path.join(reviewsDir, `${pluginId}.json`);
    const list = readJson(file, []);

    const existing = list.findIndex(it => it.userToken === userToken);
    const entry = {
      id: cryptoRandomId(),
      author: 'Anonymous',
      rating: r,
      text,
      review: text,
      userToken,
      date: new Date().toISOString(),
    };
    if (existing >= 0) list[existing] = entry;
    else list.push(entry);

    try {
      writeJson(file, list);
    } catch (e) {
      return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
    }

    // Recompute rating in plugins.json
    try {
      const plugins = readJson(pluginsFile, []);
      const idx = plugins.findIndex(p => p && p.id === pluginId);
      if (idx >= 0) {
        const sum = list.reduce((acc, it) => acc + (Number(it.rating) || 0), 0);
        plugins[idx].rating = list.length ? +(sum / list.length).toFixed(2) : 0;
        plugins[idx].reviewsCount = list.length;
        writeJson(pluginsFile, plugins);
      }
    } catch (_) {}

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

function cryptoRandomId() {
  return 'r_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
}
