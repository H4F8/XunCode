// POST /api/admin/reject
//   body: { id, adminKey }
//
// Removes a submission from data/pending.json. Requires adminKey.

const store = require('../../_store.js');
const { checkAdmin } = require('../../_admin.js');

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  let body = req.body;
  if (!body) body = await readBody(req).catch(() => ({}));
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }
  const { id } = body || {};

  const auth = await checkAdmin(req, body);
  if (!auth.ok) return res.status(401).json({ error: auth.error });
  if (!id) return res.status(400).json({ error: 'id required' });

  let pending;
  try {
    pending = await store.readJson('pending.json', []);
  } catch (e) {
    return res.status(500).json({ error: 'failed to read data: ' + (e.message || e) });
  }

  const idx = pending.findIndex(p => p.id === id);
  if (idx < 0) return res.status(404).json({ error: 'submission not found' });

  pending.splice(idx, 1);

  try {
    await store.writeJson('pending.json', pending);
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
