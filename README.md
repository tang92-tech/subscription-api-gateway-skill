# Subscription API Gateway Skill

A public, credential-free Codex Skill for deploying an **authorized self-hosted OpenAI-compatible gateway** around an account you own, then managing client tokens through New API.

## Give it to Codex

```text
Clone https://github.com/tang92-tech/subscription-api-gateway-skill.
Read AGENTS.md and SKILL.md completely.
Plan an authorized deployment on my VPS, inventory existing services first, ask before every server change, and pause for me to complete OAuth in my own browser. Never request or print secrets.
```

Codex can automate server inventory, pinned builds, Docker, local port isolation, nginx, smoke tests, backup, and rollback. **The account owner must complete OAuth/2FA personally.**

## What it deploys

```text
Authorized client
  -> HTTPS nginx
  -> New API (client tokens, quotas, logs, provider routing)
  -> MultiVibe (owned subscription OAuth -> OpenAI-compatible interface)
  -> provider
```

Official API providers can be added as separate New API channels.

## Safety defaults

- No credentials, live IPs, domains, emails, or OAuth data are stored here.
- Admin ports 1455/3000 stay local-only and are blocked from non-loopback access.
- Dependencies are pinned in `versions.env`; no `main` or `latest` deployment.
- No automated anti-abuse bypass or public quota resale workflow.
- One revocable client token per authorized person.

## Start

```bash
./scripts/validate-repo.sh
sudo ./scripts/preflight.sh
sudo ./scripts/deploy.sh
```

Then follow the human OAuth and New API steps in `SKILL.md`.

## Documentation

Start with [`docs/index.md`](docs/index.md). Read [`docs/legal.md`](docs/legal.md) before deployment and [`SECURITY.md`](SECURITY.md) before reporting a vulnerability.

## Upstreams

- [MultiVibe](https://github.com/thibautrey/multivibe) — Apache-2.0
- [New API](https://github.com/QuantumNous/new-api) — AGPL-3.0

This repository is independent and is not affiliated with OpenAI, MultiVibe, or New API.
