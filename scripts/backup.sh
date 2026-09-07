#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
TARGET="${TARGET_DIR:-/opt/subscription-api-gateway}"
[[ -d "$TARGET/data" && -f "$TARGET/.env" ]] || { echo 'Deployment not found' >&2; exit 2; }
stamp=$(date -u +%Y%m%dT%H%M%SZ)
out="$TARGET/backups/$stamp.tar.gz"
umask 077
tar -czf "$out" -C "$TARGET" .env data compose.yaml versions.env
chmod 600 "$out"
find "$TARGET/backups" -type f -name '*.tar.gz' -printf '%T@ %p\n' | sort -nr | awk 'NR>5{$1=""; sub(/^ /,""); print}' | xargs -r rm -f
echo "$out"
