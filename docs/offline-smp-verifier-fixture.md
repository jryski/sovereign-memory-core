# Offline SMP verifier fixture

Synthetic custody fixture for a small named scope. A third party can run the
validator with the files in [`fixtures/smp_offline/`](../fixtures/smp_offline/)
and nothing else: no source system, no emitter cooperation, no network, and no
database.

This fixture does not claim SMP Draft 0.3 conformance. It does not close that
claim, and it does not by itself close the remaining offline-verifier gaps.
Related work still open includes live restored-instance probes, generalized
consequential-domain enforcement, and the installer custody path.

## What a third party is given

| File | Role |
|---|---|
| `package.json` | Synthetic source package, raw payloads, and quotes |
| `manifest.json` | Frozen disposition ledger and reconciliation counts |
| `evidence-hashes.json` | SHA-256 ledger for payloads and quotes |
| `probe-definitions.json` | Versioned probe suite, including checks that would otherwise need a restored database |
| `probe-results.json` | Recorded results for that suite |
| `cutover-record.json` | Authority declaration for the scope |
| `destination-store.json` | Destination-store description: schema identity, restore-target fingerprint, backup digest, exclusions, and source/restored row sets |
| `canonical-governed-state.v1.json` | The one bound canonical governed-state definition |
| `backup/synthetic-scope-backup.txt` | Synthetic backup bytes named by the destination-store description |

The destination-store description includes one conflict, one stale claim, one
held item, one excluded item, and one tombstone/erasure case. Agent-authored
content stays unpromoted. The promoted consequential identity claim is the
public label **Primary Users**. Labels in this fixture are synthetic.

## Receipt

`main` does not already contain a custody-receipt verifier. This fixture follows
the receipt field set in the unmerged design notes for that contract, including
result states `installed`, `backup_created`, `custody_verified`,
`verification_failed`, and `verification_skipped`. It does not define a second
proof format. Canonical encoding is the existing UTF-8 RFC 8785 subset in
[`scripts/sovereignty_bundle.py`](../scripts/sovereignty_bundle.py), with one
trailing LF. Digests are SHA-256 of those bytes, or of the backup file bytes.
Row-set hashes cover the projected governed fields after declared exclusions.
They are not byte-for-byte database equality. Ranking scores, embeddings,
sequence values, cache tokens, and physical order are excluded and may differ
between the source and restored projections.

The success result for this fixture is `custody_verified`. The validator prints
that receipt as canonical JSON on standard output. Standard error is
`SMP-complete` only when the receipt result is `custody_verified` and
`skip_or_failure_reason` is null. Any failed check prints `verification_failed`
and the specific reason, and the receipt result is `verification_failed`.

Functional probes are recorded definitions and results inside the fixture. The
validator checks those records against the destination-store description. It
does not connect to PostgreSQL. Structural checks performed from the fixture
alone are foreign-key integrity, supersession acyclicity, checkpoint-chain
verification, tombstone/erasure preservation, and candidate/promotion
boundaries.

The receipt signer method is `canonical-sha256`: SHA-256 of the canonical
receipt with `signer.signature` set to an empty string. That is a local
content binding for this fixture, not an external transparency signature.
`tool.source_commit` is `unreleased` because this slice is not a release
commit.

## Run

From the repository root:

```bash
python3 scripts/validate_smp_offline_fixture.py fixtures/smp_offline
python3 scripts/validate_smp_offline_fixture.py fixtures/smp_offline --inject flatten_conflict
python3 -m unittest discover -s tests/offline_verifier -p 'test_*.py' -v
```

`--inject flatten_conflict` is an in-memory negative case. It must not report
`SMP-complete`. Other injections cover an unaccounted source item, missing
consequential evidence, promoted agent content, a dropped authority
declaration, a broken checkpoint, and a resurrected tombstone.
`--inject non_governed_noise` changes only excluded fields and still reports
`SMP-complete` with the same row-set hash.

JSON inputs must already be canonical. The validator reads the fixture
directory only and refuses backup paths that leave that directory.
