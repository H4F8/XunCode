// POST /api/plugins/download
//   body: { pluginId, userToken }
//
// Increments the `downloads` counter for a plugin in plugins.json. Dedupes
// per (pluginId, userToken) — the same anonymous user can install/uninstall
// the same plugin without inflating the counter.
//
// Same FS caveat as review.js: writes succeed on `vercel dev` and on
// deployments where data/ is writable; otherwise you need a GH-token-backed
// commit path. See market/README.md.

const fs = require('fs');
const path = require('path');

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
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  let body = req.body;
  if (!body) {
    try { body = await readBody(req); } catch (_) { body = {}; }
  }
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }
  const { pluginId, userToken } = body || {};
  if (!pluginId || typeof pluginId !== 'string') {
    return res.status(400).json({ error: 'pluginId required' });
  }
  if (!userToken || typeof userToken !== 'string') {
    return res.status(400).json({ error: 'userToken required' });
  }

  const cwd = process.cwd();
  const pluginsFile = path.join(cwd, 'data', 'plugins.json');
  const dlFile = path.join(cwd, 'data', 'downloads', `${pluginId}.json`);

  const tokens = new Set(readJson(dlFile, []));
  const fresh = !tokens.has(userToken);
  if (fresh) {
    tokens.add(userToken);
    try {
      writeJson(dlFile, Array.from(tokens));
    } catch (e) {
      return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
    }
  }

  let total = 0;
  try {
    const plugins = readJson(pluginsFile, []);
    const idx = plugins.findIndex(p => p && p.id === pluginId);
    if (idx >= 0) {
      if (fresh) {
        plugins[idx].downloads = (plugins[idx].downloads || 0) + 1;
        writeJson(pluginsFile, plugins);
      }
      total = plugins[idx].downloads || 0;
    }
  } catch (_) {}

  res.status(200).json({ ok: true, counted: fresh, total });
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; });
    req.on('end', () => resolve(data ? JSON.parse(data) : {}));
    req.on('error', reject);
  });
}
