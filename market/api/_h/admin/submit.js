// POST /api/admin/submit
//   body: { githubUrl, name }
//
// Minimal submission: just the plugin name and its GitHub repo link.
// Everything else is derived automatically:
//   - pluginId  ← owner.repo (lowercased, sanitized)
//   - author    ← repo owner
//   - version / description / tags ← pulled from the repo's plugin.json
//
// Validates that the repo has plugin.json and main.js, then appends to
// data/pending.json. No auth required — moderation happens later via
// /api/admin/approve.

const store = require('../../_store.js');
const { requireGhUser, accountTooYoung } = require('../../_admin.js');

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  let body = req.body;
  if (!body) body = await readBody(req).catch(() => ({}));
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }
  const user = await requireGhUser(req, body);
  if (!user || !user.login) {
    return res.status(401).json({ error: 'auth_required' });
  }
  if (accountTooYoung(user)) {
    return res.status(403).json({ error: 'account_age', minDays: 90 });
  }

  const { githubUrl, name } = body || {};

  if (!githubUrl || typeof githubUrl !== 'string') {
    return res.status(400).json({ error: 'githubUrl required' });
  }
  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ error: 'name required' });
  }

  const cleaned = cleanUrl(githubUrl);
  const match = /^https:\/\/github\.com\/([^/]+)\/([^/]+)$/.exec(cleaned);
  if (!match) return res.status(400).json({ error: 'githubUrl must be https://github.com/owner/repo' });
  const [, ownerRaw, repoRaw] = match;
  const owner = ownerRaw;
  const repo = repoRaw;

  // Derive a stable plugin id from the repo coordinates.
  const pluginId = `${owner}.${repo}`.toLowerCase().replace(/[^a-z0-9._-]/g, '-');

  // Fetch plugin.json to auto-fill version/description/tags/author when present.
  let manifest = null;
  let manifestOk = false;
  let mainOk = false;
  for (const branch of ['main', 'master']) {
    try {
      const m = await httpGetJson(`https://raw.githubusercontent.com/${owner}/${repo}/${branch}/plugin.json`);
      if (m.ok && m.json && typeof m.json === 'object') {
        manifestOk = true;
        manifest = m.json;
        const main = await httpHead(`https://raw.githubusercontent.com/${owner}/${repo}/${branch}/main.js`);
        mainOk = main.ok;
        break;
      }
      if (m.reachable) { manifestOk = false; break; }
    } catch (_) {}
  }

  if (!manifestOk) {
    return res.status(400).json({ error: 'plugin.json not reachable on main or master branch' });
  }
  if (!mainOk) {
    return res.status(400).json({ error: 'main.js not reachable' });
  }

  const list = (await store.readJson('pending.json', []))
    .filter(it => it.id !== pluginId);
  list.push({
    id: pluginId,
    name: name.trim(),
    version: (manifest && manifest.version) || '1.0.0',
    description:
      (manifest && (manifest.description || manifest.desc)) ||
      '',
    author:
      '@' + user.login,
    githubUrl: cleaned,
    tags: Array.isArray(manifest?.tags) ? manifest.tags : [],
    permissions: Array.isArray(manifest?.permissions)
      ? manifest.permissions
      : [],
    submittedAt: new Date().toISOString(),
  });

  try {
    await store.writeJson('pending.json', list);
  } catch (e) {
    return res.status(500).json({ error: 'persist failed: ' + (e.message || e) });
  }

  res.status(200).json({ success: true });
};

function cleanUrl(u) {
  let s = String(u).trim();
  if (s.endsWith('.git')) s = s.slice(0, -4);
  if (s.endsWith('/')) s = s.slice(0, -1);
  return s;
}

async function httpHead(url) {
  // Use GET with Range to be compatible with raw.githubusercontent.com which
  // refuses HEAD on missing files but answers GET cleanly.
  const r = await fetch(url, { method: 'GET', headers: { 'Range': 'bytes=0-0' } });
  return { ok: r.status >= 200 && r.status < 400 };
}

async function httpGetJson(url) {
  const r = await fetch(url);
  if (r.status === 404) return { reachable: false, ok: false, json: null };
  if (r.status < 200 || r.status >= 400) return { reachable: true, ok: false, json: null };
  try {
    return { reachable: true, ok: true, json: JSON.parse(await r.text()) };
  } catch (_) {
    return { reachable: true, ok: false, json: null };
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; });
    req.on('end', () => resolve(data ? JSON.parse(data) : {}));
    req.on('error', reject);
  });
}
