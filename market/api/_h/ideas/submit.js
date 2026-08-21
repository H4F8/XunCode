// /api/ideas/submit
//   GET  → returns all ideas (newest first)
//   POST { author?, text } → adds an idea
//
// Storage via api/_store.js — GitHub Contents API in production, fs locally.

const store = require('../../_store.js');

const MAX_IDEA_LEN = 2000;
const MAX_AUTHOR_LEN = 40;

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();

  const rel = 'ideas.json';

  if (req.method === 'GET') {
    const list = await store.readJson(rel, []);
    const sorted = (Array.isArray(list) ? list : [])
      .slice()
      .sort((a, b) => String(b.date || '').localeCompare(String(a.date || '')));
    res.status(200).json(sorted);
    return;
  }

  if (req.method === 'POST') {
    let body = req.body;
    if (!body) {
      try { body = await readBody(req); } catch (_) { body = {}; }
    }
    if (typeof body === 'string') {
      try { body = JSON.parse(body); } catch (_) { body = {}; }
    }
    const { author, text } = body || {};
    const cleanText = typeof text === 'string' ? text.trim().slice(0, MAX_IDEA_LEN) : '';
    if (!cleanText) return res.status(400).json({ error: 'text required' });
    const cleanAuthor =
      typeof author === 'string' && author.trim()
        ? author.trim().slice(0, MAX_AUTHOR_LEN)
        : 'Anonymous';

    let list = await store.readJson(rel, []);
    if (!Array.isArray(list)) {
      return res.status(500).json({ error: 'ideas storage corrupted' });
    }
    list.push({
      id: 'i_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36),
      author: cleanAuthor,
      text: cleanText,
      date: new Date().toISOString(),
    });

    try {
      await store.writeJson(rel, list);
    } catch (e) {
      return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
    }

    res.status(200).json({ ok: true });
    return;
  }

  res.status(405).json({ error: 'method not allowed' });
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; });
    req.on('end', () => resolve(data ? JSON.parse(data) : {}));
    req.on('error', reject);
  });
}
