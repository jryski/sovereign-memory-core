# Work Memory Protocol

Work memory records what an agent learned about doing work. It is not a substitute for user facts, source evidence, or canonical project documentation.

## Authority lifecycle

A lesson starts as `proposed`. Only an explicit sanctioned acceptance call may move it to `accepted`. Behavioral `rule` and `prohibition` lessons additionally require at least one current evidence record whose `resolution_state` is `resolvable`.

Rejected proposals remain append-only readable history. They do not occupy the predecessor’s live-successor slot, so a corrected replacement successor can be proposed later.

The lifecycle is:

```text
propose
  -> add or correct evidence
  -> accept | reject

accepted predecessor
  -> propose successor
  -> accept successor and supersede predecessor
     or reject successor and permit a replacement proposal
```

## Evidence locators

The public protocol deliberately avoids deployment-specific store names.

Supported kinds are:

| Kind | Canonical shape |
|---|---|
| `coordination_ref` | `coordination:<scheme>:<opaque-reference>` |
| `memory` | `memory:<uuid>` |
| `migration` | `migration:<portable_name>` |
| `artifact` | `artifact:sha256:<64 lowercase hex>` |
| `public_source` | `public_source:https://...` |
| `other_durable_locator` | `other:<scheme>:<opaque-reference>` |

A deployment may map `coordination_ref` to a private channel, ticket system, audit ledger, or another durable coordination store. Those mappings and real references do not belong in this repository.

## Custody

`work_lessons` is mutation-gated. Evidence and authority events are append-only. Corrections append a successor evidence row rather than modifying the predecessor.

The runtime role receives:

- `SELECT` on the protected tables;
- execution only on bounded proposal, evidence, acceptance, rejection, supersession, and boot APIs;
- no direct insert, update, delete, truncate, trigger, reference, or schema-creation power.

RLS and FORCE RLS are enabled. The final perimeter assertion verifies the expected policies, owners, ACLs, and SECURITY DEFINER search paths.

## Boot behavior

`work_lessons_boot_fragment()` returns accepted active rules and prohibitions in deterministic order:

1. `learned_on DESC`
2. `created_at DESC`
3. `id`

Tests do not assume an empty database. Every synthetic fixture is identified by its own durable key and is rolled back.
