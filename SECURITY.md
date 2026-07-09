# Security

This repository is an early reference implementation. Review the security model before using it with sensitive production data.

Relevant doc:

- [docs/02-security-model.md](docs/02-security-model.md)

## Sensitive reports

Do not put secrets, credentials, private memory exports, private chat logs, API keys, or deployment details in public issues or pull requests.

If you need to report a sensitive issue, use a private channel with the repository owner or maintainer instead of posting the sensitive material publicly.

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
