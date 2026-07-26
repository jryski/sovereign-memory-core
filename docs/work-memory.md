# Work Memory

## Purpose

Most assistant memory describes the principal, the world, or the work itself. Its purpose is continuity and personalization.

**Work memory describes the agent's operating experience:** what it attempted, what worked, what failed, and what discipline should change as a result. Its purpose is performance improvement.

These are different mechanisms and should not share a table.

A work-memory implementation is provided in [`sql/07_work_lessons.sql`](../sql/07_work_lessons.sql).

## The behavioral rule

> A lesson that is only stored is a diary.

An active behavioral lesson must be included in the agent's boot or instruction payload. Otherwise the system records experience without changing behavior.

The portable SQL exposes `work_lessons_boot_fragment()`, which returns the active behavioral subset with deterministic ordering. A deployment integrates that fragment into its own session-boot contract.

## Lesson classes

| Kind | Loaded at boot | Purpose |
|---|---:|---|
| `prohibition` | yes | A bounded action or failure class the agent must avoid. |
| `rule` | yes | An operating discipline the agent should follow. |
| `worked` | no | Evidence that a rule was earned. |
| `failed` | no | Evidence that a prohibition or correction was earned. |

Boot-loaded claims should be short, actionable, and narrowly scoped. Narrative, cost, and reasoning belong in `detail` and in the supporting `worked` or `failed` rows.

## Evidence invariant

Every lesson requires a non-empty `evidence_ref` that identifies durable supporting evidence, such as:

- a coordination record;
- a migration or release artifact;
- an immutable record identifier;
- a test or incident artifact;
- a public source.

The database enforces presence, not truth or resolvability. Deployments remain responsible for ensuring that the locator can be resolved by an authorized reviewer.

A lesson without traceable evidence is an assertion, not a lesson.

## Moving record

Lessons are corrected by supersession, not in-place rewriting.

Use:

```sql
select supersede_lesson(
  p_id,
  p_claim,
  p_detail,
  p_evidence_ref
);
```

The function creates a successor, preserves the lesson kind and v1 scope, and marks the prior active row superseded in the same transaction.

The earlier lesson remains evidence of what the system previously believed and why it changed.

## Version 1 scope

Version 1 supports only `applies_to = 'all-agents'`.

Agent-specific loading is deliberately deferred until the deployment has a typed agent identity and explicit boot semantics for unknown agents, fallback behavior, and cross-agent visibility. The column is retained as a reserved compatibility seam but constrained so it cannot imply unsupported enforcement.

## What belongs here

- A verification technique that caught a consequential error.
- A failure mode that produced an incorrect result.
- A narrowly stated prohibition supported by an observed failure.
- A coordination or execution rule supported by evidence.
- A correction to prior agent behavior.

## What does not belong here

- Facts about the principal or world. Those belong in memory.
- Architecture decisions and rationale. Those belong in documents or decision records.
- Current task status. That belongs in project state or an issue tracker.
- Preferences presented as universal rules.
- Unfalsifiable claims.
- Lessons without durable evidence.

## Failure modes

### Growth without compression

Boot-loaded rules consume context. If the active set grows beyond attentive use, overlapping rules should be merged through supersession and obsolete rules should be superseded. Do not silently drop low-ranked rules without an explicit policy.

### Overbroad claims

A useful rule in one investigation may be harmful as a universal prohibition. State the domain, trigger, and consequence narrowly enough that the rule changes the intended behavior without blocking authorized work.

### Self-congratulation

`worked` rows are easy to create and often low-information. Favor failures, corrections, and evidence that changed the operating model.

### Written but not loaded

A deployment that creates `work_lessons` but never calls `work_lessons_boot_fragment()` has implemented a log, not behavioral memory.

### Unverified mechanism claims

Verify that functions, constraints, grants, and boot integration exist in the live catalog and behave correctly. Documentation is not proof of deployment.

## Minimum conformance checks

A deployment should prove that:

1. blank evidence references are rejected;
2. unsupported `applies_to` values are rejected;
3. the supersession function creates valid lineage and deactivates the predecessor;
4. only one active direct successor can exist for a lesson;
5. boot output loads active rules and prohibitions in deterministic order;
6. worked and failed rows remain available as evidence but are not injected as behavioral instructions;
7. public or anonymous roles do not receive unintended access;
8. the deployment's actual session boot includes the returned fragment.
