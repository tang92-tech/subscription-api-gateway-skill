# Overseas hosting: pre-flight, remote OAuth, and acceptance

Guidance for hosting this stack on a datacenter outside the mainland (Hong Kong, Singapore, US, EU). Geography is rarely the blocker. Two machine-level properties are: **egress reputation** and **where the OAuth callback lands**.

## 1. Pre-flight — run these before `docker compose up`

| # | What | Command | Pass |
| - | ---- | ------- | ---- |
| 1 | Plan accepts the region | read the plan / supported-regions list | paid tier in a supported region |
| 2 | Egress IP is not challenged by the upstream edge | `curl -s -o /dev/null -w '%{http_code}\n' https://chatgpt.com/` | `200` / `302` |
| 3 | OAuth host reachable | `curl -s -o /dev/null -w '%{http_code}\n' https://auth.openai.com/` | anything but timeout |
| 4 | Docker present | `docker compose version` | v2 |
| 5 | Ports free and loopback-only | `ss -lntp \| grep -E '1455\|3000'` | nothing, or `127.0.0.1` only |

Check 2 is the one that silently ruins an install. A `403` whose body contains `__cf_chl_opt`, `Enable JavaScript and cookies to continue`, or `cZone:` is a challenged datacenter IP: OAuth may still complete, and then **every** model call fails afterwards. Fix it before building anything — egress the relay through a clean exit (a WARP-style tunnel, or a second small host with clean egress) or host the relay where the egress is clean.

## 2. Remote OAuth login — the `localhost` constraint

The relay serves its dashboard and its OAuth callback on `127.0.0.1:1455`, and the upstream OAuth client only registers `http://localhost:1455/auth/callback`.

**The browser that finishes authorization must be able to reach `localhost:1455` on the machine running the relay.**

Supported ways:

```bash
# from the operator's own computer, not the server
ssh -L 1455:127.0.0.1:1455 <user>@<server>
# then browse http://localhost:1455 and sign in with MULTIVIBE_ADMIN_TOKEN
```

- The device-code flow in the dashboard also works and needs no callback at all — prefer it when the operator cannot open an SSH tunnel.
- Browser-callback flow: after authorizing, the browser is redirected to a `localhost:1455…` URL; with the tunnel open it reaches the relay and the account is added.

**Anti-pattern:** publishing the dashboard through nginx/Cloudflare and logging in from a remote browser. The redirect lands on the operator's own laptop, the tab shows a connection error, and the dashboard waits forever. Rewriting `OAUTH_REDIRECT_URI` to a public URL does not help — the registered client rejects any callback that is not localhost.

**Diagnostic:** keep `docker compose logs -f multivibe` open while clicking login. No callback line in the log means the browser never reached the server — a routing problem, not a credential problem.

## 3. Acceptance gates (do not hand over before all four pass)

```bash
# 1. relay is alive
curl -s http://127.0.0.1:1455/health

# 2. relay can really talk upstream (a real completion, not just /models)
curl -s http://127.0.0.1:1455/v1/chat/completions \
  -H "Authorization: Bearer $MULTIVIBE_PROXY_KEY" -H 'Content-Type: application/json' \
  -d '{"model":"<exposed-model>","messages":[{"role":"user","content":"只回复OK"}],"max_tokens":32}'

# 3. gateway serves the same model through the public entry
curl -s https://<gateway-host>/v1/chat/completions \
  -H "Authorization: Bearer <token-key>" -H 'Content-Type: application/json' \
  -d '{"model":"<exposed-model>","messages":[{"role":"user","content":"只回复OK"}],"max_tokens":32}'

# 4. the union of models the client sees matches the channel lists
curl -s https://<gateway-host>/v1/models -H "Authorization: Bearer <token-key>"
```

A `200` on `/v1/models` alone proves nothing — the chat path is what fails when egress is challenged or a model is only half-routed.

## 4. Bring-up order that avoids rework

1. `docker compose up -d multivibe` → open the tunnel → complete OAuth → confirm the account appears with its quota windows.
2. Confirm the relay log shows the expected upstream catalog size (`[model-cache] … N models available`).
3. `docker compose up -d new-api` → first-run setup → create the channel pointing at `http://127.0.0.1:1455` with key = `MULTIVIBE_PROXY_KEY` and `base_url` **without** `/v1`.
4. Sync the channel `models` with what the relay actually exposes, then create one token per person/product.
5. Run the four acceptance gates. Then, and only then, publish the client config.

## 5. Traps that are specific to this kind of host

| Symptom | Cause | Fix |
| --- | --- | --- |
| Dashboard spins forever after authorization | callback hit the operator's laptop, not the relay | SSH tunnel or device-code flow (section 2) |
| OAuth fine, every completion `403` / challenge page | egress IP challenged by the upstream edge | clean egress, or move the relay (section 1) |
| Account authorizes but never appears | `data/` owned by root; the container runs as uid `10001` and cannot write `accounts.json` | `chown -R 10001:10001 data/` |
| Model list much shorter than expected | catalog is gated by the advertised client version (see gotchas) | raise `MODELS_CLIENT_VERSION`, recreate the container |
| Single model returns `no provider accounts configured` | a stale per-account model block, or the model is not in the discovered catalog | clear the block via the relay admin API; check the catalog |
| Same ChatGPT account used in two places | refresh-token rotation invalidates the other holder | one account per installation |
| `429` right after a successful login | subscription usage window exhausted | wait for the window; not a configuration fault |

## 6. Handing the build to an AI agent

When the work is delegated to an assistant, give it this file plus `gotchas.md`, and require it to:

1. run section 1 checks **first** and report the raw HTTP codes before changing anything;
2. use the SSH tunnel or device-code flow for OAuth — never a reverse proxy;
3. stop and ask if check 2 fails, instead of proceeding and debugging symptoms later;
4. leave the dashboard and API ports bound to loopback, exposing only the TLS entry;
5. prove acceptance with the four gates and paste the responses.

A brief written that way prevents the two failure modes that dominate partner installs: fixing the gateway when the problem is egress, and treating an OAuth callback that never arrived as a credential error.
