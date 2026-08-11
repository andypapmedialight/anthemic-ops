#!/usr/bin/env bash
# Installed on the Droplet as /usr/local/bin/anthemic-nginx-apply.sh (root, 755).
# Invoked by the `deploy` user via:
#     sudo /usr/local/bin/anthemic-nginx-apply.sh
#
# Expects /home/deploy/incoming-nginx/sites-available/anthemic-hub.conf
# Do NOT self-update APPLY_BIN from deploy-writable incoming-nginx (root RCE).
# Update manually as root when this script changes:
#   install -m 755 -o root -g root /home/deploy/incoming-nginx/anthemic-nginx-apply.sh /usr/local/bin/anthemic-nginx-apply.sh
set -euo pipefail

INCOMING=/home/deploy/incoming-nginx/sites-available/anthemic-hub.conf
LIVE=/etc/nginx/sites-available/anthemic-hub
BACKUP_DIR=/var/backups/nginx-anthemic
TS="$(date +%Y%m%d-%H%M%S)"
SELF_INCOMING=/home/deploy/incoming-nginx/anthemic-nginx-apply.sh
APPLY_BIN=/usr/local/bin/anthemic-nginx-apply.sh

if [[ "${EUID:-$(id -u)}" -eq 0 ]] && [[ -f "${SELF_INCOMING}" ]] && [[ -f "${APPLY_BIN}" ]]; then
  if ! cmp -s "${SELF_INCOMING}" "${APPLY_BIN}" 2>/dev/null; then
    echo "anthemic-nginx-apply: WARNING: ${SELF_INCOMING} differs from ${APPLY_BIN}; not auto-updating (install manually as root)" >&2
  fi
fi

if [[ ! -f "${INCOMING}" ]]; then
  echo "anthemic-nginx-apply: missing ${INCOMING}" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

if [[ -f "${LIVE}" ]]; then
  cp -f "${LIVE}" "${BACKUP_DIR}/anthemic-hub.${TS}.conf"
fi

install -o root -g root -m 644 "${INCOMING}" "${LIVE}"

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
