# Topology and search-scope correctness

Issue [#72](https://github.com/jryski/sovereign-memory-core/issues/72)
prevents a local search miss from being broadened into an unsupported global
negative. This is a correctness/availability contract; topology rows are
**deployment-configuration evidence**, not routing or search authority.

## Installation and public seams

Apply `sql/12_topology_scope.sql` after `sql/11_perimeter_evaluability.sql`.
Slot 12 is the next free migration after perimeter evaluability; slot 11 remains
that evaluability boundary. Topology/search-scope is safe to reapply and adds:

- `public.topology_profile_boot(viewer text)`;
- topology output under `public.session_boot(viewer text)`;
- `public.search_coverage_receipt(viewer text, attempts jsonb)`;
- bounded age/blocking/stale metadata under `channel_inbox`; and
- `channel_inbox_coverage` with `total_visible`, `represented`, `omitted`,
  `limit`, and `status`.

The topology JSON conforms to
[`contracts/topology-profile-v1.schema.json`](contracts/topology-profile-v1.schema.json).
The migration-pinned SHA-256 of that schema is
`938976903383ef5cf43af48ffe5e03a3f1be212cff5d1ea947caef2debec82fd`.

Topology output contains canonical store IDs, deployment-neutral profiles,
relationships, search scopes, separate configuration/coverage states, and no
URLs, routing endpoints, credentials, project references, principal names, or
private deployment names. `p_viewer` remains a logical-filter argument for the
rest of boot; it is not authentication under a shared service credential.
Accordingly, the public topology seam returns shared sanitized rows only.

## Search-coverage attempts and receipts

Input is an exact versioned object with `schema_version` and `attempts`; unknown
keys are rejected. `attempts` is an array of at most 32 objects:

```json
{
  "schema_version": "1",
  "attempts": [{
    "store_id": "local-store",
    "scope": "default",
    "status": "queried",
    "hit_count": 0
  }]
}
```

`status` is `queried` or `unreachable`; an unreachable attempt has zero hits.
`hit_count` is an integer from 0 through 1,000,000. Store IDs must identify an
enabled, advertised store in the shared sanitized topology, scopes must match configuration
evidence, and store IDs may not repeat.
Store IDs, profiles, owners, and scopes use the lowercase ASCII grammar
`[a-z0-9][a-z0-9._-]*` at their documented maximum lengths. Receipt attempts are
rendered in canonical store-ID order regardless of input order.

The receipt labels its source `client-reported` and its authority
`client-reported-coverage-not-search-authority`. Validation prevents malformed
claims from entering the receipt, but it does **not** prove that a client really
queried a peer. The server does not connect to peers and stores no routes.

The coverage denominator is **every registered store**, not only the
advertised, enabled, shared subset a viewer can query. Stores outside that
subset — private, unadvertised, or disabled — are excluded from viewer-queryable
coverage. Their identifiers stay out of `visible_known_stores` and out of the
receipt. The receipt reports only the count `stores_not_visible_to_viewer`.
`visible_advertised_stores` remains the viewer-queryable count.
`advertised_unqueried_stores` remains the gap inside that queryable set.

`coverage_complete` and `global_absence_supported` are true only when that
excluded count is zero. A hidden registered peer therefore keeps
`global_absence_supported` false after every visible store was queried
successfully. Identity suppression stays a privacy property; it is not evidence
that the withheld store does not exist.

Classification precedence after validation is:

1. `unknown_topology` when the profile singleton is absent, topology is
   `unknown`/`not_configured`, the canonical enabled advertised local-store row is
   absent, or registered coverage exceeds the bounded contract;
2. `local_hit`;
3. `remote_hit`;
4. `unreachable_peer`;
5. `partial_miss` when any registered store was not reported queried, including
   a store excluded from the viewer-queryable set; and
6. `complete_miss` only when every registered store was reported queried with
   zero hits, which requires zero excluded stores.

Therefore a local miss while an advertised peer remains unqueried is always
`partial_miss`, never a complete or global “nothing found.”
The explicit `global_absence_supported` receipt field is true only for
`complete_miss` with a configured canonical local store, bounded registered
topology, zero stores excluded from the viewer, every registered store queried,
and no unreachable store. It is false for every other classification.
`coverage_complete` uses the same zero-excluded requirement and is false when
local identity is missing, even if the client submits an empty attempts array.

Validation error precedence is stable: object/version envelope, 32-attempt bound, object
and exact keys, JSON scalar types, status, duplicate store ID, visible store
identity/scope, then count range and unreachable-count semantics.

## Attestation and recovery

The profile exposes expected and observed contract version/digest metadata with
`match`, `mismatch`, or `unknown`. Missing observed fields are `unknown`; any
complete nonmatching pair is `mismatch`. These are non-secret deployment metadata
receipts and fail closed. They do not substitute for topology/scope correctness.
Broader contract drift detection remains tracked separately by
[#70](https://github.com/jryski/sovereign-memory-core/issues/70).

A mismatch, unknown topology, unreachable peer, or incomplete instruction
attestation never disables local read-only boot. Callers may inspect local visible
state, but must label coverage limitations and avoid globally complete claims.

## Minimal static fallback

A client that cannot reach the introspection seam may retain a minimal static
fallback containing only a schema/version, a non-secret local profile hint, and
generic scope labels needed to choose a boot call. This fallback is
**non-authoritative client evidence**. It must not contain credentials, endpoints,
private store names, deployment routes, or a claim that any store was queried.
Once introspection is available, the runtime response supersedes the fallback as
current configuration evidence; neither artifact is search authority.
