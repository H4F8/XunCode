// GET /api/admin/ping — health check: auth config + collection sizes.

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });

  const safeCount = async (rel) => {
    try {
      const list = await store.readJson(rel, []);
      return Array.isArray(list) ? list.length : 0;
    } catch (_) {
      return 0;
    }
  };

  res.status(200).json({
    ok: true,
    adminKeyConfigured: Boolean(process.env.ADMIN_API_KEY),
    redis: store.redisMode(),
    plugins: await safeCount('plugins.json'),
    pending: await safeCount('pending.json'),
    ideas: await safeCount('ideas.json'),
    time: new Date().toISOString(),
  });
};

const store = require('../../_store.js');
