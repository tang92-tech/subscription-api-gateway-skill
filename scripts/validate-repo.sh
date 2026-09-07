#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/scripts/safety_scan.py" "$ROOT"
for f in AGENTS.md SKILL.md README.md SECURITY.md THIRD_PARTY_NOTICES.md versions.env templates/compose.yaml; do
  [[ -s "$ROOT/$f" ]] || { echo "Missing $f" >&2; exit 2; }
done
grep -q '^name: subscription-api-gateway$' "$ROOT/SKILL.md"
grep -q '^description:' "$ROOT/SKILL.md"
grep -q 'MULTIVIBE_COMMIT=[0-9a-f]\{40\}' "$ROOT/versions.env"
grep -q 'NEW_API_IMAGE=.*@sha256:[0-9a-f]\{64\}' "$ROOT/versions.env"
if command -v shellcheck >/dev/null; then shellcheck "$ROOT"/scripts/*.sh; else echo 'WARN: shellcheck not installed'; fi
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  set -a; source "$ROOT/templates/.env.example"; source "$ROOT/versions.env"; set +a
  (cd "$ROOT" && docker compose -f templates/compose.yaml config -q)
else
  echo 'WARN: Docker Compose unavailable; skipped compose validation'
fi
echo 'Repository validation passed.'
