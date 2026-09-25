# Roadmap

## Project north star

Sovereign Memory Core exists to make AI memory transfer trustworthy.

Short form:

> Trustworthy memory transfer.

Operational framing:

> Chain of custody for AI memory.

Formats move bytes. SMP proves memory transfer earned authority.

The project should not compete to become the winning memory-record format. It should provide the custody, verification, provenance, review, and cutover layer around many possible sources, exports, applications, and future memory formats.

## Current phase

Public posture is **alpha**, the same posture as the README. Tag `v0.3-alpha` names commit `c96b9da749b2d95661973485b2a026897329c8cd` (2026-08-15). That tag is a reviewed coordinate with bounded limitations. It is not independent live acceptance. Export to a portable package and clean restore outside the originating host remain unproven. Issue #92 holds recovery and live acceptance as implementation work. Related open issues are #58 and #52. Closed issue #55 is historical program context for the v0.3-alpha program. Current pointers live in [`STATUS.md`](../STATUS.md).

The phase names later in this file (`v0.1-alpha - Custody Foundation`, `v0.3-alpha - Review Workflow`, and the rest) are older product-milestone vocabulary. They are a different statement from the `v0.3-alpha` git tag. Where a milestone name and STATUS disagree, STATUS and the README win.

Custody rails that are in the repository can be reviewed from the migrations and CI. The local operator path, and the review-workflow milestone below, remain forward targets. Export, clean restore, and live acceptance are blocked.

## What is done

- Core Postgres schema for memory, wiki, attention, provenance, supersession, and operating-doc integrity.
- Optional vault schemas and provenance guards.
- Generic source-import/cutover foundation.
- Candidate locators and candidate-level quote hashes.
- Richer cutover probe categories.
- Deterministic Chat-Mine package fixture.
- Rollback-only loader proof.
- Negative package mutation tests.
- Negative SQL corruption tests.
- Public-readiness scrub of tracked examples and fixtures.
- Source-import validation with fatal blocker checks.

## What is next

- Finish project organization, ADRs, and contribution paths.
- Document durable-write policy for protected memory scopes.
- Build the local operator flow: `smc doctor`, local Docker install, schema installer, validation runner, and safe database URL checks.
- Add review workflow for accept, hold, reject, and evidence display.
- Define adapter profiles without making Chat-Mine quality claims.

## Tracks

| Track | Purpose | Current posture |
|---|---|---|
| Alpha build | Make the custody layer installable, verifiable, reviewable, and recoverable by an operator. | Active near-term work. |
| Publication | Explain SMP custody concepts, conformance gaps, and adoption path without overclaiming implementation completeness. | Drafting and review. |
| Research | Improve Chat-Mine and other emitters through evaluation, not claims. | Explicitly separate from alpha build. |

## Milestones

### v0.1-alpha - Custody Foundation

Mostly complete or in documentation-finalization phase.

Includes:

- source-import foundation
- candidate locators and quote hashes
- cutover probe categories
- deterministic Chat-Mine package fixture
- rollback loader proof
- negative package mutation tests
- negative SQL corruption tests
- public-readiness scrub
- north-star docs
- publication docs
- conformance gap audit
- durable-write policy

### v0.2-alpha - Local Operator Flow

Includes:

- `smc doctor`
- local Docker install
- schema installer
- validation runner
- safe database URL checks
- operator documentation

### v0.3-alpha - Review Workflow

Includes:

- review queue
- accept / hold / reject flow
- evidence display
- candidate status transitions
- basic review UI or CLI review

### v0.4-alpha - Adapter Profiles

Includes:

- adapter profile template
- generic external source profile
- lossiness declaration format
- sample import profile
- round-trip/export profile
- no real Chat-Mine quality claims

### v0.5-alpha - Publication Candidate

Includes:

- conformance fixture
- public docs
- license/IP checklist
- history/privacy caveat
- release notes
- demo walkthrough

### v1.0 - SMP Custody Layer Reference

Includes:

- stable custody-layer reference implementation
- conformance docs
- adoption/ratification criteria
- release artifacts

## Release targets

| Release | Target outcome |
|---|---|
| `v0.1-alpha` | Custody foundation can be reviewed and validated from the repo. |
| `v0.2-alpha` | A local operator can install and validate the foundation without manually interpreting every SQL file. |
| `v0.3-alpha` | Candidate review and promotion are visible, testable, and bounded. |
| `v0.4-alpha` | External sources can declare profile, lossiness, and evidence posture. |
| `v0.5-alpha` | The repo can support a public release candidate with clear conformance gaps. |
| `v1.0` | SMP custody-layer reference behavior is stable enough for adoption testing. |
