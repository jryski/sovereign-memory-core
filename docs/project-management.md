# Project management

This repo uses GitHub-native project management. The goal is practical coordination, not ceremony.

## Operating model

| Surface | Role |
|---|---|
| `README.md` | Entry point, current shape of the project, and links to durable docs. |
| `docs/` | Durable explanation, design docs, operation guides, roadmap, and ADRs. |
| Issues | Units of work, bugs, research tasks, conformance gaps, and follow-ups. |
| Pull requests | Reviewed changes with validation and public-safety notes. |
| Milestones | Release or phase targets. |
| GitHub Project | Board, roadmap, timeline, and filtered planning views. |
| ADRs | Architectural decisions that should survive chat transcripts. |
| Releases | Versioned snapshots once the project is ready to tag known-good states. |
| Discussions | Optional future venue for external or community design discussion. |

## Suggested GitHub Project

Project name:

> SMP Roadmap

Suggested views:

| View | Purpose |
|---|---|
| Board | Backlog / Ready / In Progress / Review / Done. |
| Roadmap | Issues grouped by target milestone. |
| Table | All issues with status, priority, track, risk, and target. |
| Publication | Publication, conformance, governance, and adoption work. |
| Alpha | Installer, review workflow, operator, and validation work. |
| Research | Chat-Mine evaluation and source-understanding research. |

Suggested fields:

| Field | Values |
|---|---|
| Status | Backlog / Ready / In Progress / Review / Done / Blocked |
| Track | Core / Docs / Alpha / Adapter / Research / Governance / Publication |
| Priority | P0 / P1 / P2 |
| Risk | Low / Medium / High / Research |
| Target | v0.1-alpha / v0.2-alpha / v0.3-alpha / v0.4-alpha / v0.5-alpha / v1.0 |

## Milestone structure

Use the milestones from [roadmap.md](roadmap.md):

- `v0.1-alpha - Custody Foundation`
- `v0.2-alpha - Local Operator Flow`
- `v0.3-alpha - Review Workflow`
- `v0.4-alpha - Adapter Profiles`
- `v0.5-alpha - Publication Candidate`
- `v1.0 - SMP Custody Layer Reference`

## Label taxonomy

Documented labels:

| Label | Meaning |
|---|---|
| `type:docs` | Documentation-only work. |
| `type:spec` | Normative or conformance-facing text. |
| `type:code` | Product or tooling implementation. |
| `type:test` | Validation, fixtures, test harnesses, or negative tests. |
| `type:research` | Investigation, evaluation, or unknown-quality work. |
| `type:infra` | CI, scripts, packaging, release, or repo automation. |
| `type:security` | Security posture, credential safety, or privacy work. |
| `type:governance` | Policy, contribution, release, or process decisions. |
| `track:core` | Core schema and validation. |
| `track:alpha` | Local operator alpha flow. |
| `track:adapter` | Adapter profiles and source import surfaces. |
| `track:publication` | Publication and conformance materials. |
| `track:chat-mine` | Chat-Mine emitter and evaluation work. |
| `track:installer` | Installer, doctor, local Docker, and setup UX. |
| `priority:p0` | Blocks public safety, correctness, or merge readiness. |
| `priority:p1` | Important near-term work. |
| `priority:p2` | Useful but not urgent. |
| `status:blocked` | Cannot proceed without a decision or dependency. |
| `status:needs-review` | Needs human or peer review. |
| `good-first-issue` | Small, bounded, newcomer-friendly task. |

This PR documents the taxonomy only. Creating or updating labels, milestones, and Projects can be done later through GitHub when explicitly approved.

## Issue practice

Issues should state:

- goal
- scope and non-goals
- acceptance criteria
- validation expectations
- public-safety or live-state guardrails
- related docs, scripts, fixtures, or ADRs

Research issues should also state what evidence would make the research actionable.

## PR practice

Each PR should include:

- summary
- issues addressed
- files changed
- validation run
- public-safety checks
- Supabase/live-state note
- remaining follow-ups

Draft PRs are appropriate for coordination. Ready-for-review means the author believes validation is complete for the stated scope.

## ADR practice

Use [docs/adr/0000-template.md](adr/0000-template.md) for decisions that affect architecture, trust posture, conformance, or contribution rules.

ADRs should be short. They record decisions and consequences; they do not replace implementation docs.
