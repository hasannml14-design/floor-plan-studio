# Floor Plan Studio — Netlify Edition

This project is prepared for a Netlify deployment: Vite/React frontend + Netlify Functions API + PostgreSQL.

## 1. GitHub

Create a Git repository and push this folder to GitHub. Do not commit `.env` or production secrets.

## 2. Netlify

Create a new site from the GitHub repository. Netlify should use:

- Build command: `npm run build`
- Publish directory: `dist`
- Functions directory: `netlify/functions`

These values are already in `netlify.toml`.

## 3. PostgreSQL

The cloud features require PostgreSQL. You can use Netlify Database/Postgres or another managed PostgreSQL provider. Put its connection string in Netlify environment variables as `DATABASE_URL`.

Run the schema once against the database:

```bash
psql "$DATABASE_URL" -f server/schema.sql
```

If your provider supplies SSL, use:

```text
DATABASE_SSL=true
DATABASE_SSL_REJECT_UNAUTHORIZED=true
```

## 4. Netlify environment variables

Set these in **Project configuration → Environment variables**:

- `DATABASE_URL` — PostgreSQL connection string
- `DATABASE_SSL=true`
- `DATABASE_SSL_REJECT_UNAUTHORIZED=true`
- `SESSION_COOKIE_NAME=fps_session`
- `SESSION_DAYS=30`
- `APP_ORIGIN=https://YOUR-SITE.netlify.app`
- `GOOGLE_CLIENT_ID` — Google OAuth Web Client ID
- `VITE_GOOGLE_CLIENT_ID` — same Google OAuth Web Client ID

Secrets should be entered in Netlify, not committed to Git. Netlify applies environment-variable changes on a new deploy.

## 5. Google OAuth

In Google Cloud Console, add your Netlify domain to the OAuth Web Client's authorized JavaScript origins, for example:

`https://YOUR-SITE.netlify.app`

The same client ID must be used for `GOOGLE_CLIENT_ID` and `VITE_GOOGLE_CLIENT_ID`.

## 6. Local Netlify testing

Install dependencies:

```bash
npm install
```

Then:

```bash
npm run dev:netlify
```

Open the local URL shown by Netlify. The Vite plugin emulates Netlify Functions locally.

## 7. Verify the API

Open:

`/api/health`

A working database returns JSON similar to:

```json
{"ok":true,"service":"floor-plan-studio-api","database":"connected"}
```

## Architecture

Browser → Netlify CDN/Vite build → `/api/*` → Netlify Function → PostgreSQL

The 2D/3D editor and exports remain client-side. Authentication, cloud projects and share links use the serverless API.

## Important

The old Docker/Nginx/Express production setup remains in the repository for VPS deployment, but Netlify deployment uses `netlify.toml` and `netlify/functions/api.mjs` instead.
