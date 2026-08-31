# Wiki outline: Sovereign Memory Core public documentation

Status: draft wiki/navigation plan.
Purpose: provide a navigable public explanation of the project without turning the blog into the source of truth.

## Recommended wiki structure

### 1. Start here

Path idea: `wiki/start-here`

Purpose:
Introduce the project in plain language.

Sections:
- What Sovereign Memory Core is
- What problem it solves
- What it does not solve yet
- Current project maturity
- Where to go next

### 2. North star

Path idea: `wiki/north-star`

Purpose:
Explain trustworthy memory transfer.

Sections:
- The one-sentence doctrine
- Custody, provenance, review, cutover
- Why apps and models are clients
- Why evidence is not the same as truth
- Current boundaries

Source doc:
- `docs/00-north-star.md`

### 3. Architecture map

Path idea: `wiki/architecture-map`

Purpose:
Translate the repo architecture into a reader-friendly mental model.

Sections:
- Tier 1 shared knowledge
- Tier 2 private vault
- Source-import/cutover
- Candidate evidence
- Probe scorecards
- Operators and assistants

Source docs:
- `docs/01-architecture.md`
- `docs/02-security-model.md`
- `docs/07-source-import-cutover.md`

### 4. Project story

Path idea: `wiki/project-story`

Purpose:
Explain how the project evolved.

Sections:
- Personal memory pain
- Database and wiki split
- Session boot and model channel
- Vault and consequential domains
- Source import and cutover
- Protocol pivot
- Chat-Mine research posture
- Live/repo dogfood

Source doc:
- `docs/publication/project-story-timeline.md`

### 5. Blog series index

Path idea: `wiki/blog-series`

Purpose:
Track blog drafts, publishing state, and core messages.

Sections:
- Series thesis
- Post list
- Status per post: idea, drafted, reviewed, published
- Links to final posts when published externally
- Claims checklist

Source doc:
- `docs/publication/blog-series-starters.md`

### 6. Claims and boundaries

Path idea: `wiki/claims-boundaries`

Purpose:
Prevent overclaiming.

Allowed claims:
- The project is building a custody layer for AI memory transfer.
- The repo contains source-import and cutover scaffolding.
- Candidate-level evidence and cutover probes are design goals and active implementation areas.
- Chat-Mine rails can be deterministic in fixtures.

Disallowed claims for now:
- Full SMP Draft 0.3 conformance.
- Real conversation mining quality is solved.
- Any live deployment is authoritative without a completed cutover.
- Any model output is durable truth without review.

### 7. Operator guide

Path idea: `wiki/operator-guide`

Purpose:
Help future users run the system safely.

Sections:
- Fresh install path
- Backup/restore
- Import workflow
- Review workflow
- Cutover workflow
- Rollback posture
- Security checks

Source docs:
- `docs/04-implementation-guide.md`
- `docs/05-operations.md`
- `docs/08-readiness-scorecard.md`

### 8. Contributor map

Path idea: `wiki/contributor-map`

Purpose:
Help contributors find useful work.

Sections:
- Core custody layer
- Source adapters
- Review UI
- Operator tooling
- Chat-Mine research
- Documentation
- Test fixtures

Source docs:
- `docs/roadmap.md`
- `docs/project-management.md`
- `CONTRIBUTING.md`

## Wiki maintenance rules

1. Repo docs remain the durable implementation source.
2. Blog posts are narrative, not normative.
3. Wiki pages can summarize and navigate, but should link back to repo docs.
4. Any conformance or readiness claim must point to the current status/gap audit.
5. Any public-facing page should include the project maturity boundary.
