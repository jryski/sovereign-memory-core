# Security

This repository is an early reference implementation. Review the security model before using it with sensitive production data.

Relevant doc:

- [docs/02-security-model.md](docs/02-security-model.md)

## Sensitive reports

Do not put secrets, credentials, private memory exports, private chat logs, API keys, or deployment details in public issues or pull requests.

## Report a vulnerability privately

Sovereign Memory Core is an early PostgreSQL reference implementation. In scope: anything that lets a principal read, write or promote memory outside its authority, defeats RLS, the SECURITY DEFINER hardening or `perimeter_report()`, corrupts provenance or history, or commits secrets or private exports. Review [docs/02-security-model.md](docs/02-security-model.md) before using it with sensitive data.

Use this repository's private vulnerability reporting form:
<https://github.com/jryski/sovereign-memory-core/security/advisories/new>

If the form is unavailable, email **jryski@gmail.com** instead.

Include, where you can, the affected commit or file, preconditions and trust boundary, a minimal reproduction with synthetic data, impact, whether secrets or personal data were exposed, and a proposed mitigation. Each program component has its own form; the [program map](https://github.com/WireSpeedComputing/sovereign-ai-os) lists them.

## Live systems

Do not run repository scripts against live Supabase or any production database unless the operator explicitly approved the exact target and operation.

Local/disposable validation is the default posture.

## Secrets

Never commit:

- service keys
- access tokens
- API keys
- private database URLs
- private Supabase project refs
- real exports containing private memory or conversation data

Use `REDACTED` or generic examples in documentation and fixtures.
