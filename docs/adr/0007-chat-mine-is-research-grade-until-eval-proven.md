# ADR-0007: Chat-Mine is research-grade until eval-proven

## Status

Accepted

## Context

The current Chat-Mine slice proves deterministic package generation, source attachment, candidate hashes, negative package checks, rollback loading, and SQL corruption detection. That does not prove high-quality mining of real long-running AI conversations.

## Decision

Chat-Mine is research-grade until eval-proven. Current deterministic package rails are useful, but real mining quality is not solved.

## Consequences

- The repo should not claim real Chat-Mine mining quality is solved.
- Real conversational adapters need known-answer evals, topic segmentation, alias handling, currentness classification, and conflict detection.
- Chat-Mine output remains candidate material subject to custody, review, and promotion.

## Related

- [docs/10-chat-mine-source-import-exporter.md](../10-chat-mine-source-import-exporter.md)
- [docs/00-north-star.md](../00-north-star.md)
