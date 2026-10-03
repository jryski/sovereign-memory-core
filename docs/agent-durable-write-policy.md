# Agent durable-write policy

A baby gate for agents that touch this project. It is not a governance
framework, and it does not add database permissions.

Agents may inspect, summarize, draft, and propose. Approved workflows promote.

> Agents may propose truth; approved workflows promote it.

Refs #32.

## Inspect and propose

These actions stay on the proposal side of the gate:

- inspect and summarize an existing record;
- draft text, a patch, or a review issue;
- propose a change and leave the durable target unchanged.

A durable source of record changes only when the specific target and the
specific operation are explicitly approved. Approval of one target leaves every
other target untouched. Approval to draft leaves the write unapproved.

## Ruling already on main

[ADR-0006](adr/0006-protected-durable-writes-default-to-proposed.md) is the
accepted ruling on main. For protected durable scopes, agent-initiated writes
default to proposed unless the human explicitly requested that exact write in
the current turn. Ambiguous language is not that request. Drafting, importing,
and staging remain allowed. An in-place durable write needs an explicit
instruction for that write, or a future approved workflow.

No document on main is titled `protected-paths-default-to-proposed`, and main
has no path list under that name. The conformance gap audit's phrase
"protected-path proposal posture" records a gap. It is not a catalog. This
policy does not invent one. The targets below are the approval-required targets
from issue #32, applied with ADR-0006's default-to-proposed rule.

## Ambiguous language

These phrases permit a draft, a proposed patch, or a review issue only:

- "capture this somewhere"
- "document this"
- "maybe Supabase"
- "also all of that"
- "align this"
- "put this in the north star"

None of them approves a durable write.

## Durable sources of record

Treat these as approval-required targets:

- wiki pages
- durable memory records
- repo files
- schema and migrations
- north-star/spec/project docs
- project status pages
- license/commercial terms
- roadmap state
- issue/PR state when used as project truth

## Risk classes

| Class | Name | Gate |
|---|---|---|
| 0 | Draft/think | No external mutation. |
| 1 | Read/inspect | External read. No mutation. |
| 2 | Communication write | A message or comment, and only when that write was explicitly requested. |
| 3 | Durable source-of-record write | Approval of the specific target and operation. |
| 4 | Dangerous/irreversible write | Approval of the specific target and operation, plus stronger confirmation of the irreversible effect. |

A class 2 communication write leaves durable sources of record unchanged.
Communication writes are not durable source-of-record writes. A request to post
a comment leaves wiki pages, memory rows, schema, roadmap state, and issue/PR
state unchanged.

## Future `proposed_changes` flow

This is a future flow. This policy does not create tables, grants, roles,
row-level security, or any other database permission.

1. The agent drafts the change, or inserts it as a proposal.
2. The proposal records the target, the operation, the current hash, the proposed content, the reason, the proposer, and a timestamp.
3. Primary Users, or a reviewer approved for that operation, mark it approved or rejected.
4. An apply step writes the durable target and records an audit trail.

Until that flow exists, the gate is unchanged: the agent proposes, and an
approved workflow promotes.

## Examples

Synthetic labels only. Primary Users are the approvers in these examples.

Allowed:

- Primary Users ask for a summary of wiki page `example-workstream/status`. The agent reads it and answers. Class 1. The page stays as it was.
- Primary Users ask for a draft north-star sentence. The agent returns a proposed patch to `docs/00-north-star.md`, or opens a review issue. The wiki page and the file stay unchanged.
- Primary Users ask for this comment on a review issue: "Draft ready for `example-workstream/example-topic`." That comment is a class 2 communication write. The issue stays open.
- The agent stages a candidate for `example-project` at `example-workstream/example-topic` and leaves the candidate proposed.

Disallowed:

- "Capture this somewhere," followed by an insert into a durable memory or a wiki page.
- "Document this," followed by an edit to a repo file, a project status page, or license/commercial terms.
- "Maybe Supabase," followed by a write to a live table.
- "Also all of that," followed by updates to schema and migrations.
- "Align this," followed by a rewrite of roadmap state or a project status page.
- "Put this in the north star," followed by an in-place edit of the north-star wiki page or `docs/00-north-star.md`.
- Applying a proposal, superseding a durable memory, or changing issue/PR state that the project uses as truth, without approval of that target and operation.
- Dropping a table, rewriting license/commercial terms, or another irreversible write, without approval of that target and operation plus stronger confirmation. Class 4.

## Out of scope

- Live database mutation, including live Supabase.
- Changes to SQL, Python, shell, tests, fixtures, or workflow behavior.
- New roles, grants, or row-level security.
- Approval steps beyond this gate.
