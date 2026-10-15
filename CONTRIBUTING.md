# Contributing

Sovereign Memory Core is a custody and verification layer for AI memory transfer. Contributions should preserve the project's core posture: evidence before belief, review before promotion, and no silent authority changes.

## Orientation

Start with:

- [README.md](README.md)
- [STATUS.md](STATUS.md)
- [docs/00-north-star.md](docs/00-north-star.md)
- [docs/roadmap.md](docs/roadmap.md)
- [docs/project-management.md](docs/project-management.md)

Architecture decisions live in [docs/adr/](docs/adr/).

## Choosing an issue

Pick an issue with clear scope, acceptance criteria, and validation expectations. If an issue touches SQL behavior, fixtures, public-safety posture, or conformance claims, keep the PR narrow and document the validation evidence.

Good first contributions usually fit one of these shapes:

- docs clarity
- fixture or validation hardening
- small operator-flow improvements
- conformance gap documentation

## Branches

Use a short topic branch. The Codex default prefix is `codex/`; human contributors may use any clear branch name.

Examples:

- `codex/project-management-scaffolding`
- `docs/adapter-profile-template`
- `test/source-import-negative-case`

## PR expectations

Open draft PRs for coordination. Mark a PR ready only after the stated validation has passed.

Use [.github/pull_request_template.md](.github/pull_request_template.md) as the source of truth for PR body structure. In short, every PR should explain what changed, what issue it addresses, which files changed, what validation ran, what public-safety checks passed, whether any live state was touched, and what remains.

## Validation expectations

Run the checks appropriate to the files changed:

- Always: `git diff --check`
- Always: `bash scripts/public_safety_scan.sh` (changed-file public-safety scan; see [docs/public-safety.md](docs/public-safety.md))
- Docs: markdown/link checks if available
- SQL: source-import validation and relevant local/disposable database checks
- Python: syntax checks and relevant test scripts
- Shell: shell syntax checks
- Fixtures: deterministic regeneration and validation

Do not weaken existing validation to make a PR pass.

## Public-safety expectations

Do not introduce:

- private names or personal identifiers
- real emails, phone numbers, addresses, or location details
- local filesystem paths
- API keys, tokens, secrets, or private deployment refs
- private Supabase project refs, URLs, or credentials
- private chat snippets or private fixture content
- private employer, client, account, or project names

Use generic placeholders such as `example-user`, `example-owner`, `example-memory-core`, `example-source-system`, `example-chat-export`, `Example Assistant`, `Example Project`, `example.local`, `you@example.com`, or `REDACTED`.

### Publication surfaces

Tracker text is publication. So are reviews, release notes, workflow logs, and uploaded artifacts. The changed-file scan does not read those surfaces. Before publishing any of them, complete the checklist in the issue templates and in [.github/pull_request_template.md](.github/pull_request_template.md).

That includes:

- issue titles, bodies, and comments
- pull-request titles, bodies, review comments, and inline suggestions
- release notes and tag messages
- workflow logs
- uploaded artifacts

Do not upload private exports, live schema or RPC inventories, or credential-bearing logs. Do not print matched secrets into workflow logs. Run `bash scripts/public_safety_scan.sh --all` before a release and apply the same checklist to the release notes and any uploaded artifact. Details, placeholders the scanner allows, and the local commands are in [docs/public-safety.md](docs/public-safety.md).

A green scan is not clearance. Pattern matching cannot establish context or attack value.

## Supabase and live state

Do not mutate live Supabase or any live database without explicit human approval for that exact target and operation.

Local/disposable database validation is allowed when the issue or PR requires it. Loader and validation paths should refuse non-local targets unless the user explicitly approves otherwise.

## Claims and conformance

Do not claim full SMP conformance unless tests and conformance documentation prove it.

Do not claim Chat-Mine quality is solved. Chat-Mine is currently a research-grade emitter with deterministic custody rails, not proven real-conversation mining quality.

## Merges

Locked **D3** ([WireSpeedComputing/sovereign-ai-os#11](https://github.com/WireSpeedComputing/sovereign-ai-os/issues/11)) allows **docs-only** bot merges after CI is green and an independent reviewer has approved. The pull request author and the independent reviewer must be different (`author ≠ reviewer`). Primary Users do not have to click merge on every docs-only pull request.

A pull request is not docs-only when it changes an agent-executable or policy surface. Those changes still need Primary Users or an explicit delegation. Exclusions:

- `AGENTS.md`, `CONTEXT.md`, `CLAUDE.md`, and equivalent agent-instruction files
- `.cursor/`
- `.github/` changes that alter workflow, action, template, or other bot behavior
- `SECURITY.md`
- auth, row-level security (RLS), or protocol semantics
- any other file that grants or describes executable agent instructions

Non-docs merges still need Primary Users or an explicit delegation. Release, deploy, and access expansion use that same bar. Opening an issue, branch, or pull request does not grant merge, release, deploy, or access authority.

The docs-only exclusion list and the cross-repo steward map live on [WireSpeedComputing/sovereign-ai-os#55](https://github.com/WireSpeedComputing/sovereign-ai-os/issues/55). The steward map is **PROPOSED** until Primary Users lock it. The proposed assigning steward for this repository is **memory-lane** (locutus / grok-memory). Steward assignment is not merge authority.

Docs-only merge does not relax the public-safety expectations in this document. Recording D3 here is a contributing-policy amendment only. Cutover status, launch gates A/B, and architecture stay outside this section.

## Sign-off

Commits must be signed off under the Developer Certificate of Origin. Use
`git commit -s`. See [DCO.md](DCO.md).
