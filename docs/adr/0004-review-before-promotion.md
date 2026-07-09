# ADR-0004: Review before promotion

## Status

Accepted

## Context

Durable memory and source-of-record changes can affect future assistant behavior. Automatically promoting imported or inferred claims would make mistakes persistent and hard to diagnose.

## Decision

Review-before-promotion is mandatory for durable memory and source-of-record changes.

## Consequences

- Candidates may be staged, held, rejected, or reviewed before promotion.
- Cutover is an explicit operator action, not a side effect of package generation or loading.
- Review workflow is part of the alpha path, not a cosmetic UI layer.

## Related

- [docs/08-readiness-scorecard.md](../08-readiness-scorecard.md)
- [ADR-0003](0003-models-and-miners-are-untrusted-emitters.md)
