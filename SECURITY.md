# Security policy

## Secrets

Never commit or disclose:

- OAuth access/refresh tokens, cookies, or account databases;
- New API passwords or client tokens;
- MultiVibe admin/internal proxy keys;
- SSH keys, certificates' private keys, 2FA seeds, or recovery codes;
- real IPs, domains, emails, request bodies, or client logs.

This public repository intentionally contains no credentials. CI runs a secret-pattern scanner, but scanners are not proof of absence.

If a secret is exposed, revoke or rotate it first. Deleting a public commit is not sufficient because clones, forks, caches, and CI logs may persist.

## Report a vulnerability

Do not post secret material in a public issue. Open a security advisory in GitHub or contact the maintainer privately with only the affected path, commit, and sanitized reproduction.
