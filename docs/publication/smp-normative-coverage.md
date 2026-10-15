# Draft 0.3 normative keyword map

Checklist for bold RFC 2119 keywords in [`smp-custody-layer.md`](smp-custody-layer.md). Each row names the spec wording, the keyword, and the conformance-audit ID that tracks it.

```bash
python3 scripts/check_normative_coverage.py
```

The command fails when a bold `MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`, or `MAY` in the spec is absent from the table below, when an uppercase keyword is not bold, or when a mapped audit ID is absent from [`smp-conformance-gap-audit.md`](smp-conformance-gap-audit.md). The RFC 2119 definition sentence is not a requirement and is ignored.

This map does not claim SMP Draft 0.3 conformance. A passing check means the keyword inventory and the audit ID column still agree. It does not mean a requirement is implemented or backed by a passing probe. Coverage posture stays in the conformance gap audit.

Keywords are taken from the spec text as written. An anchor must be a unique substring, must contain one bold keyword, and must not contain `|`.

## Keyword map

| Anchor | Keyword | Audit ID |
|---|---|---|
| only the principal or a delegate the principal has authorized **MAY** declare authority | MAY | T2 |
| A store **MAY** be local, hosted, personal, team-based, or enterprise-operated | MAY | T4 |
| A package **MUST** declare the `smp_version` it targets | MUST | T1 |
| An emitter **MAY** be deterministic, model-assisted, or model-driven | MAY | T5 |
| Migrations **MAY** proceed scope by scope | MAY | T3 |
| An item **MUST NOT** be normalized or trusted unless its raw source payload is preserved and content-hashed first | MUST NOT | I1.1 |
| A derived record **MUST** reference its evidence by locator and hash | MUST | I1.2 |
| **MUST NOT** be counted as a migrated fact | MUST NOT | I1.3 |
| it **MAY** be retained as a note or orphaned assertion, marked as such | MAY | I1.3 |
| Every source item **MUST** receive at least one explicit disposition | MUST | I2.1 |
| A single source item **MAY** yield multiple candidate records | MAY | I2.2 |
| The manifest **MUST** be frozen and hashed before load | MUST | I2.3 |
| reconciliation **MUST** reach zero unexplained source items | MUST | I2.4 |
| The reconciliation report **MUST** count, separately | MUST | I2.5 |
| Every imported record **MUST** carry a provenance basis drawn from a closed set | MUST | I3.1 |
| and **MUST** preserve the distinction between human-authored, human-confirmed, and agent-authored content | MUST | I3.2 |
| Agent-authored content **MUST NOT** be silently promoted to human authority | MUST NOT | I3.3 |
| A deployment **MUST** declare its **consequential domains** | MUST | I3.4 |
| Deployments **MAY** declare additional consequential domains | MAY | I3.4 |
| **MUST** be rejected at write time rather than flagged for later review | MUST | I3.5 |
| A probe suite **MUST** include all five categories | MUST | I4.2 |
| Probes designated *critical* for a scope **MUST** all pass before cutover | MUST | I4.3 |
| Corrections **MUST** append | MUST | I5.1 |
| history **MUST NOT** be silently rewritten | MUST NOT | I5.1 |
| the earlier record **MUST** be preserved | MUST | I5.2 |
| and **MAY** be marked stale, superseded, conflicted, or historical | MAY | I5.2 |
| Cutover **MUST** remain reversible until the authority declaration is recorded | MUST | I5.3 |
| that declaration **MUST** itself be a recorded, evidenced event | MUST | I5.4 |
| Each transition **MUST** record a durable artifact | MUST | L1 |
| A transition without its artifact **MUST NOT** be considered to have occurred | MUST NOT | L1 |
| Failure at any gate **MUST** return the system to a prior safe state | MUST | L2 |
| and no gate **MAY** be skipped | MAY | L3 |
| and **MUST** carry one state | MUST | R1 |
| - **hold** — **MUST NOT** be promoted yet | MUST NOT | R2 |
| - **exclude** — **MUST NOT** become memory | MUST NOT | R3 |
| and **MUST NOT** be normalized into a memory fact | MUST NOT | R4 |
| Promotion of a candidate to authoritative memory **MUST** require an explicit review decision by the principal or an authorized delegate | MUST | R5 |
| No import path **MAY** promote a candidate to authority automatically | MAY | R6 |
| Evidence fields **SHOULD** include | SHOULD | H1 |
| **MUST** carry a source quote and a hash of that quote | MUST | H2 |
| A store **MUST** treat emitter output as proposed input to review and verification | MUST | E1 |
| a structurally valid package **MUST NOT** by that fact alone cause any candidate to be promoted | MUST NOT | E2 |
| An adapter profile **MUST** specify | MUST | C1 |
| which validation probes **MUST** pass | MUST | C1 |
| An adapter profile **MUST** declare its **lossiness** | MUST | C2 |
| A profile that cannot round-trip a field **MUST** say so rather than silently drop it | MUST | C3 |
| A system **MUST NOT** claim conformance merely because it stores fields named "provenance" or "memory." | MUST NOT | CNF1 |
| A store **MUST** make in-place mutation of a promoted record either structurally impossible or content-hash audited | MUST | CNF4 |
| This verification **MUST** be possible offline, without cooperation from the source system or the emitter | MUST | CT5 |
| An agent **MAY** propose durable changes to a store's source-of-record | MAY | A1 |
| but **MUST NOT** promote them to authoritative state without an explicit review decision | MUST NOT | A1 |
| in-place changes by an agent **MUST** be content-hash audited | MUST | A2 |

## Audit rows without a bold RFC 2119 keyword

These audit rows track normative or doctrine prose that does not use a bold RFC 2119 keyword, so the extractor does not list them. They remain in the conformance gap audit:

`I4.1`, `I4.4`, `H3`, `CNF2`, `CNF3`, `CNF5`, `CT1`, `CT2`, `CT3`, `CT4`.

`I4.4` stays a gap. The keyword map records where claims are written. It does not show that those claims are backed by passing probes.

## CI

GitHub Actions does not run this check yet. A later workflow can run `python3 scripts/check_normative_coverage.py` when the spec, this map, or the conformance gap audit changes. Leaving it unwired is intentional for this cut.
