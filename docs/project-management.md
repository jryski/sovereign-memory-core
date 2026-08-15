# Project management

This repository uses GitHub-native project management. The goal is durable,
reviewable coordination with as little ceremony as possible.

## Source of truth by concern

| Surface | Role |
|---|---|
| `README.md` | Human entry point: what the project is, what it proves, what it does not prove |
| `STATUS.md` | Current released/runtime state and active post-release themes |
| `docs/roadmap.md` | Direction of travel, not a release promise |
| Issues | Bounded units of work, defects, research questions, and acceptance criteria |
| Pull requests | Reviewable changes plus exact validation evidence |
| ADRs | Architectural decisions that should outlive a chat transcript |
| Releases | Immutable-ish public snapshots with explicit claim boundaries and artifacts |
| GitHub Project / board | Optional planning view over issues; never the only copy of a requirement |

## Work-item practice

Issues should state enough that another contributor can tell when the work is
finished without reconstructing a private conversation.

Include:

- goal;
- scope and non-goals;
- acceptance criteria;
- validation expectations;
- public-safety and live-state guardrails;
- dependencies or blockers;
- related docs, scripts, fixtures, ADRs, or prior receipts.

If a defect is security-, custody-, or release-relevant, include the smallest
reproduction that demonstrates the failure. Do not downgrade a reproduced
load-bearing defect into an "improvement" to keep work moving.

## Suggested board states

A simple board is enough:

`Backlog -> Ready -> In Progress -> Review -> Done`

Use `Blocked` and `Waiting for owner` as explicit states rather than allowing
stalled work to look active.

For multi-agent or multi-contributor work, the card/issue is the shared work
object. Chat or model messages should point back to it rather than becoming the
only place where status, authority, or acceptance criteria exist.

## Useful classification fields

These are suggestions, not a requirement to reproduce a particular GitHub
Project configuration.

| Field | Example values |
|---|---|
| Status | Backlog / Ready / In Progress / Review / Done / Blocked / Waiting for owner |
| Area | Core / Security / Portability / Adapter / Docs / Release / Governance |
| Priority | P0 / P1 / P2 |
| Risk | Low / Medium / High / Research |
| Target | Current release / Next release / Post-release / Unscheduled |

Avoid encoding stale version roadmaps into the board. A version target is useful
only when an issue is actually committed to that release.

## PR practice

Use [`.github/pull_request_template.md`](../.github/pull_request_template.md) as
the source of truth for PR body structure.

Draft PRs are appropriate for coordination. "Ready for review" means the author
believes the stated acceptance criteria and validation are satisfied; it does
not mean the change is approved.

For load-bearing changes, preserve exact candidate coordinates and test receipts.
A review of one commit does not automatically carry forward to a successor
commit.

## Validation posture

Validation should be appropriate to the change and should fail closed where the
claim would otherwise become ambiguous.

Examples:

- docs-only: link/format checks where available, plus claim review against the
  current release evidence;
- SQL/runtime: disposable PostgreSQL execution and adversarial regression tests;
- package/restore: independent destination, source-unchanged proof, structural
  and security assertions;
- release: exact-coordinate checks, artifact hashes, known limitations, and
  independent review.

Do not weaken existing tests to obtain a passing result.

## Public/private boundary

This is a public repository.

Do not move private deployment state into an issue or PR merely because GitHub
is convenient. Real credentials, personal records, provider project refs,
private topology, recovery artifacts, and deployment-only receipts belong in an
appropriate private operating surface.

When a private deployment exposes a generic Core defect, reproduce the defect
with sanitized synthetic evidence before promoting the fix here.

## ADR practice

Use [`docs/adr/0000-template.md`](adr/0000-template.md) for decisions that affect
architecture, trust posture, conformance, repository boundaries, or durable
contribution rules.

ADRs should record:

- decision;
- context;
- alternatives considered;
- consequences;
- supersession relationship when a later ADR changes the decision.

They should not become implementation manuals.

## Release practice

A release is not "main looks good."

A release should bind:

- exact commit/tree;
- required workflows;
- reproducible evidence;
- known limitations;
- artifact/checksum roots;
- independent review;
- owner authorization where the release procedure requires it.

If integration changes the reviewed commit, treat the result as a new candidate
unless the release procedure explicitly proves coordinate preservation.

## Labels

Labels are useful for filtering, but documentation must not depend on a label
existing. Prefer a small vocabulary such as:

- `type:docs`, `type:code`, `type:test`, `type:research`, `type:infra`, `type:security`;
- `priority:p0`, `priority:p1`, `priority:p2`;
- `status:blocked`, `status:needs-review`;
- area/track labels only where they remain useful over time.

The issue body should remain understandable if every label disappears.
