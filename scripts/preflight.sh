#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

printf '%s\n' '== OS ==' 
uname -a
[[ -r /etc/os-release ]] && cat /etc/os-release
printf '%s\n' '== Resources =='
free -h 2>/dev/null || true
df -h /
printf '%s\n' '== Required commands =='
missing=0
for c in git docker openssl curl nft sed awk; do
  if command -v "$c" >/dev/null; then printf 'OK   %s\n' "$c"; else printf 'MISS %s\n' "$c"; missing=1; fi
done
if docker compose version >/dev/null 2>&1; then echo 'OK   docker compose'; else echo 'MISS docker compose v2'; missing=1; fi
printf '%s\n' '== Existing listeners =='
ss -lntup 2>/dev/null || true
printf '%s\n' '== Existing services =='
systemctl is-active nginx docker nftables 2>/dev/null || true
printf '%s\n' '== Existing compose projects =='
docker compose ls 2>/dev/null || true

if ss -H -lnt '( sport = :1455 or sport = :3000 )' 2>/dev/null | grep -q .; then
  echo 'BLOCKED: port 1455 or 3000 is already in use. Inventory and choose a safe migration.' >&2
  exit 2
fi
(( missing == 0 )) || { echo 'Install missing prerequisites after user approval.' >&2; exit 3; }
echo 'Preflight passed. No changes were made.'
