# Sovereign Memory Core status

Last updated: 2026-08-15

## Current state

`v0.3-alpha` is published as a prerelease.

The alpha release closed the finite release program tracked in issue #55 and
established a reviewed PostgreSQL reference runtime with:

- PostgreSQL 15/16 conformance coverage;
- fail-closed perimeter evaluability;
- reviewed authority and `SECURITY DEFINER` hardening;
- lifecycle, provenance, supersession, replay, and concurrency tests;
- executable provider-exit package/restore evidence on PostgreSQL 16;
- schema-drift comparison;
- checksummed release artifacts and exact-coordinate review;
- a separate HOUSE deployment recovery rehearsal with a retained logical anchor
  and a PostgreSQL 17.10 public-schema restore.

The HOUSE rehearsal is deployment-specific and does **not** expand Core's
provider-exit support range beyond PostgreSQL 15 and 16. See
[`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md).

## What this repository owns

Core owns the PostgreSQL reference implementation and its executable evidence:

- migrations and database contracts in `sql/`;
- conformance and adversarial tests in `tests/`;
- export/restore, schema-drift, and release tooling in `scripts/`;
- synthetic fixtures in `fixtures/`;
- implementation and operator documentation in `docs/`;
- release procedures and limitations in `release/`.

Core does **not** own a particular household or business deployment, private
operating evidence, production credentials, a consumer UI, or the
implementation-neutral protocol specification itself.

## Current supported release surface

| Surface | v0.3-alpha status |
|---|---|
| PostgreSQL 15 | CI/conformance covered |
| PostgreSQL 16 | CI/conformance + provider-exit rehearsal covered |
| PostgreSQL 17 | Not in declared provider-exit support range; one deployment-specific recovery procedure was exercised separately |
| Perimeter evaluability | Fail-closed clean / violated / unsupported contract |
| Portable package/restore | Proven for the declared synthetic provider-exit profile |
| Hosted-provider product reconstruction | Not claimed |
| Cryptographic principal attribution | Not claimed |
| Full physical erasure across every external copy | Not claimed |

## Known release limitations

Do not reconstruct the alpha's limitations from issue history. The canonical
release-scoped list is:

[`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md)

That document includes the important boundaries around hosted-service
portability, HOUSE's partial plain-PostgreSQL restore, PostgreSQL 17 scope,
actor attribution, perimeter findings, checksum semantics, schema-drift
comparison, source-fingerprint binding, and erasure.

## Post-alpha priorities

The release is no longer blocked on the old C1/C2/#59 sequence. New work should
be justified independently rather than reopening completed release gates.

Current classes of follow-up work are:

1. **Protocol/specification separation** — continue extracting
   implementation-neutral semantics from the PostgreSQL reference runtime
   without forcing deployment behavior into Core.
2. **Deployment/runtime boundary cleanup** — keep household and organizational
   deployment state outside this public reusable repository.
3. **Least-privilege and attribution hardening** — reduce reliance on broad or
   shared credential paths and improve independently verifiable actor identity.
4. **Provider-exit evolution** — expand profiles or PostgreSQL-version support
   only when new independent evidence exists.
5. **Source-adapter and review workflows** — exercise real adapter/review flows
   without weakening custody, provenance, conflict, or rollback semantics.
6. **Documentation and operator ergonomics** — make safe paths obvious without
   hiding the limits of the alpha.

## Public/private boundary

This is a public reference repository.

Private deployment inventories, real project identifiers, credentials, private
hostnames, personal records, household records, business records, recovery
artifacts, and private operating receipts belong outside this repository.
Synthetic fixtures may model the same behavior without carrying real data.

## Development rule

Treat conformance claims as executable claims.

A generic defect discovered in a deployment should be reproduced with sanitized
synthetic evidence before being promoted into Core. Deployment-specific product
behavior should stay downstream. Changes to runtime semantics should come with
appropriate regression/adversarial coverage and should not silently broaden the
scope of a published release.

For contribution mechanics, see [`CONTRIBUTING.md`](CONTRIBUTING.md).
