# Work Memory

## Purpose

Most assistant memory describes the principal, the world, or the work itself. **Work memory describes the agent's operating experience:** what it attempted, what worked, what failed, and what discipline should change as a result.

These are different mechanisms and should not share a table.

The portable implementation is in [`sql/07_work_lessons.sql`](../sql/07_work_lessons.sql). Rollback-only conformance checks are in [`tests/07_work_lessons.sql`](../tests/07_work_lessons.sql).

## A stored lesson is not yet an instruction

A lesson moves through an explicit authority lifecycle:

1. **Proposed** — recorded for review, never boot-active.
2. **Accepted** — reviewed through a sanctioned function and eligible for boot loading.
3. **Rejected** — preserved as a reviewed proposal but not loaded.
4. **Superseded** — replaced through append-preserving lineage, not rewritten in place.

Only active, accepted `rule` and `prohibition` rows with at least one current, resolvable evidence relation may appear in the boot fragment.

A shared runtime credential can enforce this workflow and preserve an audit trail, but it cannot cryptographically prove whether a human or an agent supplied the approval. Deployments that require identity-backed authority must use distinct principals or credentials.

## Lesson classes

| Kind | Loaded at boot | Purpose |
|---|---:|---|
| `prohibition` | yes, after acceptance | A bounded action or failure class the agent must avoid. |
| `rule` | yes, after acceptance | An operating discipline the agent should follow. |
| `worked` | no | Evidence that a technique or control succeeded. |
| `failed` | no | Evidence that an approach or assertion failed. |

Boot-loaded claims should be short, actionable, and narrowly scoped. Narrative, cost, and reasoning belong in `detail` and supporting evidence.

## Evidence custody

Evidence is a relation, not a comma-delimited string attached to a lesson.

Each evidence row records:

- a typed evidence kind;
- a canonical locator;
- the source authority or store;
- a resolution state;
- an optional integrity hash;
- who appended it;
- optional correction lineage.

New sanctioned writes use canonical locator forms:

| Evidence kind | Canonical shape |
|---|---|
| `model_channel` | `model_channel:12` or `model_channel:12-15` |
| `household_channel` | `household_channel:7` |
| `memory` | `memory:<uuid>` |
| `migration` | `migration:<snake_case_name>` |
| `artifact` | `artifact:sha256:<64 lowercase hex>` |
| `public_source` | `public_source:https://...` |
| `other_durable_locator` | `other:<scheme>:<value>` |

A value can be syntactically canonical and still fail to resolve. Resolvability is an acceptance and conformance property, not something a regular expression can prove.

### Corrections append; they do not overwrite

Evidence and authority events are append-only. A correction appends a successor evidence row linked through `supersedes`. The terminal rows are exposed through `work_lesson_evidence_current`.

This preserves both the original assertion and the later correction. Direct update, delete, and truncate are denied for routine runtime roles.

## Sanctioned write path

The portable contract exposes bounded SECURITY DEFINER functions:

- `propose_work_lesson(...)`
- `append_work_lesson_evidence(...)`
- `correct_work_lesson_evidence(...)`
- `accept_work_lesson(...)`
- `reject_work_lesson(...)`
- `propose_lesson_supersession(...)`
- `work_lessons_boot_fragment()`

The intended correction flow is:

1. Propose a successor with `propose_lesson_supersession(...)`.
2. Append or correct evidence until at least one current row is resolvable.
3. Accept the successor with `accept_work_lesson(...)`.
4. The acceptance transaction supersedes the predecessor and appends both authority events.

There is intentionally no convenience function that silently proposes and accepts in one call.

## Boot behavior

`work_lessons_boot_fragment()` returns:

- accepted, active prohibitions;
- accepted, active rules;
- deterministic ordering;
- historical worked/failed counts;
- proposed and evidence-blocked counts.

Worked and failed rows remain queryable evidence but are never injected as behavioral instructions.

Version 2 still supports only `applies_to = 'all-agents'`. Agent-scoped loading is deferred until a deployment has typed agent identity and explicit unknown-agent, fallback, and cross-agent semantics.

## What belongs here

- A verification technique that caught a consequential error.
- A failure mode that produced an incorrect result.
- A narrowly stated prohibition supported by observed evidence.
- A coordination or execution rule supported by evidence.
- A correction to prior agent behavior.

## What does not belong here

- Facts about the principal or world.
- Architecture decisions and rationale.
- Current task status.
- Preferences presented as universal rules.
- Unfalsifiable claims.
- Behavioral instructions without resolvable evidence.

## Minimum conformance checks

A deployment should prove that:

1. whitespace-only claims, actors, authorities, and locators are rejected;
2. routine roles cannot directly mutate or truncate lessons, evidence, or events;
3. a proposed rule or prohibition is absent from boot;
4. acceptance fails without current resolvable evidence;
5. an evidence correction appends a successor and a custody event;
6. acceptance makes the lesson boot-visible and appends an authority event;
7. rejection remains preserved but non-boot-active;
8. supersession preserves lineage and cannot create competing active successors;
9. worked and failed rows remain available but are not injected;
10. ordering is deterministic;
11. public, anonymous, and ordinary authenticated roles have no unintended access;
12. rollback-only tests leave no fixtures.

## Upgrade versus fresh install

The SQL file defines the fresh-install contract. Existing deployments must not blindly replay it over live tables. See [`docs/upgrades/work-memory-v2.md`](upgrades/work-memory-v2.md) for the required inventory, custody, evidence-normalization, and boot-gating sequence.