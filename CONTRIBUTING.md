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

Each PR should include:

```md
## Summary
## Issues addressed
## Files changed
## Validation run
## Public-safety checks
## Supabase/live-state note
## Remaining follow-ups
```

## Validation expectations

Run the checks appropriate to the files changed:

- Always: `git diff --check`
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

Use generic placeholders such as `example-user`, `example-owner`, `example-memory-core`, `example-source-system`, `example-chat-export`, `Example Assistant`, `Example Project`, `example.local`, or `REDACTED`.

## Supabase and live state

Do not mutate live Supabase or any live database without explicit human approval for that exact target and operation.

Local/disposable database validation is allowed when the issue or PR requires it. Loader and validation paths should refuse non-local targets unless the user explicitly approves otherwise.

## Claims and conformance

Do not claim full SMP conformance unless tests and conformance documentation prove it.

Do not claim Chat-Mine quality is solved. Chat-Mine is currently a research-grade emitter with deterministic custody rails, not proven real-conversation mining quality.

## Merges

Do not merge without human approval.
