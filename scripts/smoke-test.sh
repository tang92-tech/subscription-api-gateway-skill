#!/usr/bin/env bash
set -Eeuo pipefail
mode="${1:-}"
case "$mode" in
  --local)
    curl -fsS --max-time 10 http://127.0.0.1:3000/api/status >/dev/null
    curl -fsS --max-time 10 http://127.0.0.1:1455/ >/dev/null || true
    echo 'Local service checks passed.'
    ;;
  --public)
    base="${2:?usage: TOKEN=... MODEL=... $0 --public https://host:port}"
    : "${TOKEN:?set TOKEN through a silent prompt}"
    : "${MODEL:?set MODEL from /v1/models}"
    case "$base" in https://*) ;; *) echo 'Public URL must use HTTPS' >&2; exit 2;; esac
    invalid_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$base/v1/models" -H 'Authorization: Bearer invalid-placeholder')
    [[ "$invalid_code" == 401 || "$invalid_code" == 403 ]] || { echo "Auth gate failed: HTTP $invalid_code" >&2; exit 3; }
    models=$(curl -fsS --max-time 30 "$base/v1/models" -H "Authorization: Bearer $TOKEN")
    grep -q "\"$MODEL\"" <<<"$models" || { echo "Model not present: $MODEL" >&2; exit 4; }
    body=$(printf '{"model":"%s","messages":[{"role":"user","content":"Reply with OK"}],"max_tokens":8}' "$MODEL")
    curl -fsS --max-time 120 "$base/v1/chat/completions" \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$body" >/dev/null
    echo 'Public authenticated completion passed.'
    ;;
  *) echo "usage: $0 --local | TOKEN=... MODEL=... $0 --public https://host:port" >&2; exit 1;;
esac
