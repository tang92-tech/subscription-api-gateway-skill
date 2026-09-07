# Codex entrypoint

1. Read `SKILL.md` completely before changing a server.
2. Treat `versions.env` as the dependency lock.
3. Ask for confirmation before SSH, firewall, nginx, package installation, container launch, or destructive changes.
4. Never ask the user to paste access tokens, OAuth credentials, private keys, or passwords into chat. Use silent terminal prompts or an on-server `.env` with mode `600`.
5. Pause for the human to complete OAuth in their own browser.
6. Run `scripts/validate-repo.sh` before proposing a deployment and `scripts/smoke-test.sh` after it.
7. Stop if ownership/authorization, service-provider terms, or rollback safety are unclear.
