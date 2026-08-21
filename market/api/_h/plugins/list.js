// GET /api/plugins/list?q=search — returns approved plugins, sorted by rating desc.
// Optional ?q= filter searches name, author, description, tags.

const fs = require('fs');
const path = require('path');

module.exports = (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });

  try {
    const file = path.join(process.cwd(), 'data', 'plugins.json');
    const raw = fs.existsSync(file) ? fs.readFileSync(file, 'utf-8') : '[]';
    let list = JSON.parse(raw);
    if (!Array.isArray(list)) return res.status(500).json({ error: 'corrupt data' });

    // search filter
    const q = (req.query?.q || '').toLowerCase().trim();
    if (q) {
      list = list.filter(p =>
        (p.name || '').toLowerCase().includes(q) ||
        (p.author || '').toLowerCase().includes(q) ||
        (p.description || '').toLowerCase().includes(q) ||
        (p.id || '').toLowerCase().includes(q) ||
        (p.tags || []).some(t => t.toLowerCase().includes(q))
      );
    }

    list.sort((a, b) => {
      const r = (b.rating || 0) - (a.rating || 0);
      if (r !== 0) return r;
      return (b.downloads || 0) - (a.downloads || 0);
    });

    res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');
    res.status(200).json(list);
  } catch (e) {
    res.status(500).json({ error: String(e && e.message || e) });
  }
};
