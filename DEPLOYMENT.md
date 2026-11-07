# Floor Plan Studio — Phase 6 Production Deployment

This guide deploys the Phase 5 application as four containers:

- **gateway** — public Nginx reverse proxy on ports 80/443; selects HTTP bootstrap or HTTPS configuration based on certificate availability.
- **frontend** — static React/Vite build served by Nginx on the private Compose network.
- **api** — Node.js/Express API on the private Compose network.
- **db** — PostgreSQL 16 with a persistent named volume.

Certbot is an on-demand utility container. The database bootstrap/admin role and the API runtime role are separate; the API is not a PostgreSQL superuser. The database and API are not published to the host. Browser traffic stays same-origin (`https://DOMAIN` and `https://DOMAIN/api`), so the existing HTTP-only session cookie works with `SameSite=Lax`.

## 1. Server prerequisites

Use a Linux VPS or dedicated host with:

- Docker Engine and the Docker Compose v2 plugin.
- A DNS name you control.
- Public inbound TCP ports **80 and 443** open in the VPS firewall and hosting-provider firewall.
- A DNS **A** record for `DOMAIN` pointing to the server's public IPv4 address. Add an **AAAA** record only when IPv6 is correctly routed to this same server; remove stale AAAA records.
- `curl`, `openssl`, and `bash` for the helper scripts.

A practical starting point is 2 vCPU, 2–4 GB RAM and sufficient disk for PostgreSQL plus backups. Actual sizing depends on the number and size of projects.

## 2. Put the source on the server and configure secrets

Copy/extract the Phase 6 source to a stable directory, for example `/opt/floor-plan-studio`, then:

```bash
cd /opt/floor-plan-studio
cp .env.production.example .env
openssl rand -hex 32
```

Generate two independent secrets with `openssl rand -hex 32`: one for the database bootstrap/admin role (`POSTGRES_PASSWORD`) and one for the least-privilege API role (`APP_DB_PASSWORD`). Edit `.env`, then restrict its permissions with `chmod 600 .env`:

```dotenv
DOMAIN=planner.example.com
ACME_EMAIL=admin@example.com
POSTGRES_DB=floor_plan_studio
POSTGRES_ADMIN_USER=fps_admin
POSTGRES_PASSWORD=PASTE_ADMIN_64_CHARACTER_HEX_SECRET
APP_DB_USER=fps_app
APP_DB_PASSWORD=PASTE_APP_64_CHARACTER_HEX_SECRET
GOOGLE_CLIENT_ID=
VITE_GOOGLE_CLIENT_ID=
IMAGE_TAG=latest
PG_POOL_MAX=10
SESSION_DAYS=30
SESSION_COOKIE_NAME=fps_session
```

`POSTGRES_PASSWORD` is the database bootstrap/admin password and `APP_DB_PASSWORD` belongs to the API runtime role. Both are URL-safe hex strings because Compose constructs the internal PostgreSQL URL from `APP_DB_PASSWORD`. The API role is created without superuser, database-creation or role-creation privileges and owns the application database public schema (and is not a superuser), which lets the API manage its tables and lets the restore script replace schema objects. Keep `.env` private; it is excluded from Docker build contexts and Git. The init script runs only when PostgreSQL initializes an empty data volume; preserve both credentials when reusing an existing volume.

For Google Login, use the same Google OAuth **Web Client ID** in `GOOGLE_CLIENT_ID` and `VITE_GOOGLE_CLIENT_ID`. Add `https://DOMAIN` to **Authorized JavaScript origins** in Google Cloud Console. Email/password login works when these values are blank.

## 3. First deployment (HTTP bootstrap)

After DNS resolves to the server and ports 80/443 are reachable:

```bash
./scripts/deploy.sh
```

The script validates Compose configuration, builds images, starts all four services, and displays service status. Until a certificate exists, the gateway serves the domain over HTTP only and exposes the ACME challenge path. This is a short bootstrap state; do not send user credentials over HTTP.

Check service status and logs:

```bash
docker compose -f compose.production.yml ps
docker compose -f compose.production.yml logs --tail=100 api gateway db
```

## 4. Issue HTTPS certificate

Run:

```bash
./scripts/issue-certificate.sh
```

The script waits for the HTTP gateway, requests a Let's Encrypt certificate using the webroot HTTP-01 challenge, then recreates the gateway. Its startup selector detects the certificate and activates the HTTPS Nginx configuration. The gateway redirects normal HTTP requests to HTTPS and continues serving the ACME challenge path on port 80 for renewal.

Open `https://DOMAIN`. The health endpoint is `https://DOMAIN/api/health` and should report `{ "ok": true, "database": "connected" }`.

If issuance fails, check DNS A/AAAA records, port 80 firewall rules, domain spelling, clock accuracy, and:

```bash
docker compose -f compose.production.yml logs gateway
docker compose -f compose.production.yml --profile tools run --rm certbot certificates
```

Do not manually create files under the Let's Encrypt volume. Certbot owns its contents.

## 5. Migrate an existing Phase 5 PostgreSQL database

The production Compose stack uses a new named volume and a separate least-privilege application role. Do not point the production API at the old development database volume directly. Export the Phase 5 database as a PostgreSQL custom archive, copy it to the Phase 6 server, start Phase 6 once (so its database and `fps_app` role are initialized), then restore the archive:

```bash
# On the Phase 5 host (adjust the Compose filename if your local file differs)
docker compose exec -T postgres sh -c \
  'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_dump -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl' \
  > phase5-projects.dump

# Copy phase5-projects.dump to the Phase 6 server, for example into backups/
./scripts/deploy.sh
# Stop application writes before restoring.
docker compose -f compose.production.yml stop api
# Run this during a maintenance window; it replaces existing database objects.
CONFIRM_RESTORE=YES ./scripts/restore-db.sh backups/phase5-projects.dump
docker compose -f compose.production.yml start api
./scripts/issue-certificate.sh
```

This restores the user, session, project and sharing tables under the Phase 6 runtime role. Ask users to sign in again if the old sessions are not intended to remain valid. Keep the original Phase 5 dump until the new deployment has been verified.

## 6. Deploy updates

After uploading a new source version:

```bash
./scripts/backup-db.sh
./scripts/deploy.sh
```

`deploy.sh` builds and starts the updated images. Docker Compose keeps the PostgreSQL named volume. The API applies the idempotent `server/schema.sql` at startup. For rollback, retain the previous source/image tag and restore a database backup only when the schema/data compatibility is understood.

To inspect status:

```bash
docker compose -f compose.production.yml ps
docker compose -f compose.production.yml logs -f api
```

## 7. Automated PostgreSQL backup

Create a backup manually:

```bash
./scripts/backup-db.sh
```

The script creates a PostgreSQL custom-format archive in `backups/`, verifies it with `pg_restore --list`, writes a SHA-256 checksum, restricts file permissions, and deletes local backup files older than `BACKUP_RETENTION_DAYS` (default 30). Override for a one-off run:

```bash
BACKUP_RETENTION_DAYS=60 ./scripts/backup-db.sh
```

Install scheduled backup and certificate renewal jobs. Review `deploy/backup-cron.example`, replace the sample directory with the real absolute path, then install with `crontab -e`. Create a writable `logs/` directory (`mkdir -p logs && chmod 700 logs`) first. Run as the deployment user that can access Docker. Check cron logs and periodically test a restore on a separate staging database/server.

**Important:** backups in `./backups` are on the same server as the database. They protect against accidental deletion and some corruption, but not server/disk loss. Copy encrypted backups off-site (object storage or a separate backup host), restrict access, and periodically test recovery. Database dumps contain user emails and floor-plan project data.

## 8. Restore a database backup (destructive)

First make a fresh backup and stop application writes (maintenance window):

```bash
./scripts/backup-db.sh
docker compose -f compose.production.yml stop api
```

Then restore a known archive. The script checks its checksum when the `.sha256` sidecar is present and refuses to run without explicit confirmation:

```bash
CONFIRM_RESTORE=YES ./scripts/restore-db.sh backups/floor-plan-studio-YYYYMMDDTHHMMSSZ.dump
```

Restore replaces existing database objects. Start the API and check health:

```bash
docker compose -f compose.production.yml start api
curl --fail https://DOMAIN/api/health
```

Replace `DOMAIN` in the curl example with the configured hostname. Never run restore against the live database without a verified pre-restore backup.

## 9. Certificate renewal

Let's Encrypt certificates are renewed with:

```bash
./scripts/renew-certificates.sh
```

The script runs `certbot renew` and reloads Nginx so renewed certificates are used. Schedule it daily using the sample cron entry. Certbot only renews when a certificate is due; running the command daily is safe and avoids excessive issuance requests.

## 10. Firewall and network exposure

Only ports 80 and 443 should be publicly reachable for the application (plus your restricted SSH port). Do **not** publish PostgreSQL 5432 or Node API 4000. They are reachable only on the private Docker Compose network. The frontend container is similarly private; the gateway is the only public web entry point.

Example UFW rules (adapt SSH port and policy before applying):

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

The API trusts one reverse-proxy hop (`TRUST_PROXY=true` is set in Compose), matching the included gateway topology. If another proxy/CDN is added in front, revisit forwarded-IP trust and TLS mode rather than blindly increasing the trust count.

## 11. Useful commands

```bash
# Live logs
docker compose -f compose.production.yml logs -f

# Restart the application tier
docker compose -f compose.production.yml restart api frontend gateway

# Validate rendered Compose configuration
docker compose -f compose.production.yml config

# See disk usage, including the PostgreSQL volume
docker system df

docker volume ls | grep floor-plan-studio
```

Do not use `docker compose down -v` for routine maintenance: `-v` deletes the PostgreSQL and certificate volumes. Use `docker compose down` only when you understand the service downtime; named volumes are preserved without `-v`.

## 12. Operational/security checklist before public launch

- [ ] `.env` has unique strong secrets and restrictive file permissions (`chmod 600 .env`).
- [ ] `DOMAIN` DNS records and public TCP ports 80/443 are correct.
- [ ] HTTPS works and HTTP redirects to HTTPS.
- [ ] Google OAuth origin/client ID is correct if Google Login is enabled.
- [ ] Database/API ports are not publicly published.
- [ ] Daily backup and certificate-renewal schedules are installed and monitored.
- [ ] A backup was copied off-site and a restore was tested.
- [ ] Disk usage, Docker logs, API errors and certificate expiry are monitored.
- [ ] Email verification, password reset, account deletion, abuse/usage quotas, concurrent edit conflict resolution and a formal security review are addressed before commercial SaaS launch.

This deployment is a hardened single-host Docker baseline, not a high-availability cluster. It does not include managed secrets, multi-region failover, automated off-site object-storage backup, zero-downtime migrations, or multi-replica shared-session orchestration.
