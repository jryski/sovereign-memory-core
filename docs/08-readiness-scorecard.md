# 08 · 10/10 Readiness Scorecard

This scorecard defines what `sovereign-memory-core` must satisfy before it should be considered a 10/10 database schema and personal memory system.

## Scoring rule

A category is complete only when it has:

1. versioned repo artifact;
2. live deployment evidence;
3. repeatable validation check;
4. clear rollback or remediation path.

Claims without evidence do not count.

## 1. Source of truth and portability

- [ ] Repo contains every live schema object needed to recreate the system.
- [ ] Live DB object inventory matches repo migrations or documented intentional drift.
- [ ] Migrations are mirrored outside the hosting provider.
- [ ] Restore into vanilla Postgres has been rehearsed.
- [ ] Data exports exist in human-readable formats.
- [ ] Provider-exit test has a date, evidence, and findings.

## 2. Memory model

- [ ] Atomic facts live in `memories`.
- [ ] Durable documents live in `wiki_pages`.
- [ ] Active/proposed/superseded semantics are enforced and documented.
- [ ] Corrections supersede rather than overwrite.
- [ ] Deleted data requires explicit audited override.
- [ ] Stale historical state is quarantined as proposed or review-required.

## 3. Provenance and authority

- [ ] Every high-impact or consequential fact carries source/provenance.
- [ ] Financial figures are guarded by database triggers or equivalent checks.
- [ ] Accepted provenance bases are documented and consistent across memories, wiki, and vault.
- [ ] Model-authored claims are not silently promoted to human decisions.
- [ ] Human decisions are distinguishable from model summaries and inferences.
- [ ] Review queue surfaces low-confidence, stale, or proposed records.

## 4. Recall and attention

- [ ] `session_boot()` returns hot topics, deadlines, review counts, integrity, channel state, and health.
- [ ] Hot index or equivalent attention layer avoids loading the entire store.
- [ ] Hot-topic promotion has deterministic rules.
- [ ] Semantic/vector recall is treated as cache or assistive retrieval, not canon.
- [ ] Cutover probes prove important facts can be recalled after import or migration.
- [ ] Failure to recall critical facts creates an actionable remediation item.

## 5. Source import and authoritative cutover

- [ ] Source inventory complete.
- [ ] Freeze or watermark recorded where the source can change.
- [ ] Raw exports preserved with file hashes.
- [ ] Every source item has a manifest decision.
- [ ] HOUSE/VAULT/HOLD/EVIDENCE classification complete.
- [ ] Import counts match manifest counts.
- [ ] Payload hashes verify.
- [ ] Readiness checks pass.
- [ ] Critical cutover probes pass.
- [ ] Prior sources remain readable during rollback window where feasible.
- [ ] Owner explicitly approves authoritative cutover.

## 6. Trust boundaries and security

- [ ] Security model states the real boundary is the credential/connector/API surface.
- [ ] Broad credential blast radius is documented.
- [ ] No anon/authenticated/PUBLIC grants leak on protected objects.
- [ ] Views use `security_invoker` where appropriate.
- [ ] SECURITY DEFINER functions pin `search_path`.
- [ ] Private schemas have no unintended grants.
- [ ] Least-privilege API or role hardening path is designed and prioritized.
- [ ] Sensitive domains are separated by schema, project, or credential as appropriate.

## 7. VAULT readiness

- [ ] Raw restricted records are preserved before normalization.
- [ ] Payload hashes are computed and verified.
- [ ] Normalized rows link back to preserved source records.
- [ ] Identity, health, finance, and legal/authority records are person-centered.
- [ ] Temporal truth is modeled with observed/recorded/effective windows where needed.
- [ ] Vault audit logs keys only, not duplicate sensitive payloads.
- [ ] Capability assignments are explicit rows, not implied by role names.

## 8. Operations

- [ ] Backup process documented.
- [ ] Backup checksum process documented.
- [ ] Restore rehearsal documented and repeated after schema overhauls.
- [ ] Weekly ops ritual exists and is usable by any approved assistant.
- [ ] Migration drift check exists.
- [ ] Derived-index backlog, attention backlog, review queue, and overdue deadlines are surfaced.
- [ ] Bulk transfers avoid model context and tool stdin when server-side staging or file transfer is available.
- [ ] Bulk transfers are verified by counts and checksums before import or promotion.
- [ ] Incident runbook exists for bad writes, leaked credentials, failed restore, integrity mismatch, and corrupted transfer.

## 9. Multi-model coordination

- [ ] `model_channel` or equivalent is documented.
- [ ] Model messages are treated as untrusted content.
- [ ] Replies have deterministic references.
- [ ] Message retrieval uses ordering/sequence, not semantic search.
- [ ] Cross-model reviews preserve disagreement without treating models as authority.
- [ ] Peer-review operating rule exists for schema changes.

## 10. Repo quality

- [ ] README distinguishes core repo from UI repo.
- [ ] STATUS file tracks repo/live divergence without embedding one deployment's private inventory.
- [ ] All SQL is versioned and idempotent or clearly migration-scoped.
- [ ] Acceptance tests are copy-pasteable or scriptable.
- [ ] Every high-risk claim is either tested or downgraded.
- [ ] Issues track remaining hardening work.
- [ ] Release tags mark known-good schema versions.

## Current blockers to 10/10

1. Source-import/cutover foundation is committed, but full Draft 0.3 lifecycle coverage is incomplete: REVIEWED, PARALLEL, AUTHORITATIVE, explicit authority declaration, and offline third-party verification remain gaps.
2. Executable validation covers current source-import/cutover rails, candidate locators, quote hashes, rollback loader proof, and richer probe categories, but does not yet prove full SMP Draft 0.3 conformance.
3. No stored provider-exit evidence artifact in repo.
4. Least-privilege access hardening is designed conceptually but not implemented.
5. UI/review workflow is split to a new repo and not yet complete.
6. Peer review of the SQL implementation is ongoing.
7. License and contribution posture remains unresolved in #38.

## Target definition of done

`sovereign-memory-core` reaches 10/10 when a new approved operator can:

1. clone the repo;
2. apply migrations to a fresh Postgres/Supabase project;
3. run acceptance tests;
4. import or reconcile records from an existing source;
5. verify payload hashes and readiness checks;
6. run cutover probes;
7. restore from backup into vanilla Postgres;
8. prove service boundaries and grant posture;
9. boot with `session_boot()`;
10. continue work without relying on vendor-native memory or any prior non-authoritative source.
