#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/versions.env"
TARGET="${TARGET_DIR:-/opt/subscription-api-gateway}"

for v in MULTIVIBE_REPO MULTIVIBE_COMMIT NEW_API_IMAGE; do
  [[ -n ${!v:-} ]] || { echo "Missing pin: $v" >&2; exit 2; }
done

if [[ -e "$TARGET/.env" ]]; then
  echo "$TARGET already has .env; refusing to overwrite. Use the documented upgrade flow." >&2
  exit 3
fi

"$REPO_ROOT/scripts/preflight.sh"
install -d -m 0750 "$TARGET" "$TARGET/vendor" "$TARGET/data/new-api" "$TARGET/data/multivibe" "$TARGET/backups"

if ! getent group 10001 >/dev/null; then groupadd --system --gid 10001 subgateway; fi
if ! getent passwd 10001 >/dev/null; then
  useradd --system --uid 10001 --gid 10001 --home-dir "$TARGET" --shell /usr/sbin/nologin subgateway
fi
if [[ $(getent passwd 10001 | cut -d: -f1) != subgateway ]]; then
  echo 'uid 10001 is owned by another user; stop and choose a reviewed PROXY_UID.' >&2
  exit 4
fi
chown -R 10001:10001 "$TARGET/data/multivibe"

cp "$REPO_ROOT/templates/compose.yaml" "$TARGET/compose.yaml"
cp "$REPO_ROOT/versions.env" "$TARGET/versions.env"
cat > "$TARGET/.env" <<ENV
MULTIVIBE_ADMIN_TOKEN=$(openssl rand -hex 32)
MULTIVIBE_PROXY_KEY=$(openssl rand -hex 32)
NEWAPI_SESSION_SECRET=$(openssl rand -hex 32)
PROXY_MODELS=gpt-placeholder
PROXY_UID=10001
PROXY_GID=10001
TZ=UTC
MULTIVIBE_COMMIT=$MULTIVIBE_COMMIT
NEW_API_IMAGE=$NEW_API_IMAGE
ENV
chmod 600 "$TARGET/.env"

mkdir -p "$TARGET/vendor/multivibe"
git -C "$TARGET/vendor/multivibe" init -q
git -C "$TARGET/vendor/multivibe" remote add origin "$MULTIVIBE_REPO"
git -C "$TARGET/vendor/multivibe" fetch -q --depth 1 origin "$MULTIVIBE_COMMIT"
git -C "$TARGET/vendor/multivibe" checkout -q --detach FETCH_HEAD
[[ $(git -C "$TARGET/vendor/multivibe" rev-parse HEAD) == "$MULTIVIBE_COMMIT" ]] || { echo 'MultiVibe pin mismatch' >&2; exit 5; }

cp "$REPO_ROOT/templates/admin-ports.nft" /etc/nftables/subscription-gateway.nft
cp "$REPO_ROOT/templates/subscription-gateway-firewall.service" /etc/systemd/system/subscription-gateway-firewall.service
systemctl daemon-reload
systemctl enable --now subscription-gateway-firewall.service

cd "$TARGET"
docker compose config -q
docker compose up -d --build

echo
printf '%s\n' 'Infrastructure launched.'
printf 'Admin token is stored only in %s/.env (mode 600).\n' "$TARGET"
printf '%s\n' 'Next: open an SSH tunnel for localhost:1455 and localhost:3000, then complete OAuth and New API setup personally.'
