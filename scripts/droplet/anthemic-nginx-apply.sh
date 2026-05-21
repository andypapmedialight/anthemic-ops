#!/usr/bin/env bash
# Installed on the Droplet as /usr/local/bin/anthemic-nginx-apply.sh (root, 755).
# Invoked by the `deploy` user via:
#     sudo /usr/local/bin/anthemic-nginx-apply.sh
#
# Expects:
#   /home/deploy/incoming-nginx/sites-available/anthemic-hub.conf
#   /home/deploy/incoming-nginx/conf.d/anthemic-hub-limits.conf  (limit_req_zone for contact API)
# Validates with nginx -t before reloading; rolls back on failure.
set -euo pipefail

INCOMING=/home/deploy/incoming-nginx/sites-available/anthemic-hub.conf
INCOMING_LIMITS=/home/deploy/incoming-nginx/conf.d/anthemic-hub-limits.conf
LIVE=/etc/nginx/sites-available/anthemic-hub
LIVE_LIMITS=/etc/nginx/conf.d/anthemic-hub-limits.conf
BACKUP_DIR=/var/backups/nginx-anthemic
TS="$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "${INCOMING}" ]]; then
  echo "anthemic-nginx-apply: missing ${INCOMING}" >&2
  exit 1
fi
if [[ ! -f "${INCOMING_LIMITS}" ]]; then
  echo "anthemic-nginx-apply: missing ${INCOMING_LIMITS}" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

# Snapshot current live configs (if any) before touching them.
if [[ -f "${LIVE}" ]]; then
  cp -f "${LIVE}" "${BACKUP_DIR}/anthemic-hub.${TS}.conf"
fi
if [[ -f "${LIVE_LIMITS}" ]]; then
  cp -f "${LIVE_LIMITS}" "${BACKUP_DIR}/anthemic-hub-limits.${TS}.conf"
fi

install -o root -g root -m 644 "${INCOMING}" "${LIVE}"
install -o root -g root -m 644 "${INCOMING_LIMITS}" "${LIVE_LIMITS}"

# Validate. If nginx -t fails, restore backups and bail.
if ! nginx -t; then
  echo "anthemic-nginx-apply: nginx -t failed; rolling back" >&2
  if [[ -f "${BACKUP_DIR}/anthemic-hub.${TS}.conf" ]]; then
    cp -f "${BACKUP_DIR}/anthemic-hub.${TS}.conf" "${LIVE}"
  else
    rm -f "${LIVE}"
  fi
  if [[ -f "${BACKUP_DIR}/anthemic-hub-limits.${TS}.conf" ]]; then
    cp -f "${BACKUP_DIR}/anthemic-hub-limits.${TS}.conf" "${LIVE_LIMITS}"
  else
    rm -f "${LIVE_LIMITS}"
  fi
  nginx -t
  exit 1
fi

systemctl reload nginx
echo "anthemic-nginx-apply: OK (backup ${BACKUP_DIR}/anthemic-hub.${TS}.conf)"
