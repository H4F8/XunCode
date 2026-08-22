// GET /api/reports/list → admin-only list of bug reports (newest first).

const store = require('../../_store.js');
const { checkAdmin } = require('../../_admin.js');

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET' && req.method !== 'POST') {
    return res.status(405).json({ error: 'method not allowed' });
  }

  let body = req.body;
  if (!body && req.method === 'POST') {
    try { body = {}; } catch (_) { body = {}; }
  }

  const auth = await checkAdmin(req, body || {});
  if (!auth.ok) return res.status(401).json({ error: auth.error });

  res.setHeader('Cache-Control', 'no-store');
  const list = await store.readJson('reports.json', []);
  const sorted = (Array.isArray(list) ? list : [])
    .slice()
    .sort((a, b) => String(b.date || '').localeCompare(String(a.date || '')));
  res.status(200).json(sorted);
};
