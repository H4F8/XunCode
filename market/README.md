# XunCode Plugin Marketplace

Vercel-hosted backend for the in-app marketplace.

## Endpoints

| Method | Path                       | Purpose                                         |
|--------|----------------------------|-------------------------------------------------|
| GET    | `/api/plugins/list`        | All approved plugins, sorted by rating          |
| GET    | `/api/plugins/info?id=…`   | Single plugin detail                            |
| GET    | `/api/plugins/reviews?id=…`| Reviews for a plugin (legacy alias)             |
| GET    | `/api/plugins/review?id=…` | Reviews for a plugin                            |
| POST   | `/api/plugins/review`      | Add or update a review                          |
| POST   | `/api/plugins/download`    | Increment download counter (deduped per token)  |
| POST   | `/api/admin/submit`        | Submit a GitHub repo for moderation             |
| GET    | `/api/admin/pending`       | List pending submissions (admin key)            |
| POST   | `/api/admin/approve`       | Approve a pending submission (admin key)        |

## Local development

```sh
cd market
npx vercel dev
```

`vercel dev` mounts `data/` writable, so submit/review/approve can persist
locally. The `public/index.html` UI is served at `/`.

## Production storage

Vercel functions have a read-only filesystem on production deployments,
so writes from `submit` / `review` / `approve` would be lost. The simplest
durable backend: commit changes back to the repo through the GitHub API.

Set the following env vars on the Vercel project:

| Var                   | What                                             |
|-----------------------|--------------------------------------------------|
| `ADMIN_API_KEY`       | Required by `approve.js`                         |
| `GH_TOKEN`            | (Optional) Personal access token w/ `repo`       |
| `GH_REPO`             | (Optional) `owner/repo` to commit data back to   |
| `GITHUB_CLIENT_ID`    | OAuth App client id — enables "Sign in with GitHub" |
| `GITHUB_CLIENT_SECRET`| OAuth App client secret                          |
| `AUTH_SECRET`         | HMAC secret for session tokens (falls back to `ADMIN_API_KEY`) |
| `ADMIN_GITHUB_LOGINS` | Comma-separated GitHub logins with admin rights (default `H4F8`) |

### GitHub login setup

1. GitHub → Settings → Developer settings → OAuth Apps → **New OAuth App**.
2. Homepage URL: `https://vscodemobile-market.vercel.app`
3. Authorization callback URL: `https://vscodemobile-market.vercel.app/api/auth/callback`
4. Copy the client id / secret into the Vercel env vars above and redeploy.

After signing in, the header shows your avatar; users whose login is listed in
`ADMIN_GITHUB_LOGINS` get the **Админ** tab and can approve/reject submissions
without typing the API key. The classic key flow keeps working.

If `GH_TOKEN` and `GH_REPO` are present, you can extend the write path in
`review.js` / `submit.js` / `approve.js` to call `PUT /repos/.../contents/...`
instead of `fs.writeFileSync`.

## Data layout

```
data/
├── plugins.json        # Approved plugins (array)
├── pending.json        # Submissions awaiting review (array)
├── downloads/
│   └── <pluginId>.json # List of userTokens that already counted (dedupe)
└── reviews/
    └── <pluginId>.json # Reviews for a single plugin
```

Each entry in `plugins.json` looks like:

```json
{
  "id": "com.author.plugin",
  "name": "Pretty Name",
  "version": "1.0.0",
  "author": "author",
  "description": "What it does",
  "githubUrl": "https://github.com/author/repo",
  "rating": 4.5,
  "reviewsCount": 12,
  "downloads": 342,
  "icon": "https://…",
  "tags": ["git", "linter"]
}
```

## Admin web UI

`public/index.html` ships with three tabs:

- **Browse** — public list of approved plugins (rendered with stars).
- **Submit** — just the plugin name + GitHub repo URL; the server derives the
  id, author and metadata from `plugin.json` in the repo, then queues it for
  moderation.
- **Ideas** — anyone can leave feature ideas; stored via `/api/ideas/*`.
- **Admin** — visible to GitHub admins (`ADMIN_GITHUB_LOGINS`) or paste your
  `ADMIN_API_KEY`, get the list of pending submissions, hit Approve.

## Links

- GitHub: <https://github.com/H4F8>
- Telegram Dev: <https://t.me/XunKal1Dev>
- Telegram: <https://t.me/GodPassTGK>
