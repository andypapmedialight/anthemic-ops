#!/usr/bin/env bash
# Morning Macro public endpoint checks (run on droplet via cron or manually).
# Usage: BASE_URL=https://anthemic-developments.com ./scripts/mmd-uptime-check.sh
# Exit 0 = all probes OK; non-zero = failure (suitable for cron alerting).
set -euo pipefail

BASE_URL="${BASE_URL:-https://anthemic-developments.com}"
DEEP="${MMD_UPTIME_DEEP:-0}"

probe() {
  local name="$1" url="$2" max="${3:-20}"
  local tmp
  tmp="$(mktemp)"
  local code
  code="$(curl -fsS -o "${tmp}" -w "%{http_code}" --max-time "${max}" "${url}" 2>/dev/null || echo "000")"
  if [[ "${code}" != "200" ]]; then
    echo "FAIL ${name}: HTTP ${code}" >&2
    cat "${tmp}" >&2 || true
    rm -f "${tmp}"
    return 1
  fi
  echo "OK   ${name}: HTTP ${code}"
  rm -f "${tmp}"
}

probe val-health "${BASE_URL}/economics/proxy/valuation/health" 15
probe fred-health "${BASE_URL}/economics/proxy/fred/health" 15
probe freshness "${BASE_URL}/economics/api/freshness" 30
probe economics "${BASE_URL}/economics/" 20

if [[ "${DEEP}" == "1" ]]; then
  tmp="$(mktemp)"
  code="$(curl -fsS -o "${tmp}" -w "%{http_code}" --max-time 120 \
    "${BASE_URL}/economics/proxy/valuation?metric=margin-debt" 2>/dev/null || echo "000")"
  if [[ "${code}" != "200" ]]; then
    echo "FAIL margin-debt: HTTP ${code}" >&2
    exit 1
  fi
  echo "OK   margin-debt: HTTP ${code}"
  rm -f "${tmp}"
fi

echo "mmd-uptime-check: all probes passed"
