# Operations

## Status

```bash
cd /opt/subscription-api-gateway
docker compose ps
docker compose logs --tail=100 multivibe
docker compose logs --tail=100 new-api
```

Sanitize logs before sharing. OAuth tokens, client tokens, request bodies, emails, and account IDs are sensitive.

## Token policy

- Use one New API client token per authorized person or application.
- Name it for traceability; set quota, expiry, allowed models, and IP rules when appropriate.
- Never issue the internal MultiVibe proxy key to a client.
- Revoke an individual token without rotating everyone else's token.
- A token can be unlimited while the owning New API user still has no quota. Check both token and user quota when diagnosing `insufficient_user_quota`.

## Model policy

Treat `/v1/models` as the truth. Provider rollouts differ by account. A rumored or UI-only model is not usable until it is discovered and a minimal authenticated request succeeds.

## Official API channels

Add official providers as separate New API channels. Verify the endpoint and exact model ID from official docs. New API may append `/v1/...`; avoid a duplicate `/v1/v1/...` path.

## Backup

```bash
sudo ./scripts/backup.sh
```

Backups contain credentials and databases. They are mode 600, local by default, and must be moved to an encrypted backup system.

## Upgrade

1. Update `versions.env` in a branch.
2. Validate upstream licenses and breaking changes.
3. Build in a disposable host.
4. Run validation and smoke tests.
5. Back up production.
6. Deploy; roll back on any failed gate.
