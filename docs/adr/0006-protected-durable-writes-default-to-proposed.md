# ADR-0006: Protected durable writes default to proposed

## Status

Accepted

## Context

Agents can help draft memory updates, but protected durable scopes need a conservative write posture. Ambiguous user language should not let an agent mutate the source of record without an exact, current-turn instruction.

## Decision

For protected durable scopes, agent-initiated writes default to proposed unless the human explicitly requested that exact write in the current turn.

This reflects the durable-write policy ruling recorded in issue #34.

## Consequences

- Agents may propose truth; approved workflows promote it.
- Drafting, importing, and staging remain allowed.
- In-place durable writes require explicit user instruction or a future approved workflow.
- More complex role, trigger, or approval systems can wait until the simple policy is insufficient.

## Related

- Issue #34
- Planned durable-write policy documentation
