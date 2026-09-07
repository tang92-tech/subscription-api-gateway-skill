#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
: "${DOMAIN:?set DOMAIN}"
: "${CERT_FILE:?set CERT_FILE}"
: "${KEY_FILE:?set KEY_FILE}"
LISTEN_PORT="${LISTEN_PORT:-8443}"
[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || { echo 'Invalid DOMAIN' >&2; exit 2; }
[[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || { echo 'Invalid LISTEN_PORT' >&2; exit 2; }
[[ -r "$CERT_FILE" && -r "$KEY_FILE" ]] || { echo 'Certificate/key not readable' >&2; exit 3; }
command -v nginx >/dev/null || { echo 'nginx not installed' >&2; exit 4; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT=/etc/nginx/conf.d/subscription-api-gateway.conf
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
[[ -e "$OUT" ]] && cp -a "$OUT" "$OUT.$STAMP.bak"
sed \
  -e "s|__DOMAIN__|$DOMAIN|g" \
  -e "s|__LISTEN_PORT__|$LISTEN_PORT|g" \
  -e "s|__CERT_FILE__|$CERT_FILE|g" \
  -e "s|__KEY_FILE__|$KEY_FILE|g" \
  "$ROOT/templates/nginx.conf.template" > "$OUT"
if ! nginx -t; then
  rm -f "$OUT"
  [[ -e "$OUT.$STAMP.bak" ]] && mv "$OUT.$STAMP.bak" "$OUT"
  echo 'nginx validation failed; previous config restored' >&2
  exit 5
fi
systemctl reload nginx
echo "nginx installed: https://$DOMAIN:$LISTEN_PORT"
