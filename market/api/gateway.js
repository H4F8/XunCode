// /api/gateway — single serverless function that routes every legacy
// /api/<group>/<name> URL to its handler module in api/_h/.
//
// Vercel Hobby allows max 12 functions; this deployment exposes ONE.
// vercel.json rewrites:
//   /api/(admin|plugins|ideas|auth)/:fn  →  /api/gateway?g=<group>&f=<name>
//
// Handler modules keep the standard (req, res) signature, so nothing else
// changes. External URLs are unchanged for the website and the app.

const routes = {
  admin: {
    approve: () => require('./_h/admin/approve'),
    pending: () => require('./_h/admin/pending'),
    ping: () => require('./_h/admin/ping'),
    reject: () => require('./_h/admin/reject'),
    submit: () => require('./_h/admin/submit'),
  },
  plugins: {
    download: () => require('./_h/plugins/download'),
    info: () => require('./_h/plugins/info'),
    list: () => require('./_h/plugins/list'),
    review: () => require('./_h/plugins/review'),
    reviews: () => require('./_h/plugins/reviews'), // legacy plural alias
  },
  ideas: {
    submit: () => require('./_h/ideas/submit'),
    list: () => require('./_h/ideas/list'),
  },
  auth: {
    start: () => require('./_h/auth/start'),
    callback: () => require('./_h/auth/callback'),
    me: () => require('./_h/auth/me'),
  },
};

module.exports = async (req, res) => {
  let g = '';
  let f = '';
  try {
    const url = new URL(req.url, 'http://localhost');
    g = url.searchParams.get('g') || '';
    f = url.searchParams.get('f') || '';
  } catch (_) {}

  const group = routes[g];
  const factory = group && group[f];
  if (!factory) {
    res.status(404).json({ error: `unknown endpoint: /api/${g}/${f}` });
    return;
  }
  return factory()(req, res);
};
