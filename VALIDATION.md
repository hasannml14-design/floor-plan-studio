# Floor Plan Studio — Phase 6 validation report

## Phase 6 checks completed in this environment

- `compose.production.yml` and the existing development `docker-compose.yml` parsed successfully with PyYAML; the production file contains the expected `db`, `api`, `frontend`, `gateway` and `certbot` services.
- All Bash deployment, backup, restore, certificate and shared helper scripts passed `bash -n` syntax validation.
- The PostgreSQL init script passed POSIX shell syntax validation (`sh -n`).
- The gateway's HTTP bootstrap and HTTPS Nginx configurations both passed `nginx -t` using the locally installed Nginx 1.26.3. A temporary self-signed certificate and local upstream substitutions were used only for syntax checking; no production certificate or live upstream was created.
- `Dockerfile`, gateway Dockerfile, `.dockerignore`, `.env.production.example`, `package.json` and deployment documentation were reviewed for the build/runtime split and expected paths. `package.json` parsed as valid JSON.
- The API runtime is configured with a separate non-superuser PostgreSQL role. The bootstrap SQL creates that role on first initialization, limits it to the application database/schema, and is mounted read-only into the PostgreSQL init directory.
- The backup script produces a custom-format PostgreSQL archive, verifies it with `pg_restore --list`, writes a SHA-256 sidecar and applies local retention. Restore is destructive by design and requires `CONFIRM_RESTORE=YES`.
- Phase 5 application code and source structure are retained; the Phase 6 changes focus on deployment, TLS, secrets and operations.

## Not run in this environment

- Docker Engine and the Docker Compose v2 plugin are not installed here. Therefore `docker compose config`, image builds, container health checks, container networking, actual frontend/API startup and live Nginx reverse-proxy testing were not run.
- `npm install --no-audit --no-fund` was attempted, but the npm registry request timed out. No dependency installation completed, so `npm run build`, the full Vitest suite and a browser/WebGL smoke test were not run.
- No PostgreSQL server/client is installed in this environment. The PostgreSQL init SQL, least-privilege grants, backup/restore commands and Phase 5-to-6 database migration instructions were not exercised against a live database.
- Let's Encrypt issuance/renewal requires a real public domain, DNS records and ports 80/443 reachable from the internet. No certificate was requested and no VPS was deployed.
- `shellcheck` was not available; shell syntax was checked with the interpreters, not a static shell linter.

## Recommended validation on the target VPS

After configuring `.env` and DNS, run:

```bash
./scripts/deploy.sh
./scripts/issue-certificate.sh
./scripts/backup-db.sh

docker compose -f compose.production.yml ps
curl --fail https://YOUR_DOMAIN/api/health
```

Before public launch, test registration/login, Google login (if enabled), project save/load, sharing permissions, an actual restore on a staging database, certificate renewal with `certbot renew --dry-run`, and the browser's 2D/3D/editor/export workflows. Keep encrypted off-site backups and monitor database disk usage, container health, application errors and certificate expiry.

## Important operational limitations

This is a hardened single-host Docker deployment baseline, not a high-availability platform. It does not include managed secrets, multi-region failover, automated off-site backup replication, database point-in-time recovery, zero-downtime schema migrations, multi-replica session coordination, transactional email, password reset, email verification, or real-time multi-editor conflict resolution. Phase 5 simultaneous edits still use last-write-wins snapshots. Review the included `DEPLOYMENT.md` and complete a security review before commercial public launch.
