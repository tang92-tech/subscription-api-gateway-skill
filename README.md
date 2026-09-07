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

---

<!-- jiuliang-about-start -->

## 关于半斤九两 / About EVEN BETTER

半斤九两科技（EVEN BETTER）专注"外贸 + AI"的真实落地。我们希望帮助外贸企业把产品、客户、渠道和团队流程，沉淀成客户看得懂、渠道跑得动、团队留得下的系统。

我们主要提供：

- 外贸 AI 落地方法：围绕 Build / Traffic / Team，判断企业该先建资产、放流量，还是建系统。
- 企业表达与内容增长：把产品、案例、FAQ、老板经验和信任证据，整理成海外客户看得懂的内容资产。
- 主动开发流程：从客户画像、线索搜索、客户背调到开发信和跟进复盘，跑出可复用闭环。
- 团队 AI 工作流：把经验写进 `AGENTS.md`、SOP、模板库、检查清单和可复用 Skill。

更多内容可以查看我们整理的 [《外贸人 Codex 蓝皮书》](https://github.com/FloydTang/waimaoren-codex-bluebook)。

### 找到我们

- 官网：[tang92.com](https://tang92.com)
- 公众号：半斤九两
- GitHub：[@FloydTang](https://github.com/FloydTang)

扫码关注公众号，领取后续模板、案例和更新；也可以通过公众号后台留言联系九两。

<p>
  <img src="https://raw.githubusercontent.com/FloydTang/waimaoren-codex-bluebook/main/assets/wechat-qr.png" alt="半斤九两公众号二维码" width="180">
</p>

<!-- jiuliang-about-end -->
