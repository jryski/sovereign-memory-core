# ADR-0003: Models and miners are untrusted emitters

## Status

Accepted

## Context

Models, extractors, and source miners can produce useful candidate memories, but they can also hallucinate, flatten conflicts, miss context, confuse aliases, or turn suggestions into asserted facts.

## Decision

Models and miners are untrusted emitters. Their outputs are candidates, not authoritative memory.

## Consequences

- Imported model output should preserve source locators, quotes, hashes, disposition, and confidence context.
- Emitters should not silently resolve conflicts or mark durable truth.
- Custody validation and human review are the boundary between emitted candidates and durable memory.

## Related

- [ADR-0004](0004-review-before-promotion.md)
- [ADR-0007](0007-chat-mine-is-research-grade-until-eval-proven.md)
