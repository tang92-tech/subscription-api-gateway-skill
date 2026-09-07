#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
TARGET="${TARGET_DIR:-/opt/subscription-api-gateway}"
archive="${1:?usage: sudo $0 /opt/subscription-api-gateway/backups/<timestamp>.tar.gz}"
real_target=$(realpath "$TARGET/backups")
real_archive=$(realpath "$archive")
[[ "$real_archive" == "$real_target"/* && -f "$real_archive" ]] || { echo 'Archive must be inside deployment backups/' >&2; exit 2; }
"$(dirname "$0")/backup.sh" >/dev/null
cd "$TARGET"
docker compose down
rm -rf data
mkdir -p data
tar -xzf "$real_archive" -C "$TARGET"
chmod 600 .env
docker compose config -q
docker compose up -d
"$(dirname "$0")/smoke-test.sh" --local
