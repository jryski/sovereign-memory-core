# ADR-0005: Adapter profiles over format competition

## Status

Accepted

## Context

Memory and export formats will keep changing. A useful custody layer needs to compare, map, and verify source material without forcing every producer to adopt one project-specific record format.

## Decision

SMP should support adapter profiles over competing with every memory protocol or export format.

## Consequences

- Adapter profiles should declare mapping, lossiness, source identity, evidence posture, and unsupported fields.
- The core can accept packages from many sources while enforcing common custody requirements.
- Future external formats can be treated as inputs or outputs rather than rivals.

## Related

- [docs/09-source-adapters.md](../09-source-adapters.md)
- [ADR-0001](0001-smp-is-a-custody-layer-not-a-memory-format.md)
