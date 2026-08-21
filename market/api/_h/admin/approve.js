// POST /api/admin/approve
//   body: { id, adminKey? }  — or GitHub session: { id, ghToken }
//
// Moves a submission from data/pending.json to data/plugins.json. Requires
// either ADMIN_API_KEY or a signed GitHub token of an allowlisted admin
// (see api/_admin.js).

const fs = require('fs');
const path = require('path');
const { checkAdmin } = require('../../_admin.js');

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  let body = req.body;
  if (!body) body = await readBody(req).catch(() => ({}));
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }

  const auth = await checkAdmin(req, body);
  if (!auth.ok) return res.status(401).json({ error: auth.error });

  const { id } = body || {};
  if (!id) return res.status(400).json({ error: 'id required' });

  const cwd = process.cwd();
  const pendingFile = path.join(cwd, 'data', 'pending.json');
  const pluginsFile = path.join(cwd, 'data', 'plugins.json');

  let pending = [];
  let plugins = [];
  try {
    pending = fs.existsSync(pendingFile) ? JSON.parse(fs.readFileSync(pendingFile, 'utf-8')) : [];
    plugins = fs.existsSync(pluginsFile) ? JSON.parse(fs.readFileSync(pluginsFile, 'utf-8')) : [];
  } catch (e) {
    return res.status(500).json({ error: 'failed to read data: ' + (e.message || e) });
  }

  const idx = pending.findIndex(p => p.id === id);
  if (idx < 0) return res.status(404).json({ error: 'submission not found' });

  const entry = pending.splice(idx, 1)[0];
  const filtered = plugins.filter(p => p.id !== id);
  filtered.push({
    ...entry,
    version: entry.version || '1.0.0',
    rating: 0,
    reviewsCount: 0,
    downloads: 0,
    icon: entry.icon || '',
    tags: entry.tags || [],
    approvedAt: new Date().toISOString(),
  });

  try {
    fs.writeFileSync(pendingFile, JSON.stringify(pending, null, 2));
    fs.writeFileSync(pluginsFile, JSON.stringify(filtered, null, 2));
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
