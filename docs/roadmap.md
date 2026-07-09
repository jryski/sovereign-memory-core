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

The repo is in `v0.1-alpha - Custody Foundation`.

The custody rails are mostly implemented and are being documented, hardened, and organized for repeatable contribution. The local operator path is next: a contributor should be able to install, validate, import a fixture, run a rollback loader proof, and understand what is safe before touching any live system.

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
