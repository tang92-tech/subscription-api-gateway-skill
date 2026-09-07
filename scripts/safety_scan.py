#!/usr/bin/env python3
"""Fail on likely credentials, private keys, live IPs, or credential files."""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
SKIP = {".git", "vendor", "data", "backups", "node_modules", "__pycache__"}
BLOCKED = {".env", "credentials.json", "accounts.json", "oauth-state.json"}
PATTERNS = {
    "OpenAI-style secret": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    "bearer token": re.compile(r"Bearer\s+[A-Za-z0-9._-]{24,}"),
    "private key": re.compile(r"-----BEGIN (?:OPENSSH|RSA|EC|DSA)? ?PRIVATE KEY-----"),
    "live IPv4 URL": re.compile(r"https?://(?!127\.0\.0\.1(?::|/))(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?"),
    "secret assignment": re.compile(r"(?:password|passwd|secret|api[_-]?key|admin[_-]?token)\s*[:=]\s*['\"]?(?!change-me|\$|<)[A-Za-z0-9_-]{16,}", re.I),
}
findings: list[str] = []
for path in ROOT.rglob("*"):
    if not path.is_file() or any(part in SKIP for part in path.parts):
        continue
    if path.name in BLOCKED or (path.name.startswith(".env") and path.name != ".env.example"):
        findings.append(f"{path}: blocked credential filename")
        continue
    try:
        text = path.read_text("utf-8")
    except UnicodeDecodeError:
        continue
    for name, pattern in PATTERNS.items():
        if pattern.search(text): findings.append(f"{path}: {name}")
if findings:
    print("Safety scan failed:", file=sys.stderr)
    print("\n".join(f"- {x}" for x in findings), file=sys.stderr)
    raise SystemExit(1)
print("Safety scan passed.")
