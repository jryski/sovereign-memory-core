# 08 · Readiness criteria

This document is a **reference-implementation readiness checklist**, not a
numeric score and not a deployment inventory.

The previous version mixed Core quality, one deployment's operating model,
private-domain concepts, UI work, and agent coordination into a single "10/10"
score. That made the number subjective and blurred repository boundaries.

For current release state, use [`../STATUS.md`](../STATUS.md). For exact
`v0.3-alpha` claim limits, use
[`../release/v0.3-alpha-known-limitations.md`](../release/v0.3-alpha-known-limitations.md).

## Scoring rule

A Core capability should be called ready only when the relevant combination of
these exists:

1. versioned repository artifact;
2. executable validation;
3. adversarial/negative coverage where failure matters;
4. documented rollback or remediation behavior;
5. release-scoped evidence when the capability is part of a release claim.

A downstream deployment may require additional acceptance evidence. Deployment
success does not automatically broaden Core support, and Core CI does not
certify an unmeasured deployment.

## 1. Schema and lifecycle

- [ ] Core schema is versioned and reproducible from the repository.
- [ ] Accepted/proposed/superseded semantics are explicit.
- [ ] Corrections preserve history rather than silently replacing it.
- [ ] Evidence/provenance relationships are reconstructable.
- [ ] Concurrent replay and duplicate input have deterministic outcomes.
- [ ] Migration upgrade and reapply behavior is tested.

## 2. Authority and security

- [ ] The trust boundary is stated honestly.
- [ ] Direct, inherited, membership-chain, and `PUBLIC` privilege paths are evaluated.
- [ ] RLS/FORCE RLS posture is measurable where required.
- [ ] Ownership and default privileges are included in perimeter evaluation.
- [ ] `SECURITY DEFINER` surfaces are inventoried and hardened against search-path/temp shadowing.
- [ ] Unevaluable security state fails closed rather than reporting clean.
- [ ] Broad/shared credential limitations are documented rather than hidden.

## 3. Portability and recovery

- [ ] Export/package format is versioned.
- [ ] Package validation rejects unsupported or unclassified loss.
- [ ] Restore is exercised on an independent clean target.
- [ ] Source-before/source-after checks prove the source was unchanged.
- [ ] Restored structure and security-relevant objects are compared.
- [ ] Positive and denial controls prove the restored system is both usable and bounded.
- [ ] Recovery artifacts and release artifacts have durable integrity receipts.
- [ ] Supported PostgreSQL/provider ranges are stated explicitly and are not broadened by anecdotal success.

## 4. Drift and reproducibility

- [ ] Schema drift has an executable comparison contract.
- [ ] Comparison inputs are bound to the candidate being reviewed where the claim requires it.
- [ ] Empty/unevaluable comparison inputs cannot pass as clean.
- [ ] Release artifacts are generated from the exact reviewed candidate.
- [ ] Checksums cover the intended artifact set and the checksum root is recorded externally.

## 5. Source import and adapters

- [ ] Adapter/source profile declares what was observed and what may be lossy.
- [ ] Raw/source evidence can be retained or referenced without silently promoting derived claims.
- [ ] Import decisions distinguish accept, hold, reject, and conflict states where applicable.
- [ ] Counts/hashes reconcile before a source is treated as successfully transferred.
- [ ] Rollback or source-continuity posture is documented.
- [ ] Source-understanding quality is measured independently from package determinism.

## 6. Public-repository quality

- [ ] README clearly says what Core is and is not.
- [ ] STATUS reflects the current release rather than an obsolete development phase.
- [ ] Roadmap does not encode stale version promises as current truth.
- [ ] Public examples and fixtures are synthetic.
- [ ] No private deployment identifiers, credentials, topology, or payloads are committed.
- [ ] High-risk claims are either executable/reviewed or explicitly downgraded.
- [ ] Issues track defects and follow-ups without requiring private-chat archaeology.

## 7. Release discipline

Before publishing a release that claims a capability:

- [ ] freeze an exact candidate commit/tree;
- [ ] run the required workflows against that candidate;
- [ ] preserve reproducible receipts;
- [ ] record known limitations;
- [ ] independently review load-bearing evidence;
- [ ] ensure integration does not silently change the reviewed coordinate;
- [ ] publish checksummed artifacts from the same candidate;
- [ ] require owner/release authorization where the release procedure says so.

## Deployment acceptance is separate

A real deployment should have its own acceptance checklist covering its actual
provider, PostgreSQL version, credentials, backups/recovery anchors, private
data, hosted services, connectors, and operational rollback plan.

That checklist belongs with the deployment. Only generic defects that can be
reproduced safely with synthetic evidence should be promoted into this public
Core repository.
