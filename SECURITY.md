# Security

This repository is an early reference implementation. Review the security model before using it with sensitive production data.

Relevant doc:

- [docs/02-security-model.md](docs/02-security-model.md)

## Sensitive reports

Do not put secrets, credentials, private memory exports, private chat logs, API keys, or deployment details in public issues or pull requests.

Report a vulnerability through this repository's own private vulnerability reporting form:
<https://github.com/jryski/sovereign-memory-core/security/advisories/new>

If the form is unavailable, email <jryski@gmail.com> instead. Include the affected commit, the
trust boundary involved and a minimal reproduction with synthetic data.

Each program component has its own private form. Report issues in another component there; the
[program map](https://github.com/WireSpeedComputing/sovereign-ai-os) lists every component.

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
