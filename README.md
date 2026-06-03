# anthemic-ops

Infrastructure-as-code for **anthemic-developments.com** on the DigitalOcean Droplet.

Owns the active nginx **site config** for the Anthemic vhost. Each app (Set List Generator, future personal site, future bass coaching) is deployed from its own repo; this repo only routes traffic to them.

## Layout

```
nginx/
  sites-available/
    anthemic-hub.conf      ← single source of truth, deployed to /etc/nginx/sites-available/anthemic-hub
  archived/                ← prior versions kept for reference, not deployed
scripts/droplet/
  anthemic-nginx-apply.sh  ← installed at /usr/local/bin/, runs nginx -t before reload
.github/workflows/
  deploy.yml               ← push-to-main pipeline
```

> SWARM (`report.safermurrayroad.com`) is **not** managed here - it lives in the SWARM repo.

## Workflow

1. Edit `nginx/sites-available/anthemic-hub.conf`.
2. Commit + push to `main`.
3. CI rsyncs the site config (including `limit_req_zone` in `anthemic-hub.conf`), runs `sudo /usr/local/bin/anthemic-nginx-apply.sh` which:
   - backs up the current live config to `/var/backups/nginx-anthemic/`,
   - replaces it with the new one,
   - runs `nginx -t`,
   - on failure, restores the backup and exits 1 (no reload),
   - on success, `systemctl reload nginx`.
4. CI smoke-tests the public URLs (`/`, `/setlist/`, `/bass/`, `/api/v1/songs`). **`/bass/` needs files on disk** from an **anthemic-hub** deploy; if ops runs alone first, `/bass/` may 404 until hub has deployed.

Manual: **Actions → Deploy → Run workflow**.

## One-time Droplet setup

Same `deploy` user as the Set List and Hub repos. Add the apply script + sudoers entry + incoming dir for nginx.

```bash
# From this repo on your laptop
scp -P 26555 -i ~/.ssh/id_ed25519 \
  scripts/droplet/anthemic-nginx-apply.sh \
  root@170.64.232.47:/tmp/

# As root on the Droplet
sudo install -o root -g root -m 755 \
  /tmp/anthemic-nginx-apply.sh \
  /usr/local/bin/anthemic-nginx-apply.sh
rm /tmp/anthemic-nginx-apply.sh

sudo tee /etc/sudoers.d/deploy-anthemic-nginx <<'EOF'
deploy ALL=(root) NOPASSWD: /usr/local/bin/anthemic-nginx-apply.sh
EOF
sudo chmod 440 /etc/sudoers.d/deploy-anthemic-nginx
sudo visudo -cf /etc/sudoers.d/deploy-anthemic-nginx

sudo -u deploy mkdir -p /home/deploy/incoming-nginx/sites-available

# After pulling a new apply script, refresh it once as root (CI cannot sudo install):
#   sudo install -o root -g root -m 755 /home/deploy/incoming-nginx/anthemic-nginx-apply.sh /usr/local/bin/anthemic-nginx-apply.sh
```

## GitHub repository secrets

Same four as the other Anthemic repos:

| Name | Value |
|------|-------|
| `DEPLOY_HOST` | `170.64.232.47` |
| `DEPLOY_PORT` | `26555` |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_SSH_KEY` | private key matching `deploy`'s `authorized_keys` |

## Rolling back

If a bad config slips past `nginx -t` (e.g. references a path that exists today but not after a future change), restore from the backup directory the apply script leaves behind:

```bash
ssh -p 26555 -i ~/.ssh/id_ed25519 root@170.64.232.47
ls -lt /var/backups/nginx-anthemic/   # newest first
sudo cp /var/backups/nginx-anthemic/anthemic-hub.<TIMESTAMP>.conf /etc/nginx/sites-available/anthemic-hub
sudo nginx -t && sudo systemctl reload nginx
```

Then revert the bad commit in this repo so the next push is consistent.

## Bass coaching (`/bass/`)

Bass is **static HTML** deployed with the hub into `/var/www/anthemic-hub/bass/` (not a separate upstream). nginx must fall back to **`/bass/index.html`**, not `/index.html`, or `/bass/` serves the hub homepage.

1. **anthemic-hub**: CI and `anthemic-hub-deploy-apply.sh` must include `bass/**` on the droplet.
2. **anthemic-ops**: `location /bass/ { try_files $uri $uri/ /bass/index.html; }` with `root /var/www/anthemic-hub;`, then push and run the nginx deploy workflow (or copy + `nginx -t` + reload).
3. **Droplet**: reinstall `/usr/local/bin/anthemic-hub-deploy-apply.sh` from this repo if it is still an older version that omits `bass/`.

For a **containerised** bass app later, you would add an `upstream` and `proxy_pass` instead, like Set List.

## Morning Macro economics proxies

Static UI: `/var/www/anthemic-hub/economics/` (hub deploy). Live data uses **`mmd-valuation.service`** on `127.0.0.1:8071` plus nginx upstream proxies to Yahoo, Google, and FRED.

| Public path | Backend |
|-------------|---------|
| `/economics/proxy/yahoo` | `query1.finance.yahoo.com` |
| `/economics/proxy/google` | `www.google.com/finance` |
| `/economics/proxy/fred` | FRED API (`/etc/nginx/snippets/mmd-fred-api-key.conf`) |
| `/economics/proxy/fred/health` | JSON `ok` when key snippet is set |
| `/economics/proxy/valuation` | `mmd_valuation` — `?metric=` or `?metrics=` batch |
| `/economics/proxy/valuation/health` | `mmd_valuation` `/health` |
| `/economics/api/freshness` | `mmd_valuation` `/freshness` (FRED vintage footer) |

Deploy order for a new droplet: **anthemic-hub** deploy (static files, `FRED_API_KEY` → snippet + `/etc/anthemic-mmd/valuation.env`, optional `ABS_INDICATOR_API_KEY` in the same env file for AU headline macro, systemd unit) **then** **anthemic-ops** nginx deploy. CI smoke-tests valuation and freshness URLs after ops deploy.

### Rate limits (`/economics/proxy/*`)

Per-IP `limit_req` zones in `anthemic-hub.conf` (429 when exceeded):

| Zone | Paths | Rate |
|------|--------|------|
| `hub_mmd_health` | `fred/health`, `valuation/health`, `/economics/api/freshness` | 120/min |
| `hub_mmd_quote` | Yahoo, Google proxies | 120/min |
| `hub_mmd_fred` | FRED series proxy | 48/min |
| `hub_mmd_valuation` | Live valuation metrics | 18/min |

A normal dashboard refresh should stay under burst limits; scrapers get throttled.

### Uptime monitoring

- **GitHub Actions:** `.github/workflows/mmd-uptime.yml` — every 15 minutes, fast probes (health, freshness, `/economics/`). Use **workflow_dispatch** with `deep: true` for a slow BIS margin-debt check.
- **On-droplet (optional):** `scripts/mmd-uptime-check.sh` — e.g. cron `*/15 * * * * BASE_URL=https://anthemic-developments.com /path/mmd-uptime-check.sh`

**Slack on failure:** add repo secret `MMD_UPTIME_SLACK_WEBHOOK` (incoming webhook URL). If unset, the workflow falls back to `PAPAWEB_SLACK_WEBHOOK`. Failed scheduled runs post a short message with a link to the Actions log.

You can also enable GitHub **Settings → Notifications** for workflow failures.

### FRED freshness cache (hub deploy)

`mmd-valuation` caches `/freshness` FRED lookups in memory (default **300s**). Override in `/etc/anthemic-mmd/valuation.env`:

`MMD_FRED_FRESHNESS_CACHE_TTL=300`

## Related repos

- [`anthemic-hub`](https://github.com/andypapmedialight/anthemic-hub) - hub at `/` and static **`/bass/`**.
- [`SetListGenerator`](https://github.com/andypapmedialight/SetListGenerator) - `/setlist/` and `/api/`.
- (future) `anthemic-personal` - `/personal/` when ready.
