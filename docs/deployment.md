# Deployment guide

## 1. Prepare

Recommended minimum: Linux x86_64/arm64 VPS, 1 vCPU, 1 GiB RAM plus swap, Docker Compose v2, nginx, a domain/certificate, and an account you own. Confirm service-provider terms before continuing.

Clone this repository on the VPS and run:

```bash
./scripts/validate-repo.sh
sudo ./scripts/preflight.sh
sudo ./scripts/deploy.sh
```

The deploy script installs no OS packages. If preflight reports missing Docker, Git, OpenSSL, curl, nft, or nginx, install them using the OS-supported package manager after user approval.

## 2. What deploy.sh changes

- Creates `/opt/subscription-api-gateway`.
- Creates system account `subgateway` with uid/gid 10001 if available.
- Fetches exactly the commit in `versions.env` into `vendor/multivibe`.
- Generates three random secrets in `.env` with mode 600.
- Copies the pinned compose file and starts MultiVibe/New API.
- Installs a narrow nftables table that blocks non-loopback input to 1455/3000.

It does not change nginx, certificates, provider accounts, or OAuth.

## 3. Human OAuth

From the operator computer:

```bash
ssh -N -L 1455:127.0.0.1:1455 -L 3000:127.0.0.1:3000 \
  -p <SSH_PORT> <SSH_USER>@<VPS_HOST>
```

Visit `http://localhost:1455`. Retrieve the generated admin token directly on the VPS without pasting it into chat:

```bash
sudo awk -F= '/^MULTIVIBE_ADMIN_TOKEN=/{print $2}' /opt/subscription-api-gateway/.env
```

Complete device/OAuth authorization personally. Never give passwords, 2FA, cookies, refresh tokens, or recovery codes to an agent.

## 4. Initialize New API

Visit `http://localhost:3000`, initialize the root account, then create an OpenAI-compatible channel:

- Base URL: `http://127.0.0.1:1455`
- API key: value of `MULTIVIBE_PROXY_KEY` in the VPS `.env`
- Models: exact IDs returned by MultiVibe `/v1/models`
- Concurrency: conservative; start at 1–2

Do not append `/v1` to a New API channel base URL when the channel adapter already appends `/v1/...`.

Create one New API token per authorized user. Never share `MULTIVIBE_PROXY_KEY` externally.

## 5. TLS

Prepare a certificate first, then:

```bash
sudo DOMAIN=api.example.com \
  CERT_FILE=/etc/letsencrypt/live/api.example.com/fullchain.pem \
  KEY_FILE=/etc/letsencrypt/live/api.example.com/privkey.pem \
  LISTEN_PORT=8443 \
  ./scripts/install-nginx.sh
```

The script backs up an existing same-name config, renders the template, runs `nginx -t`, and only then reloads nginx.

## 6. Verify

```bash
sudo ./scripts/smoke-test.sh --local
read -rsp "Client API token: " TOKEN; echo
TOKEN="$TOKEN" MODEL="<discovered-model>" \
  ./scripts/smoke-test.sh --public https://api.example.com:8443
unset TOKEN
```
