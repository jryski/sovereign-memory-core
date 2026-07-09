# ADR-0002: Evidence hashes prove custody, not truth

## Status

Accepted

## Context

Hashes and checksums are useful for proving that bytes, quotes, or packages have not changed. They cannot prove that a claim is true, current, complete, or endorsed by the user.

## Decision

Evidence hashes prove custody and source attachment, not truth or correctness.

## Consequences

- Validation can reject drift, missing evidence, and mismatched source attachment.
- Validation must not treat a matching hash as a truth verdict.
- Review and promotion remain required for durable memory.

## Related

- [docs/07-source-import-cutover.md](../07-source-import-cutover.md)
- [docs/08-readiness-scorecard.md](../08-readiness-scorecard.md)
