# Floor Plan Studio Web — Phase 6

A browser-based 2D/3D floor-plan editor extended with a Node.js API and PostgreSQL cloud workspace. Phase 5 builds on the Phase 1–4 editor: multi-floor plans, doors/windows, furniture, 3D visualization and the PDF/DXF/SVG/PNG/OBJ/GLB export pipeline remain in the project, with account registration, login, Google sign-in, cloud projects, automatic synchronization and share links added.

This is an independent implementation of common floor-plan workflows. It does not include proprietary Android source code or original app assets.

## Phase 5 cloud features

### Accounts and authentication
- Email/password registration and login.
- Google Identity Services sign-in; the ID credential is verified on the server with Google's OAuth client library.
- Password hashes are stored with bcrypt (12 salt rounds); the app never stores plaintext passwords.
- Opaque random session tokens are stored as SHA-256 hashes in PostgreSQL and delivered to the browser in an HTTP-only cookie.
- Sign out revokes the current database session.
- Authentication endpoints have rate limiting and request validation.

### PostgreSQL cloud workspace
- A PostgreSQL schema for users, sessions, projects, share links and optional project memberships.
- The complete multi-floor `SavedProject` JSON data model is stored in a JSONB project document so Phase 1–4 fields survive cloud save/load.
- The cloud dashboard lists owned projects and member projects, opens a cloud project and deletes projects owned by the signed-in user.
- Active work continues to save locally in IndexedDB (localStorage fallback) even when the user is signed out or offline.
- While signed in, changes are uploaded to the cloud after a 1.1-second debounce. Browser writes are serialized so an older in-flight request cannot overtake a newer snapshot. The cloud API checks the current user's owner/member rights or the supplied editor share token for every write.
- Cloud status appears in the header and editor status bar. Cloud writes are debounced by about 1.1 seconds after changes.

### Project sharing
- Create a `Viewer` link (view-only) or an `Editor` link (can edit after signing in).
- Expiry options: 1 day, 7 days, 30 days or never.
- Owners can list active links and revoke links at any time.
- Share tokens are high-entropy random values. Only their SHA-256 hashes are stored in PostgreSQL.
- The share token is placed after `#share=` in the URL fragment. Fragments are not sent in HTTP requests or referrer headers. The page exchanges the token with the API to retrieve the shared plan.
- Viewer links open the editor in a read-only mode. Editor links require an authenticated session before changes can sync to the owner's project.

### Phase 1–4 editor features retained
- Editable 2D plan canvas, wall drawing and measurement editing, snapping and room detection.
- Door/window placement, furniture library and property inspector.
- 3D scene built with React Three Fiber and Three.js.
- Multiple floors and stacked 3D view.
- PDF print sheets, DXF, SVG, high-resolution PNG, OBJ and GLB exports.

## Requirements

- Node.js 20.19+ or 22.12+.
- npm 10+.
- PostgreSQL 14+ (PostgreSQL 15+ recommended).
- A modern browser. WebGL 2 is recommended for 3D viewing.
- Google OAuth Web Client ID only if Google sign-in is required. Email/password works without Google credentials.

## 1. Configure PostgreSQL and environment

Copy `.env.example` to `.env` and edit it. Change the example local database password in both `POSTGRES_PASSWORD` and `DATABASE_URL` before starting PostgreSQL:

```bash
cp .env.example .env
```

On Windows PowerShell, use `Copy-Item .env.example .env`.

**Quick local option — Docker:** with Docker Desktop running, start the bundled PostgreSQL 16 service:

```bash
docker compose up -d postgres
```

The container creates `floor_plan_studio` with the credentials in `.env`; its database volume persists between restarts. The port is bound to `127.0.0.1` only.

**Existing PostgreSQL option:** create an empty database, for example in `psql`:

```sql
CREATE DATABASE floor_plan_studio;
```

Then set `DATABASE_URL` in `.env` to your PostgreSQL username, password, host, port and database. Never commit `.env` or put database credentials in any `VITE_` variable.

The API runs `server/schema.sql` automatically at startup. The schema uses idempotent `CREATE TABLE IF NOT EXISTS` statements and creates indexes/triggers for the project database.

Important settings:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string; server-only secret |
| `DATABASE_SSL` | Set `true` when your managed PostgreSQL provider requires TLS |
| `PORT` | API port; defaults to `4000` |
| `NODE_ENV` | Use `production` on the deployed server |
| `APP_ORIGIN` | Public website origin used to create share URLs |
| `ALLOWED_ORIGINS` | Comma-separated allowed browser origins for CORS and mutation-origin checks |
| `SESSION_DAYS` | Session lifetime in days; defaults to 30 |
| `COOKIE_SAME_SITE` | `lax` for a same-origin deployment; use `none` only for a cross-site HTTPS deployment |
| `GOOGLE_CLIENT_ID` | Google OAuth Web client ID, server-side audience verification |
| `VITE_GOOGLE_CLIENT_ID` | Same Google OAuth Web client ID, made public to the browser for the Google sign-in button |

For same-origin deployment, keep `COOKIE_SAME_SITE=lax` and serve the frontend and `/api` from the same site. When the frontend and API are on different sites, use HTTPS, `NODE_ENV=production`, `COOKIE_SAME_SITE=none`, set the frontend origin in `ALLOWED_ORIGINS`, and review browser third-party-cookie restrictions. A same-site reverse proxy is the recommended production arrangement.

## 3. Configure Google sign-in (optional)

1. Open Google Cloud Console and select or create a project.
2. Configure the OAuth consent screen / Google Auth Platform.
3. Create an OAuth Client ID of type **Web application**.
4. Add the exact local website origin (normally `http://localhost:5173`) to Authorized JavaScript origins for development.
5. For production, add the exact HTTPS website origin (for example `https://planner.example.com`).
6. Put the same Web client ID in both `GOOGLE_CLIENT_ID` and `VITE_GOOGLE_CLIENT_ID` in `.env` (leave both blank to disable Google sign-in).
7. Restart the Vite and API processes after changing `.env`.

The browser sends the Google ID credential to the backend. The backend validates its signature/audience and requires Google's `email_verified` claim before creating or linking the account. The Google client ID is public configuration; the database URL and all server secrets must remain server-side.

## 4. Install and run locally

Install all frontend and backend packages:

```bash
npm install
```

Run the React/Vite development server and Node API together:

```bash
npm run dev:all
```

Or run them separately in two terminals:

```bash
npm run server:dev
```

```bash
npm run dev
```

Open `http://localhost:5173`. Vite proxies `/api` requests to `http://localhost:4000` during development. The API health check is available at `http://localhost:4000/api/health`.

## 5. Production build and start

```bash
npm run build
npm run test:server
```

Start the API server:

```bash
npm run server:start
```

When `dist/index.html` exists, the Express server also serves the built frontend. For a single-origin deployment, deploy the project and `.env` to the Node host, configure PostgreSQL and environment values, run `npm install`, `npm run build`, then `npm run server:start`. Put the server behind HTTPS at your domain. If a reverse proxy is used, configure `TRUST_PROXY=true` only when the proxy is trusted.

The `dist/` folder can alternatively be hosted on a static platform, but configure a same-site reverse proxy for `/api` or carefully configure cross-origin cookies and CORS. Do not expose the Node server to the internet without HTTPS in production.

## Dashboard and sharing workflow

1. Open **Cloud** in the editor toolbar.
2. Register with email/password or continue with Google.
3. The active project begins cloud sync automatically. Local IndexedDB backup remains enabled.
4. Open Cloud again to see your cloud project dashboard. Select **Open** to load a saved project.
5. In **Share current project**, choose Viewer or Editor and the expiry period, then create and copy the link.
6. A Viewer can open the plan without signing in, but the plan is read-only. An Editor must sign in before edits can be synchronized.
7. The owner can revoke an active link from the Cloud workspace. A revoked or expired token no longer opens the project.

## API routes

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/api/health` | API/database health check |
| `POST` | `/api/auth/register` | Create an email/password account |
| `POST` | `/api/auth/login` | Create a session |
| `POST` | `/api/auth/google` | Verify Google ID credential and create session |
| `GET` | `/api/auth/me` | Read current session user |
| `POST` | `/api/auth/logout` | Revoke current session |
| `GET` | `/api/projects` | List owned/member cloud projects |
| `GET` | `/api/projects/:id` | Load an authorized project |
| `POST` | `/api/projects/sync` | Create/update a cloud project |
| `DELETE` | `/api/projects/:id` | Delete an owned project |
| `GET` | `/api/projects/:id/shares` | List share links (owner only) |
| `POST` | `/api/projects/:id/shares` | Create a viewer/editor link (owner only) |
| `DELETE` | `/api/projects/:id/shares/:shareId` | Revoke a share link (owner only) |
| `POST` | `/api/shares/open` | Open a valid share link (token in request body) |

## Security notes

- Parameterized SQL is used for user/project operations.
- Passwords are SHA-256 pre-hashed then bcrypt-hashed; session/share tokens are random opaque tokens whose hashes are persisted.
- Session cookies are HTTP-only, `SameSite=Lax` by default and `Secure` in production.
- Authentication routes are rate-limited; the API validates registration/login, sharing and project payloads.
- CORS and unsafe HTTP mutation origins are allow-listed. Helmet sets security headers and a Content Security Policy for the Google Identity Services script/frame.
- Share links are bearer credentials: anyone holding a live link can access the permission granted by that link. Do not post editor links publicly; revoke a link if it is exposed.
- Do not commit `.env`. Do not send `DATABASE_URL` or server credentials to the browser.

## Scope and production hardening still recommended

This is a full-stack starter implementation, not a fully operated SaaS. Before public commercial launch, configure database backups and point-in-time recovery, monitor API errors, set connection/pool limits for your hosting provider, add transactional email and email verification, implement password reset and account deletion flows, add usage/storage quotas, and conduct a security review/penetration test. Link sharing is currently URL-based (not email invitations); editors need an account to sync edits. No real-time multi-user cursor collaboration or conflict-free merge is implemented. Concurrent editors currently use last-write-wins project snapshots, so avoid editing the same project simultaneously until version/conflict handling is added.

## Source structure

```text
src/
  App.tsx
  components/
    EditorCanvas.tsx
    ThreeDView.tsx
    ExportDialog.tsx
    CloudWorkspace.tsx
  services/
    projectStorage.ts       Local IndexedDB storage
    planExport.ts           PDF/DXF/SVG/PNG/OBJ/GLB exporters
    cloudApi.ts             Cookie-authenticated cloud API client
  types/plan.ts
  geometry/
  data/
  styles.css
deploy/
  nginx/                   HTTP bootstrap and TLS reverse-proxy configurations
  postgres/                least-privilege application-role initialization
scripts/                   deployment, certificate and database backup/restore helpers
Dockerfile                 multi-stage API and frontend images
compose.production.yml     production Docker Compose stack
DEPLOYMENT.md              VPS, DNS, HTTPS, backup and recovery guide
server/
  index.js                  Express API, security headers and static host
  auth.js                   Registration, password login, Google ID verification and sessions
  projects.js               Projects, share permissions, sync and share link reads
  db.js                     PostgreSQL pool and schema initialization
  schema.sql                Users, sessions, projects, shares and member tables
  lib/security.js           Opaque token and user-safe serialization helpers
  __tests__/security.test.js
.env.example
```

## Phase 6 — Production deployment

Phase 6 adds a production Docker deployment with separate frontend, Node API and PostgreSQL services, an Nginx edge reverse proxy, Let's Encrypt HTTPS, custom-domain configuration, automated PostgreSQL backup/restore scripts, and deployment documentation.

**Start here:** read [`DEPLOYMENT.md`](./DEPLOYMENT.md). For production, copy `.env.production.example` to `.env`, configure the DNS hostname and secrets, then run `./scripts/deploy.sh` followed by `./scripts/issue-certificate.sh`. Schedule `scripts/backup-db.sh` and `scripts/renew-certificates.sh` using `deploy/backup-cron.example`.

Production Compose file: `compose.production.yml`. The existing `docker-compose.yml` remains the lightweight local-development PostgreSQL service. The runtime API connects using a dedicated non-superuser PostgreSQL role; the bootstrap/admin credential is kept out of the API container.

Never run `docker compose down -v` on a live deployment unless you intentionally want to delete its named database/certificate volumes.
