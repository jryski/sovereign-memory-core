# ADR-0001: SMP is a custody layer, not a memory format

## Status

Accepted

## Context

AI memory can appear as SQL rows, JSON exports, chat transcripts, notes, application records, vendor data, or future memory protocol objects. Competing to define one universal memory-record format would make the project brittle and distract from the transfer problem.

## Decision

SMP is a custody, verification, provenance, review, and cutover layer. It is not trying to become the winning memory-record format.

## Consequences

- Source formats remain adapter surfaces.
- The core must prove accounting, evidence attachment, review posture, and authority transfer.
- Adapter profiles can describe lossiness and mapping without forcing all sources into one native shape.

## Related

- [docs/00-north-star.md](../00-north-star.md)
- [docs/roadmap.md](../roadmap.md)
