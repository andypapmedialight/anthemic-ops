# anthemic-ops

Infrastructure-as-code for **anthemic-developments.com** on the DigitalOcean Droplet.

Owns the active nginx **site config** for the Anthemic vhost. Each app (Set List Generator, future personal site, future bass coaching) is deployed from its own repo; this repo only routes traffic to them.

## Layout

```
nginx/
  sites-available/
    anthemic-hub.conf      ← single source of truth, deployed to /etc/nginx/sites-available/anthemic-hub
  conf.d/
    anthemic-hub-limits.conf  ← limit_req_zone (http context), deployed to /etc/nginx/conf.d/
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
3. CI rsyncs the site config and `conf.d/anthemic-hub-limits.conf`, runs `sudo /usr/local/bin/anthemic-nginx-apply.sh` which:
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

sudo -u deploy mkdir -p /home/deploy/incoming-nginx/sites-available /home/deploy/incoming-nginx/conf.d
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

## Morning Macro valuation API (`/economics/proxy/valuation`)

Live BIS/FRED valuation cards are served by **`mmd-valuation.service`** on `127.0.0.1:8071`, installed by **anthemic-hub** deploy (`/opt/anthemic-mmd/`, unit from `scripts/droplet/mmd-valuation.service`). nginx proxies:

`GET /economics/proxy/valuation?metric=otc-notional` → loopback valuation server.

Deploy order for a new droplet: hub apply (installs Python + systemd unit) **then** ops nginx deploy (adds `location = /economics/proxy/valuation`). CI smoke-tests the public URL after ops deploy.

## Related repos

- [`anthemic-hub`](https://github.com/andypapmedialight/anthemic-hub) - hub at `/` and static **`/bass/`**.
- [`SetListGenerator`](https://github.com/andypapmedialight/SetListGenerator) - `/setlist/` and `/api/`.
- (future) `anthemic-personal` - `/personal/` when ready.
