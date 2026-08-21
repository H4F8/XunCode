// GET /api/admin/ping
//
// Cheap health check for the marketplace admin auth pipeline. Returns whether
// ADMIN_API_KEY is configured server-side without leaking the value, plus the
// approved/pending counts. Use it to verify a fresh deploy is wired correctly.

const fs = require('fs');
const path = require('path');

module.exports = (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });

  const cwd = process.cwd();
  const pluginsFile = path.join(cwd, 'data', 'plugins.json');
  const pendingFile = path.join(cwd, 'data', 'pending.json');

  const safeCount = (file) => {
    try {
      if (!fs.existsSync(file)) return 0;
      const list = JSON.parse(fs.readFileSync(file, 'utf-8'));
      return Array.isArray(list) ? list.length : 0;
    } catch (_) {
      return 0;
    }
  };

  res.status(200).json({
    ok: true,
    adminKeyConfigured: Boolean(process.env.ADMIN_API_KEY),
    plugins: safeCount(pluginsFile),
    pending: safeCount(pendingFile),
    time: new Date().toISOString(),
  });
};
