// GET /api/admin/pending
//   query/header: adminKey or x-admin-key
//
// Returns the list of submissions awaiting review. Required because Vercel
// only serves files under /public, so the admin UI cannot read data/pending.json
// directly.

const store = require('../../_store.js');
const { checkAdmin } = require('../../_admin.js');

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });

  const auth = await checkAdmin(req, null);
  if (!auth.ok) {
    // fall back to query param for the classic key flow
    if (!(req.query && req.query.adminKey && process.env.ADMIN_API_KEY &&
          req.query.adminKey === process.env.ADMIN_API_KEY)) {
      return res.status(401).json({ error: auth.error });
    }
  }

  try {
    const list = await store.readJson('pending.json', []);
    res.status(200).json(Array.isArray(list) ? list : []);
  } catch (e) {
    res.status(500).json({ error: String(e && e.message || e) });
  }
};
