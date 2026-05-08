#!/usr/bin/env bash
# Installed on the Droplet as /usr/local/bin/anthemic-nginx-apply.sh (root, 755).
# Invoked by the `deploy` user via:
#     sudo /usr/local/bin/anthemic-nginx-apply.sh
#
# Expects the candidate config at /home/deploy/incoming-nginx/sites-available/anthemic-hub.conf.
# Validates with nginx -t before reloading; rolls back on failure.
set -euo pipefail

INCOMING=/home/deploy/incoming-nginx/sites-available/anthemic-hub.conf
LIVE=/etc/nginx/sites-available/anthemic-hub
BACKUP_DIR=/var/backups/nginx-anthemic
TS="$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "${INCOMING}" ]]; then
  echo "anthemic-nginx-apply: missing ${INCOMING}" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

# Snapshot current live config (if any) before touching it.
if [[ -f "${LIVE}" ]]; then
  cp -f "${LIVE}" "${BACKUP_DIR}/anthemic-hub.${TS}.conf"
fi

# Stage the new config in place; this is what nginx -t will validate.
install -o root -g root -m 644 "${INCOMING}" "${LIVE}"

# Validate. If nginx -t fails, restore backup and bail.
if ! nginx -t; then
  echo "anthemic-nginx-apply: nginx -t failed; rolling back" >&2
  if [[ -f "${BACKUP_DIR}/anthemic-hub.${TS}.conf" ]]; then
    cp -f "${BACKUP_DIR}/anthemic-hub.${TS}.conf" "${LIVE}"
    nginx -t
  else
    rm -f "${LIVE}"
  fi
  exit 1
fi

systemctl reload nginx
echo "anthemic-nginx-apply: OK (backup ${BACKUP_DIR}/anthemic-hub.${TS}.conf)"
