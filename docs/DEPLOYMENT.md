# Deployment

The API (Rails + PostgreSQL) runs on **Render**, which runs a long-lived Ruby web server with a managed database. The browser demo in `web/` is static and runs on **Vercel**.

Vercel is built for frontends and short-lived serverless functions, so it isn't used for the Rails API itself.

## 1. API on Render

1. Push this repository to GitHub.
2. In the Render dashboard, choose **New → Blueprint** and select the repository. Render reads `render.yaml` and creates:
   - `community-reservations-db`: a free PostgreSQL database
   - `community-reservations-api`: the Rails web service
3. When prompted for the variables marked `sync: false`, set:
   - `DEMO_ADMIN_PASSWORD`: a strong password for `admin@example.com` (never committed)
   - `CORS_ORIGINS`: your Vercel URL, e.g. `https://community-reservations.vercel.app` (you can fill this in after step 2 below)
4. Deploy. Each deploy runs `bin/render-build.sh`, which installs gems, runs migrations, and loads idempotent demo data.
5. Verify the deployment:

   ```bash
   curl https://<your-service>.onrender.com/api/v1/health
   ruby script/smoke_test.rb https://<your-service>.onrender.com
   ```

Generated automatically by the Blueprint: `SECRET_KEY_BASE`, `JWT_SECRET`, and `DATABASE_URL`.

Free-tier notes:

- The service sleeps after about 15 minutes idle; the first request then takes roughly 30-60 seconds. The demo UI shows "API waking up…" and retries.
- Free Render PostgreSQL databases expire after a limited period. Check Render's current free-tier terms, and upgrade or recreate the database when needed.

## 2. Demo UI on Vercel

1. In `web/config.js`, set `DEFAULT_API_BASE_URL` to your Render URL and commit.
2. In Vercel, choose **Add New → Project**, import the repository, and set **Root Directory** to `web`. Framework preset: **Other**. There is no build command, and the output directory is the root directory.
3. Deploy, then add the Vercel URL to `CORS_ORIGINS` on Render (comma-separated if you have several) and redeploy the API.

You can point the UI at any API without redeploying by adding `?api=https://...` to the page URL.

## 3. Docker (any container host)

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
