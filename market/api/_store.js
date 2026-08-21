// Shared JSON storage for all marketplace handlers.
//
// Backends (auto-selected):
//
//   1. Upstash Redis (free tier) — used when UPSTASH_REDIS_REST_URL +
//      UPSTASH_REDIS_REST_TOKEN are set (Vercel Storage → Marketplace →
//      Upstash injects exactly these names). Pure REST/fetch, no deps,
//      serverless-friendly. Whole collections are stored as single JSON
//      values under keys prefixed with KEY_PREFIX.
//
//   2. Local fs — `vercel dev` / self-hosting. Files under market/data/.
//
// The deployment bundle ships the original market/data/*.json, so on a Redis
// cache miss we lazily seed the key from the bundled copy (first read wins).

const fs = require('fs');
const path = require('path');

const KEY_PREFIX = process.env.UPSTASH_KEY_PREFIX || 'xuncode-market';

function restConfig() {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  return url && token ? { url: url.replace(/\/$/, ''), token } : null;
}

function bundledFile(rel) {
  return path.join(process.cwd(), 'data', rel);
}

function readLocal(rel, fallback) {
  try {
    const f = bundledFile(rel);
    return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf-8')) : fallback;
  } catch (_) {
    return fallback;
  }
}

async function rest(cfg, command) {
  const r = await fetch(`${cfg.url}/${command.map(encodeURIComponent).join('/')}`,
    { headers: { authorization: `Bearer ${cfg.token}` } });
  if (!r.ok) throw new Error(`upstash ${r.status}`);
  const j = await r.json();
  return j.result;
}

// ── warm-instance cache ────────────────────────────────────────────────
const memCache = new Map();

module.exports = {
  redisMode: () => restConfig() !== null,

  async readJson(rel, fallback) {
    const cfg = restConfig();
    if (!cfg) return readLocal(rel, fallback);

    if (memCache.has(rel)) return memCache.get(rel);

    let raw = null;
    try {
      raw = await rest(cfg, ['get', `${KEY_PREFIX}:${rel}`]);
    } catch (_) {}

    if (raw != null) {
      try {
        const v = JSON.parse(raw);
        memCache.set(rel, v);
        return v;
      } catch (_) {}
    }

    // Miss → seed from the copy bundled with the deployment.
    const seeded = readLocal(rel, null);
    if (seeded !== null && !Array.isArray(seeded)) return seeded;
    if (seeded !== null) {
      memCache.set(rel, seeded);
      try { await rest(cfg, ['set', `${KEY_PREFIX}:${rel}`, JSON.stringify(seeded)]); } catch (_) {}
      return seeded;
    }
    return fallback;
  },

  async writeJson(rel, data) {
    const cfg = restConfig();

    // Always mirror into the local tree too (local mode + fresh bundles).
    try {
      const f = bundledFile(rel);
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, JSON.stringify(data, null, 2), 'utf-8');
    } catch (_) {}
    memCache.set(rel, data);

    if (!cfg) return;

    await rest(cfg, ['set', `${KEY_PREFIX}:${rel}`, JSON.stringify(data)]);
  },
};
