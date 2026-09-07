---
name: subscription-api-gateway
summary: Deploy an authorized, self-hosted OpenAI-compatible gateway for a user's own Codex/ChatGPT subscription, with New API token management, TLS, auditing, rollback, and optional official API channels.
description: "Deploy and verify an authorized self-hosted subscription API gateway using MultiVibe, New API, Docker and nginx. Use when a user asks Codex to turn an owned Codex/ChatGPT subscription into an OpenAI-compatible endpoint, issue separate client tokens, add official API providers, diagnose routing, or perform safe upgrades and rollback. Requires explicit account and server authorization; never use for resale, public sharing, credential theft, or bypassing provider safeguards."
---

# Subscription API Gateway Skill

Deploy the infrastructure, pause for the account owner to complete OAuth, then expose one authenticated OpenAI-compatible HTTPS endpoint through New API.

## When to Use This Skill

Use when the user asks to:

- deploy an API gateway for a Codex/ChatGPT subscription they own;
- install or repair MultiVibe + New API + nginx on an authorized VPS;
- issue one revocable New API token per authorized teammate;
- add official OpenAI-compatible API channels such as DeepSeek or Kimi;
- verify `/v1/models`, chat completions, TLS, local-only admin ports, backups, or rollback.

## Not For / Boundaries

Hard stop when any item applies:

1. The user does not own, or lacks explicit permission to administer, the account or VPS.
2. The goal is resale, public quota sharing, account farming, bypassing abuse controls, or unauthorized access.
3. The requested deployment conflicts with the provider's current terms. Tell the user to use an official API or team/business plan.
4. A secret appears in chat, tracked files, command output, screenshots, or logs. Rotate it before continuing.
5. Existing nginx, firewall, Docker, VPN, or port ownership is not understood. Inventory first; never replace blindly.
6. OAuth is pending. A human must complete it in their own browser; Codex must not handle passwords, 2FA, or recovery codes.
7. The upstream blocks the VPS or rejects the model. Do not automate evasion; stop and offer an approved egress or official API path.

This repository is automation and documentation, not a hosted service or a promise that a subscription permits API redistribution.

## Required Inputs

Ask only for non-secret inputs first:

- SSH host, SSH port, SSH user, and confirmation that key-based SSH is ready;
- target OS and architecture;
- domain (recommended) or temporary TLS hostname;
- desired public HTTPS port and known ports already in use;
- whether nginx/Docker/firewall/VPN already exist;
- account ownership and intended authorized users;
- whether to add only subscription routing or also official API channels.

Secrets must be entered through a silent terminal prompt or created on the VPS. Never echo them.

## Quick Reference

```bash
# 1. Validate the cloned repository locally
./scripts/validate-repo.sh

# 2. Copy/clone it to the authorized VPS, then run as root
sudo ./scripts/deploy.sh

# 3. Open local-only dashboards through an SSH tunnel
ssh -N \
  -L 1455:127.0.0.1:1455 \
  -L 3000:127.0.0.1:3000 \
  -p <SSH_PORT> <SSH_USER>@<VPS_HOST>

# 4. After OAuth + New API setup, test from the VPS
sudo ./scripts/smoke-test.sh --local

# 5. After TLS, test from a client without printing its token
read -rsp "Client API token: " TOKEN; echo
TOKEN="$TOKEN" MODEL="<model-from-v1-models>" \
  ./scripts/smoke-test.sh --public https://<domain>:<port>
unset TOKEN
```

## Codex Execution Contract

### Phase 0 — Repository and authorization gate

1. Read this file, `docs/index.md`, `docs/legal.md`, and `versions.env`.
2. Run `./scripts/validate-repo.sh`.
3. Confirm ownership, scope, ports, rollback plan, and that no secret was pasted into chat.
4. Present the exact planned commands and ask before touching the VPS.

Acceptance: local validation passes and the user approves the server plan.

### Phase 1 — Server inventory and preflight

Run `sudo ./scripts/preflight.sh` on the VPS. Record OS, RAM, disk, port listeners, nginx/firewall/VPN state, Docker version, and existing compose projects. Do not modify anything in this phase.

Acceptance: no unexplained conflict on ports 1455/3000 or the chosen public port; rollback path is known.

### Phase 2 — Pinned bootstrap

Run `sudo ./scripts/deploy.sh`. It:

- verifies `versions.env` pins;
- creates a dedicated uid/gid and `/opt/subscription-api-gateway`;
- fetches the pinned MultiVibe commit;
- installs the pinned New API image reference;
- generates random local secrets into `.env` mode `600`;
- launches the two local services;
- blocks direct non-loopback access to admin ports 1455 and 3000.

Acceptance: both containers are healthy/running, and admin ports reject non-loopback traffic.

### Phase 3 — Human OAuth checkpoint

Ask the user to open the SSH tunnel shown above. The user visits `http://localhost:1455`, logs into the dashboard using the on-server admin token, and completes the provider device/OAuth flow personally.

Codex must never request or view account passwords, 2FA, session cookies, refresh tokens, or recovery codes.

Acceptance: the dashboard shows an enabled owned account and `/v1/models` returns at least one model through the internal proxy key.

### Phase 4 — New API initialization

Through `http://localhost:3000`, the user initializes New API. Create an OpenAI-compatible channel with:

- Base URL `http://127.0.0.1:1455` (no `/v1` in New API channel base URLs);
- internal MultiVibe proxy key from the server `.env`;
- model names copied from MultiVibe `/v1/models`;
- low concurrency and automatic-disable policy chosen explicitly.

Create one revocable token per authorized person. Do not share the internal MultiVibe key.

Acceptance: a New API client token can call a discovered model locally.

### Phase 5 — TLS and public endpoint

Use `scripts/install-nginx.sh` only after backing up existing nginx configuration. It never binds admin ports publicly. Validate with `nginx -t` before reload.

Acceptance: HTTPS works; `/v1/models` requires a valid client token; direct public access to ports 1455/3000 is blocked.

### Phase 6 — Verification and handoff

Run local and public smoke tests, create a backup, and give the user:

- public Base URL;
- one per-user New API token (transmitted privately, never committed);
- exact verified model IDs;
- backup/rollback path;
- commands from `docs/operations.md`.

Acceptance: authorized client test succeeds, invalid token test fails, TLS and admin isolation pass.

## Common Patterns

### Add an official OpenAI-compatible provider

In New API add a separate channel. Use the provider's official base domain without a duplicate `/v1` when New API appends the API path. Verify the exact model ID and API key against official documentation before enabling.

### Diagnose `Invalid token`

Check, in order: client token status, token quota, user quota, model access, channel status, and whether the client accidentally used the internal MultiVibe key.

### Diagnose `No available channel`

Compare the requested model with MultiVibe `/v1/models` and New API channel models. Never invent a model name merely because it appears in rumors or another account.

### Upgrade safely

Do not follow `main` or `latest`. Open a PR updating `versions.env`, build in a disposable environment, run all acceptance tests, then deploy with a backup and rollback timestamp.

## Examples

### Example 1 — Fresh single-user deployment

- Input: authorized AlmaLinux VPS, unused port 8443, owned subscription.
- Steps: validate → preflight → pinned deploy → human OAuth → New API channel/token → nginx TLS → smoke test.
- Acceptance: valid token returns a model response; invalid token fails; ports 1455/3000 are not publicly reachable.

### Example 2 — Existing nginx and port 443 already used

- Input: production VPS where another service owns 443.
- Steps: inventory listeners → choose 8443 → back up nginx → install only the new server block → `nginx -t` → reload.
- Acceptance: existing 443 service remains unchanged and the gateway succeeds on 8443.

### Example 3 — Add an official API channel

- Input: provider-owned API key entered privately and exact official model ID.
- Steps: verify official endpoint → add separate New API channel → use a dedicated per-user token → call `/v1/models` and a minimal completion.
- Acceptance: request routes to the intended channel; removing that channel does not affect subscription routing.

### Example 4 — Provider denies the VPS

- Input: upstream 403/region/datacenter restriction.
- Steps: stop; preserve logs without secrets; ask the user to choose an approved region, official API, or provider-supported network path.
- Acceptance: no bypass is installed without an explicit, compliant decision.

## References

- `docs/index.md`: documentation map.
- `docs/deployment.md`: human-readable deployment detail.
- `docs/operations.md`: routine operations and token hygiene.
- `docs/rollback.md`: backup and rollback.
- `docs/legal.md`: terms, attribution, and public-use boundary.
- `THIRD_PARTY_NOTICES.md`: upstream licenses and pins.

## Maintenance

- Source of truth: this repository and `versions.env`.
- Dependency updates require a reviewed PR and all quality gates.
- Known limit: upstream subscription endpoints and provider terms can change without notice; successful historical deployment is not proof of current permission or compatibility.
- Last reviewed: 2026-09-05.
