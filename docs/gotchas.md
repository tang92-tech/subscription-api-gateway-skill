# Gotchas

Real pitfalls verified on a live AlmaLinux 9 VPS deployment. Each item was reproduced and fixed in production, not inferred from documentation.

---

## Networking and routing

**1. Linux forwarding does not honor `from`-type policy routing.**
To route container traffic through a tunnel interface, the only reliable path found was: host networking + a fixed uid + `iptables mangle OUTPUT -m owner` marking + `ip rule fwmark`. Bridge networks combined with `ip rule from <subnet>` were completely ineffective (packets escaped via the main table and were rejected upstream with HTTP 403).

**2. Tunnel replies silently dropped by `rp_filter`.**
Traffic leaving but never returning is usually reverse-path filtering, not routing. A virtual gateway address can be pingable while replies are still dropped. Setting the tunnel interface's `rp_filter` to `0` (`sysctl -w net.ipv4.conf.<iface>.rp_filter=0`) fixed it immediately. `ip route get ... from <other-subnet>` reporting `Network is unreachable` is a misleading signal.

**3. The custom routing table's default route needs a virtual gateway plus `onlink`.**
`ip route replace default via <virtual-gw> dev <iface> onlink table <n>`. A bare `dev` route carries the PERVASIVE flag, cannot take `onlink`, and fails scope-link validation.

**4. Keep DNS out of the tunnel.**
Mark only `tcp --dports 80,443`. If UDP 53 is also tunneled, name resolution times out.

**5. Do not leave tunnel rules in place during Docker builds.**
Build traffic routed through the tunnel breaks package and npm mirrors (e.g. `no such package`). Remove the `ip rule` during builds and restore it afterward. Make the network script idempotent and re-runnable.

---

## Installation

**6. AlmaLinux 9 is not supported by `get.docker.com`.**
Use the CentOS repository instead:

```bash
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

---

## New API

**7. Use the Docker Hub image.**
`calciumion/new-api:latest` works. A GHCR path failed (uppercase rejected by Docker, lowercase unauthorized). Pin by digest for reproducible deployments rather than tracking `latest`.

**8. The v1.x HTTP API differs from older versions.**
First-run setup requires a `confirmPassword` field. Channel creation must nest the payload: `{"mode":"single","channel":{...}}`. Channel updates via `PUT /api/channel/` must **not** include `status`. To read a full token key use `POST /api/token/:id/key`. The self-use mode flag lives in the SQLite `options` table (`SelfUseModeEnabled`); changing it through the API option endpoint may not take effect — write the DB and restart the container.

**9. Token updates are full-field replacements, not patches (important).**
`PUT /api/token/` overwrites every field. Omitting `name`, quota, or the model whitelist clears them, and can push the token into `status=4` (quota exhausted / disabled). `status` cannot be restored through that endpoint; fix it in SQLite (`UPDATE tokens SET status=1, unlimited_quota=1, remain_quota=0, model_limits_enabled=0 WHERE id=<id>`) and restart the container. Always send the complete field set when updating a token.

**10. OpenAI-type channel `base_url` must not include `/v1`.**
The gateway appends the API path itself. Setting `https://api.example.com/v1` produces `.../v1/v1/chat/completions` and a 404 (`url.not_found`). Use `https://api.example.com`.

**11. Channel model changes must go through the API (important).**
New API routes models through a separate `abilities` table (`group/model/channel_id/enabled`). Editing `channels.models` directly in SQLite **does not update `abilities`**, producing `No available channel for model xxx` even when the channel is enabled and the group matches. Update the channel via `PUT /api/channel/` so the mapping is rebuilt. If you already edited the DB, verify with:

```sql
select "group", model, channel_id from abilities where channel_id = <id>;
```

**12. Login has a session cap.**
Repeated logins return `AUTH_SESSION_LIMIT` (HTTP 409 Conflict), which is easy to misread as a wrong password. Clear `DELETE FROM user_sessions;` to recover. Automation should reuse one access token instead of logging in per request.

**13. Open registration is enabled by default (security).**
Defaults are `RegisterEnabled=true`, `EmailVerificationEnabled=false`, `TurnstileCheckEnabled=false`. Once a panel is reachable from the internet, scanners will register accounts in bulk and each gets an auto-generated `rt-*` / `auto-*` token. Disable registration through the API (`PUT /api/option/` with `RegisterEnabled` and `PasswordRegisterEnabled` set to false) — writing the `options` table directly can be overwritten by cached state. Audit `users` and `tokens` counts periodically.

**14. Do not put nginx Basic Auth in front of a single-page app panel.**
The dashboard is a SPA that fires continuous XHR after page load. Basic Auth intercepts those requests and returns an authentication challenge; browsers handle credentials inconsistently for XHR (the same path can answer 200 and 401), so the browser prompts for credentials repeatedly and keeps prompting even after correct input. If you want an extra layer, exclude API paths with a `map` (e.g. return `off` for `~^/(api|v1|v1beta)(/|$)`) and protect only page routes — or use IP allow-listing / an access proxy instead.

**15. Provider model IDs are not what they look like.**
Always read the provider's own `GET /v1/models` rather than guessing from model names. Example: the marketing name "V4.1 Flash" maps to the API id `deepseek-flash`, not `deepseek-v4-flash`. A wrong id yields `No available channel for model ...` once routing is involved. Reasoning models may consume a small `max_tokens` budget entirely on reasoning, leaving `content` empty — allow generous token limits when testing.

**16. `sk-kimi-` style keys may belong to a dedicated coding endpoint.**
A key prefixed `sk-kimi-` belonged to a coding subscription whose endpoint is `https://api.kimi.com/coding/v1`. Pointing it at the general vendor endpoint returned `Invalid Authentication` on every attempt, which is easily misdiagnosed as an invalid key and leads to unnecessary key rotation. **Check the endpoint before replacing the key.**

---

## Gateway behavior

**17. OAuth token refresh can deadlock (important).**
Some reverse-proxy implementations only auto-refresh on HTTP 401 for specific providers. If a provider's access token is invalidated upstream while the locally stored `expiresAt` is still in the future, nothing triggers a refresh: the local copy believes the token is valid, upstream keeps returning 401, and **every model from that account becomes unusable** while the discovered model count drops. Recovery: stop the container, set the account's `expiresAt=1` and `state.needsTokenRefresh=true` in the accounts store, start the container, then **issue one real request** to trigger the lazy refresh. Deploy a periodic health-check job that performs a real completion call and self-heals on token errors.

**18. Upstream model catalogs change on the vendor's schedule.**
The reverse proxy re-discovers models periodically; treat its `/v1/models` output as the source of truth. When models are added or retired: compare the live list, update each channel's `models` via the API, verify the `abilities` mapping, then run an end-to-end call. **Do not retire an old model early** — keep it while the upstream still returns it, and remove it only after the upstream stops serving it.

**19. Quota exhaustion presents as 402 and triggers temporary model-level blocks.**
When an upstream returns `quota/rate-limit: 402`, the proxy may record `{until, reason}` blocks per model in the account state, surfacing as `no provider accounts configured for requested model` or `all accounts exhausted or unavailable`. **This is not a configuration failure.** It clears when the quota window resets; no channel change is required.

---

## Domains and TLS

**20. Custom domain checklist.**
1. If DNS is hosted behind a CDN with a wildcard record (e.g. `*.example.com`), an undefined subdomain is captured by that wildcard and points at the wildcard's target — which can produce CDN 5xx errors such as 522. Add an explicit A/AAAA record for the subdomain; specific records take precedence over wildcards.
2. When the service listens on a **non-standard port**, set the record to **DNS only** (no proxy). Proxy modes handle non-standard origin ports unreliably; DNS-only lets clients connect straight to the origin with your own certificate.
3. Diagnose with `curl --resolve <host>:<port>:<origin-ip> <url>` to bypass the CDN and reach the origin directly — this cleanly separates "service failure" from "DNS/CDN failure".
4. Automate renewal and pair it with a validation hook, e.g. a daily `certbot renew` cron job with `--deploy-hook "nginx -t && systemctl reload nginx"`.

**21. Context limits differ between the official API and a subscription relay path.**
A model's official API may advertise a much larger context window than the subscription relay path actually permits (the relay limit can align with a pricing tier boundary). Fill in the value the relay reports, not the official marketing number — otherwise clients believe there is headroom and send oversized prompts that the upstream rejects.

**22. Soft-delete columns must be written as DATETIME text, never as an integer timestamp.**
New API uses GORM soft deletes: the `deleted_at` column is a `*time.Time`, stored as DATETIME text in SQLite. If you clean up users or tokens with `UPDATE ... SET deleted_at = <unix integer>`, every API that scans that column fails with `unsupported Scan, storing driver.Value type int64 into type *time.Time`. The visible symptom is a **blank or erroring user/token list in the dashboard even though the underlying rows are intact** — easy to misdiagnose as data loss. Write `SET deleted_at = datetime('now')`, or `DELETE` the rows outright (the `logs` table preserves the audit trail). To repair existing rows: `UPDATE <table> SET deleted_at = datetime(deleted_at, 'unixepoch') WHERE typeof(deleted_at) = 'integer'`.

**23. Renaming the administrator account requires updating login references.**
A root/admin username can be changed (password, permissions, and user id stay the same), and the old username stops working immediately. After renaming, update every credential file and automation script that logs in with the old name. Dashboards and historical logs aggregate by user id, so the rename does not disturb past statistics.

**24. An empty `forward` chain with `policy drop` silently blocks all bridged-container egress.**
If nftables has a `table inet filter` whose `chain forward` is empty with `policy drop`, host-networked containers keep working while **bridged containers (image builds, `docker run`) lose all outbound connectivity**. Symptoms: DNS timeouts inside the container, `apk add` reporting `no such package`, npm fetches failing — while the host's own networking is perfectly healthy, which makes it easy to misattribute to a mirror or tunnel problem. Fix: add `ct state established,related accept` plus `iifname`/`oifname accept` rules for each docker bridge, and make it an idempotent boot-time script.

**25. A reverse proxy's tool-type allowlist governs which model capabilities survive.**
Some relays filter tools against the upstream's declared `supported_tool_types`. If upstream declares only `["function"]`, tools such as `image_generation` or `web_search` are **silently dropped** (the echoed response shows `"tools":[]` with no error). Diagnose by probing the upstream directly with each tool type before relaxing any local allowlist. Verified in practice: `image_generation` and `web_search` are accepted upstream while `computer_use_preview` is rejected with HTTP 400 — **do not blanket-allow every type**; test each one.

**26. Desktop-agent "computer use" usually comes from a local MCP server, not the API.**
Local computer-use capabilities are typically exposed by a local MCP server plus a bundled plugin, not by a model-side tool flag. When it "stops working" after switching to a custom gateway, check the local configuration first: an `enabled = false` flag, or a `command` that uses a fragile relative path. Treating it as a gateway fault wastes a lot of time.

**27. An "is there assistant output?" check must count image-generation items.**
Some relays only count `response.output_text.*`, message items, and function/custom tool calls as assistant output, and **do not recognize `item.type === "image_generation_call"`**. The consequence: upstream successfully produces a multi-megabyte image, but the relay judges the response empty, raises `empty_assistant_output`, and records an empty-response error against the account (a few of those trigger a temporary model-level block). Fix it inside the detection helper by adding an image branch — match `response.output_item.done` with `item.type === "image_generation_call"` and `status === "completed"`, and check the same inside the `response.completed` output iteration. The image payload itself usually needs no special handling, since most implementations never drop that event.

**28. Always probe with streaming when validating Codex-style clients.**
The same request can behave differently under `stream:false` (buffered rebuild path) versus `stream:true` (frame-by-frame passthrough) — buffered paths may lose non-text output items such as images, while streaming delivers them intact. Desktop agents use streaming, so a probe that omits `stream:true` and `Accept: text/event-stream` can wrongly conclude the change had no effect. Acceptance: the three `response.image_generation_call.*` events are present, `output_item.done` carries a valid base64 `result`, and the account state gains **no new** model block for that model.
