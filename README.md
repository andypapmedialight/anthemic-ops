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

> SWARM (`report.safermurrayroad.com`) is **not** managed here — it lives in the SWARM repo.

## Workflow

1. Edit `nginx/sites-available/anthemic-hub.conf`.
2. Commit + push to `main`.
3. CI rsyncs the file, runs `sudo /usr/local/bin/anthemic-nginx-apply.sh` which:
   - backs up the current live config to `/var/backups/nginx-anthemic/`,
   - replaces it with the new one,
   - runs `nginx -t`,
   - on failure, restores the backup and exits 1 (no reload),
   - on success, `systemctl reload nginx`.
4. CI smoke-tests the public URLs (`/`, `/setlist/`, `/api/v1/songs`).

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

## Adding a new app to the vhost

When you add (e.g.) the bass site:

1. In `nginx/sites-available/anthemic-hub.conf`, add an `upstream anthemic_bass { server 127.0.0.1:8072; }` and a `location /bass/ { proxy_pass http://anthemic_bass/; ... }` block (mirror the Set List pattern, no API needed unless the app has one).
2. Commit + push.
3. Hub repo: switch the bass card from "Coming soon" to a real link.

## Related repos

- [`anthemic-hub`](https://github.com/andypapmedialight/anthemic-hub) — the menu page at `/`.
- [`SetListGenerator`](https://github.com/andypapmedialight/SetListGenerator) — `/setlist/` and `/api/`.
- (future) `anthemic-personal`, `anthemic-bass` — their respective paths.
