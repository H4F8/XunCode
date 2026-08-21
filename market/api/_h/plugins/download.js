// POST /api/plugins/download
//   body: { pluginId, userToken }
//
// Increments the `downloads` counter for a plugin in plugins.json. Dedupes
// per (pluginId, userToken) — the same anonymous user can install/uninstall
// the same plugin without inflating the counter.
//
// Persistence goes through api/_store.js (Upstash Redis in production).
const store = require('../../_store.js');

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

  const dlRel = `downloads/${pluginId}.json`;

  const tokens = new Set(await store.readJson(dlRel, []));
  const fresh = !tokens.has(userToken);
  if (fresh) {
    tokens.add(userToken);
    try {
      await store.writeJson(dlRel, Array.from(tokens));
    } catch (e) {
      return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
    }
  }

  let total = 0;
  try {
    const plugins = await store.readJson('plugins.json', []);
    const idx = plugins.findIndex(p => p && p.id === pluginId);
    if (idx >= 0) {
      if (fresh) {
        plugins[idx].downloads = (plugins[idx].downloads || 0) + 1;
        await store.writeJson('plugins.json', plugins);
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
