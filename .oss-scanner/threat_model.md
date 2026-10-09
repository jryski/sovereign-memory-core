# OSS Scanner threat model: Sovereign Memory Core

The repository is a public PostgreSQL reference implementation for memory custody and provenance. It is not a live deployment and must not be treated as the source of any real household or personal records. See [SECURITY.md](../SECURITY.md), [docs/02-security-model.md](../docs/02-security-model.md), and [docs/perimeter.md](../docs/perimeter.md).

## Assets and attacker-controlled surfaces

- Confidentiality and authority-bound access to stored records, evidence and lineage.
- Integrity of accepted records, append-only event history, supersession, revisions, erasure receipts, exports, restore and verification.
- PostgreSQL access control: roles, grants, role inheritance, RLS, views, default privileges, SECURITY DEFINER functions and search_path protection.
- Untrusted source/import packages, malformed serialized data, caller-provided identifiers, and lower-privileged role activity.
- Python/shell packaging scripts and local validation tools when fed untrusted files.

The high-value review surfaces are `sql/`, `tests/`, `scripts/`, and the security-definer and perimeter documentation. Consider both the portable PostgreSQL profile and the Supabase-compatible profile, but respect their documented differences.

## Execution and boundary assumptions

- Use disposable local PostgreSQL clusters and synthetic fixtures only. `DATABASE_URL` must never target any live Supabase, HOUSE, VAULT, or other production service.
- The provided Dockerfile includes PostgreSQL 16 binaries and Python 3. No database is created automatically; initialize a temporary cluster as the `postgres` OS user and run relevant scripts with a local connection only.
- `scripts/validate_source_import.sh` and the conformance SQL in `tests/` are starting points. Some upgrade tests need Git history and a previous reviewed commit; report missing test prerequisites rather than claiming that a design vulnerability is proved.
- A legitimate database owner, host administrator, or holder of the full service-role credential is already privileged; evaluate only security boundaries the repository actually promises.

## Severity guidance

- **Critical:** demonstrated low-privilege to database-owner/service-role escalation, unauthorized bulk access across user or trust boundaries, or reliable tampering/erasure of protected custody records by an unprivileged actor.
- **High:** reproducible RLS/ACL or SECURITY DEFINER privilege bypass, append-only/audit forgery, approval-state bypass, or loss of verification integrity permitting another actor to forge trusted evidence.
- **Medium:** constrained corruption that is detected or recoverable, local-only denial of service by a non-privileged actor, or bounded leakage of non-sensitive metadata.
- **Low / informational:** documentation or operator-misconfiguration concerns without an exploitable claimed enforcement boundary.

Demonstrate the exact principal and grants involved. Distinguish vulnerabilities in this reference runtime from unsafe deployment choices. Use synthetic data and disclose exploit details only privately.
