// DELETE /api/ideas/delete?id=<ideaId>
// Admin-only (GitHub session of an allowlisted login, see api/_admin.js).
// Removes one idea from ideas.json.

const store = require('../../_store.js');
const { checkAdmin } = require('../../_admin.js');

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST' && req.method !== 'DELETE') {
    return res.status(405).json({ error: 'method not allowed' });
  }

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

  const auth = await checkAdmin(req, body);
  if (!auth.ok) return res.status(401).json({ error: auth.error });

  const id = (body && body.id) || (req.query && req.query.id) || '';
  if (!id) return res.status(400).json({ error: 'id required' });

  const list = await store.readJson('ideas.json', []);
  const idx = list.findIndex(i => i && i.id === id);
  if (idx < 0) return res.status(404).json({ error: 'idea not found' });

  list.splice(idx, 1);

  try {
    await store.writeJson('ideas.json', list);
  } catch (e) {
    return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
  }

  res.status(200).json({ ok: true });
};
