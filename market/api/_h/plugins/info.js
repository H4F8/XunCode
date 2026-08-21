// GET /api/plugins/info?id=<id> — returns details of a single plugin.

const store = require('../../_store.js');

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });

  const id = (req.query && req.query.id) || '';
  if (!id) return res.status(400).json({ error: 'missing id' });

  try {
    const list = await store.readJson('plugins.json', []);
    const found = list.find(p => p && p.id === id);
    if (!found) return res.status(404).json({ error: 'not found' });
    res.status(200).json(found);
  } catch (e) {
    res.status(500).json({ error: String(e && e.message || e) });
  }
};
