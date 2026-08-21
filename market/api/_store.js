// Shared JSON storage for all marketplace handlers.
//
// Backends (auto-selected):
//
//   1. Upstash Redis (free tier) — used when UPSTASH_REDIS_REST_URL +
//      UPSTASH_REDIS_REST_TOKEN are set (Vercel Storage → Marketplace →
//      Upstash injects exactly these names). Pure REST/fetch, no deps,
//      serverless-friendly. Whole collections are stored as single values
//      under keys prefixed with KEY_PREFIX. Values larger than
//      COMPRESS_THRESHOLD bytes are gzip-compressed (zlib, built-in) and
//      stored as "gz:<base64>" to cut bandwidth/storage usage; anything
//      smaller stays plain JSON. Reads accept both forms transparently.
//
//   2. Local fs — `vercel dev` / self-hosting. Files under market/data/ are
//      always written uncompressed (pretty-printed) so they stay editable.
//
// The deployment bundle ships the original market/data/*.json, so on a Redis
// cache miss we lazily seed the key from the bundled copy (first read wins).

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const KEY_PREFIX = process.env.UPSTASH_KEY_PREFIX || 'xuncode-market';
// Values at or below this size are stored as-is; larger ones are compressed
// with whichever representation (gzip / brotli / plain) turns out smallest.
const COMPRESS_THRESHOLD = parseInt(process.env.UPSTASH_COMPRESS_OVER || '0', 10);
const MARKS = { gz: 'gz:', br: 'br:' };

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

// Rate limiting: tries to claim key for ttlMs via SET NX EX.
// Returns 0 when claimed, otherwise remaining wait in ms (approx via TTL).
async function claimRateLimit(keyRel, ttlMs) {
  const cfg = restConfig();
  if (!cfg) return 0; // no limiter without redis
  const key = `${KEY_PREFIX}:${keyRel}`;
  try {
    const set = await rest(cfg, ['set', key, Date.now().toString(), 'NX', 'EX',
      String(Math.max(1, Math.ceil(ttlMs / 1000)))]);
    if (set === 'OK' || set === true || set === 1) return 0;
    let ttl = 0;
    try { ttl = Number(await rest(cfg, ['ttl', key])) || 0; } catch (_) {}
    if (ttl <= 0) {
      // expired between calls — retry once
      const again = await rest(cfg, ['set', key, Date.now().toString(), 'NX', 'EX',
        String(Math.max(1, Math.ceil(ttlMs / 1000)))]);
      if (again === 'OK' || again === true || again === 1) return 0;
      try { ttl = Number(await rest(cfg, ['ttl', key])) || 0; } catch (_) {}
    }
    return Math.max(1, ttl) * 1000;
  } catch (_) {
    return 0; // redis hiccup → don't block users
  }
}

function encodeValue(json) {
  const buf = Buffer.from(json, 'utf-8');
  const gz = zlib.gzipSync(buf, { level: 9 });
  const br = zlib.brotliCompressSync(buf);
  // base64 inflates binary payloads by ~4/3 — factor that in, plus marker
  const gzLen = Math.ceil(gz.length * 4 / 3) + MARKS.gz.length;
  const brLen = Math.ceil(br.length * 4 / 3) + MARKS.br.length;
  if (buf.length <= gzLen && buf.length <= brLen) return json; // plain, human-readable
  if (brLen <= gzLen) return MARKS.br + br.toString('base64');
  return MARKS.gz + gz.toString('base64');
}

function decodeValue(raw) {
  if (typeof raw === 'string' && raw.startsWith(MARKS.br)) {
    return zlib.brotliDecompressSync(Buffer.from(raw.slice(MARKS.br.length), 'base64')).toString('utf-8');
  }
  if (typeof raw === 'string' && raw.startsWith(MARKS.gz)) {
    return zlib.gunzipSync(Buffer.from(raw.slice(MARKS.gz.length), 'base64')).toString('utf-8');
  }
  return raw;
}

module.exports = {
  redisMode: () => restConfig() !== null,
  claimRateLimit,

  async readJson(rel, fallback) {
    const cfg = restConfig();
    if (!cfg) return readLocal(rel, fallback);

    // NOTE: no read cache here — multiple serverless instances must see each
    // other's writes immediately (otherwise deleted items "resurrect").
    let raw = null;
    try {
      raw = await rest(cfg, ['get', `${KEY_PREFIX}:${rel}`]);
    } catch (_) {}

    if (raw != null) {
      try {
        return JSON.parse(decodeValue(raw));
      } catch (_) {}
    }

    // Miss → seed from the copy bundled with the deployment.
    const seeded = readLocal(rel, null);
    if (seeded !== null && !Array.isArray(seeded)) return seeded;
    if (seeded !== null) {
      try { await rest(cfg, ['set', `${KEY_PREFIX}:${rel}`, encodeValue(JSON.stringify(seeded))]); } catch (_) {}
      return seeded;
    }
    return fallback;
  },

  async writeJson(rel, data) {
    const cfg = restConfig();
    const json = JSON.stringify(data);

    // Always mirror into the local tree too (local mode + fresh bundles).
    try {
      const f = bundledFile(rel);
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, JSON.stringify(data, null, 2), 'utf-8');
    } catch (_) {}

    if (!cfg) return;

    await rest(cfg, ['set', `${KEY_PREFIX}:${rel}`, encodeValue(json)]);
  },
};
