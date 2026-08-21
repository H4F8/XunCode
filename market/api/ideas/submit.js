// /api/ideas/submit
//   GET  → returns all ideas (newest first)
//   POST { author?, text } → adds an idea
//
// Storage notes (same as plugins/review): on Vercel the function FS is
// read-only on the hot path; writes persist on local `vercel dev` or when
// data/ is mounted as a writable volume / replaced by a token-backed writer.

const fs = require('fs');
const path = require('path');

const MAX_IDEA_LEN = 2000;
const MAX_AUTHOR_LEN = 40;

function readJson(file, fallback) {
  try {
    return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf-8')) : fallback;
  } catch (_) {
    return fallback;
  }
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2), 'utf-8');
}

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();

  const cwd = process.cwd();
  const ideasFile = path.join(cwd, 'data', 'ideas.json');

  if (req.method === 'GET') {
    const list = readJson(ideasFile, []);
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

    const list = readJson(ideasFile, []);
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
      writeJson(ideasFile, list);
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
