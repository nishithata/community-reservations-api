# Deployment

| Piece | Host | Why |
|---|---|---|
| Rails API | **Render** (free web service) | Runs a long-lived Ruby web server, deploys from GitHub |
| PostgreSQL | **Neon** (free tier) | Free with no expiry; supports the `btree_gist` extension the overlap constraint needs |
| Demo UI (`web/`) | **Vercel** | Static files, no build step |

Vercel is built for frontends and short-lived serverless functions, so it isn't used for the Rails API itself.

## 1. Database on Neon

1. Create a project at **neon.tech** in the region closest to the API (this demo uses **AWS US West 2 (Oregon)**, matching Render's Oregon region).
2. Click **Connect**, turn **Connection pooling off**, and copy the connection string. The host must **not** contain `-pooler`, because Rails migrations use advisory locks that Neon's pooler doesn't support. Keep `?sslmode=require`.
3. Never commit or share this string; it contains the database password. If it leaks, reset the role's password in Neon (**Roles → ⋯ → Reset password**) and update Render.

## 2. API on Render

1. Push this repository to GitHub.
2. In the Render dashboard, choose **New → Blueprint** and select the repository. Render reads `render.yaml` and creates the `community-reservations-api` web service.
3. When prompted for the variables marked `sync: false`, set:
   - `DATABASE_URL`: the Neon direct connection string from step 1
   - `DEMO_ADMIN_PASSWORD`: a strong password for `admin@example.com` (never committed)
   - `CORS_ORIGINS`: your Vercel URL, e.g. `https://community-reservations-api-web.vercel.app` (use `*` until the UI is deployed)
4. Deploy. Each deploy runs `bin/render-build.sh`, which installs gems, runs migrations, and loads idempotent demo data.
5. Verify the deployment:

   ```bash
   curl https://<your-service>.onrender.com/api/v1/health
   ruby script/smoke_test.rb https://<your-service>.onrender.com
   ```

Generated automatically by the Blueprint: `SECRET_KEY_BASE` and `JWT_SECRET`.

Free-tier notes:

- The Render service sleeps after about 15 minutes idle; the first request then takes roughly 30-60 seconds. The demo UI shows "API waking up…" and retries.
- Neon scales the database to zero when idle and wakes it on the next query (well under a second), which is hidden inside Render's own wake-up time.

<details>
<summary>Using a Render-managed database instead</summary>

Add a `databases:` entry to `render.yaml` and point `DATABASE_URL` at it with `fromDatabase` (`property: connectionString`). Render's free databases expire after a limited period, so you'd need to recreate the database or upgrade to a paid plan when it does. The app re-migrates and re-seeds automatically on the next deploy.
</details>

## 3. Demo UI on Vercel

1. In `web/config.js`, set `DEFAULT_API_BASE_URL` to your Render URL and commit.
2. In Vercel, choose **Add New → Project**, import the repository, and set **Root Directory** to `web`. Framework preset: **Other**. There is no build command, and the output directory is the root directory.
3. Deploy, then add the Vercel URL to `CORS_ORIGINS` on Render (comma-separated if you have several) and redeploy the API.

You can point the UI at any API without redeploying by adding `?api=https://...` to the page URL.

## 4. Docker (any container host)

The `Dockerfile` builds a production image (non-root user, jemalloc, bootsnap precompiled). Its entrypoint runs `db:prepare` before starting the server.

```bash
docker compose up --build              # API + PostgreSQL on http://localhost:3000
docker compose exec api bin/rails db:seed
```

For a real host, provide `DATABASE_URL`, `SECRET_KEY_BASE`, `JWT_SECRET`, `CORS_ORIGINS`, and (if seeding) `DEMO_ADMIN_PASSWORD`.

## Demo safety checklist

- [x] Admin password comes only from `DEMO_ADMIN_PASSWORD`; seeding refuses to run in production without it
- [x] The public demo account is a **member**: it can't create, edit, or delete resources
- [x] Self-service sign-ups are always members
- [x] Rate limits on login, sign-up, and booking
- [x] CORS restricted to your UI's origin
- [x] Secrets come from Render environment variables, never from the repository
- [x] HTTPS enforced
