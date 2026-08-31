# SAOS-0017 — Context Envelope v0.1

**Status:** candidate specification; documentation-only, implementation-neutral
**Version:** `context-envelope/v0.1`
**Normative language:** **MUST**, **MUST NOT**, **SHOULD**, and **MAY** have their usual requirement meanings.

> This document defines a portable exchange contract for context supplied to an agent or other consumer. It does not describe a live implementation, database schema, deployment, or conformance result. The examples are synthetic.

## 1. Purpose and boundary

A Context Envelope carries a bounded, reviewable set of context items together with the information needed to interpret them safely. It is a custody and decision-input contract, not a memory-engine ranking algorithm and not a domain ontology. A Household deployment and a Business deployment can use the same envelope without copying household or business tables: deployment-specific entities remain opaque references or typed payloads inside `items`.

The envelope MUST preserve the distinction between:

- what was observed or supplied (`evidence`);
- what was derived (`claim` or `summary`);
- what was accepted, rejected, or unresolved (`review` and `resolution`);
- what is current, stale, superseded, or conflicted (`status`); and
- what the consumer is allowed to do (`capabilities`, `policies`, and `permitted_next_actions`).

An envelope does not prove that a claim is true in the outside world. Provenance proves the basis and custody of a statement, not its independent truth.

## 2. Envelope shape

The conceptual top-level members are:

| Member | Required | Meaning |
| --- | ---: | --- |
| `envelope_version` | yes | Exact profile identifier, currently `context-envelope/v0.1`. |
| `envelope_id` | yes | Stable identifier for this assembled envelope. |
| `issued_at` | yes | Time at which this envelope was assembled, with timezone. |
| `valid_until` | no | Consumer-use horizon; absence does not mean timeless validity. |
| `subject` | yes | Opaque deployment subject/scope reference; never a copied domain table. |
| `items` | yes | Zero or more context items, each with explicit state and provenance. |
| `capabilities` | yes | Capabilities asserted for this envelope/consumer, with scope and expiry. |
| `policies` | yes | Constraints governing use, disclosure, mutation, and escalation. |
| `permitted_next_actions` | yes | Explicitly allowlisted actions; an omitted action is not permitted by implication. |
| `assembly` | yes | Assembler identity, inputs, and completeness/limitation notes. |

Unknown, unavailable, or inapplicable values MUST NOT be silently omitted when their absence affects interpretation. Use the value-status form in §3.

## 3. Value status: known, unknown, unavailable, and conflict

A field whose value is not known MUST use an explicit marker rather than a guessed value. A minimal value-status object is:

```json
{"state":"unknown","reason":"not_observed"}
```

Allowed states are:

- `known`: the value is asserted with a provenance basis;
- `unknown`: the value may exist but is not known;
- `unavailable`: it may be known elsewhere but is not accessible in this envelope;
- `not_applicable`: the field does not apply to this item; and
- `conflict`: two or more preserved assertions cannot presently be treated as one value.

For `conflict`, the competing assertions MUST remain addressable and MUST include their own provenance. A consumer MUST NOT select a winner merely because one appears first. A conflict MAY include a prior resolution record, but that record does not erase the competing history.

Example:

```json
{
  "name": "preferred_delivery_day",
  "value": {
    "state": "conflict",
    "alternatives": [
      {"value": "monday", "item_id": "item-101"},
      {"value": "wednesday", "item_id": "item-119"}
    ],
    "reason": "contradictory_current_claims"
  }
}
```

## 4. Context item semantics

Each item MUST have an `item_id`, `kind`, `content`, `status`, `provenance`, and `review`. `kind` is a protocol-level category such as `evidence`, `claim`, `decision`, `preference`, `instruction`, `summary`, or `observation`; deployments MAY define additional kinds without changing the envelope contract.

`status` SHOULD include:

- `current`, `stale`, `superseded`, `reverted`, `historical`, or `conflicted`;
- `observed_at`, `recorded_at`, and, where meaningful, `effective_from`/`effective_until`;
- `supersedes` and `superseded_by` references when applicable; and
- a reason for non-current status.

A stale or superseded item MUST remain representable for audit and reconstruction. It MUST NOT be presented as current merely because it is retrievable.

## 5. Provenance and custody

`provenance` MUST identify the basis, source reference, and transformation history to the extent available. At minimum it SHOULD carry:

```json
{
  "basis": "human_direct|decision_record|imported_artifact|source_document|agent_summary|agent_inference|system_observed",
  "source_ref": "opaque-source-ref",
  "source_revision": "opaque-revision",
  "integrity": {"algorithm":"sha-256","digest":"synthetic-digest"},
  "attributed_to": "opaque-principal-or-agent",
  "derived_from": ["item-or-source-ref"],
  "recorded_by": "opaque-runtime-ref"
}
```

The producer MUST distinguish human-authored, human-confirmed, and agent-authored material. Agent-authored content MUST NOT be silently represented as human authority. If a provenance component is unknown or inaccessible, it MUST use an explicit value-status object.

## 6. Prior resolutions and review

An item MAY include `prior_resolutions`, an append-only list of decisions about that item or its predecessors. Each resolution SHOULD contain `resolution_id`, `at`, `actor`, `outcome` (`accepted`, `rejected`, `held`, `superseded`, `reopened`, or `withdrawn`), `basis_refs`, and `note`.

A later resolution supersedes the decision's effect where policy permits, but MUST NOT rewrite or delete prior resolutions. `held` means no winner was authorized. `reopened` means a prior outcome is no longer sufficient for the current question; it is not an automatic acceptance.

## 7. Capabilities, policies, and permitted next actions

Capabilities are scoped assertions, not ambient permissions. Each capability SHOULD state `capability_id`, `scope`, `holder`, `granted_by`, `granted_at`, and `expires_at` or an explicit no-expiry policy reference. Examples include `read_context`, `propose_correction`, `request_evidence`, `export_context`, and `review_conflict`.

Policies MUST state applicable constraints, including data handling, disclosure boundaries, retention/erasure rules, consequential-domain requirements, review requirements, and escalation behavior. A policy can deny an action even when a capability exists.

`permitted_next_actions` MUST be the intersection of capability, policy, item state, and envelope validity. Each action SHOULD include `action`, `target_refs`, `preconditions`, and `requires_review`. Consumers MUST treat any action not listed as disallowed or requiring separate authorization.

The assertions in a v0.1 envelope—including `capabilities`, `policies`, and `permitted_next_actions`—do not themselves grant authority. They describe decision inputs and an explicit allowlist at envelope assembly time; they MUST NOT be treated as a delegation, credential, or execution approval. Before executing an action, the consumer MUST re-authorize it against the current policy, current item/envelope state, and any applicable external authority. If that re-authorization is unavailable, stale, ambiguous, or denied, the action MUST NOT execute.

## 8. Synthetic Household example

```json
{
  "envelope_version":"context-envelope/v0.1",
  "envelope_id":"env-household-synthetic-001",
  "issued_at":"2030-04-02T09:00:00Z",
  "subject":{"ref":"household:example-home","state":"known"},
  "items":[
    {
      "item_id":"item-101","kind":"preference",
      "content":{"delivery_day":"monday"},
      "status":{"state":"conflicted","observed_at":"2030-03-01T10:00:00Z"},
      "provenance":{"basis":"human_direct","source_ref":"example-chat-01","recorded_by":"example-runtime"},
      "review":{"state":"held"},
      "prior_resolutions":[{"resolution_id":"res-1","outcome":"held","actor":"example-reviewer","at":"2030-03-02T12:00:00Z"}]
    },
    {
      "item_id":"item-119","kind":"preference",
      "content":{"delivery_day":"wednesday"},
      "status":{"state":"current","observed_at":"2030-03-10T10:00:00Z"},
      "provenance":{"basis":"agent_summary","source_ref":"example-chat-02","derived_from":["example-chat-02"],"recorded_by":"example-runtime"},
      "review":{"state":"unresolved"}
    }
  ],
  "capabilities":[{"capability_id":"request_evidence","scope":"subject","expires_at":"2030-04-09T00:00:00Z"}],
  "policies":[{"policy_id":"household-review-before-change","rule":"conflicts require human review"}],
  "permitted_next_actions":[{"action":"request_evidence","target_refs":["item-101","item-119"],"requires_review":false}],
  "assembly":{"assembled_by":"example-runtime","completeness":{"state":"known"},"limitations":[]}
}
```

No household member, chore, purchase, or calendar table is prescribed by this example.

## 9. Synthetic Business example

```json
{
  "envelope_version":"context-envelope/v0.1",
  "envelope_id":"env-business-synthetic-001",
  "issued_at":"2030-04-02T09:00:00Z",
  "valid_until":"2030-04-02T17:00:00Z",
  "subject":{"ref":"business:example-team","state":"known"},
  "items":[
    {
      "item_id":"item-budget-042","kind":"claim",
      "content":{"proposal_ref":"ticket:budget-042","amount":{"currency":"USD","value":12500}},
      "status":{"state":"current","observed_at":"2030-04-02T08:30:00Z"},
      "provenance":{"basis":"agent_inference","source_ref":"ticket:budget-042","derived_from":["decision-record:budget-q2"],"recorded_by":"example-runtime"},
      "review":{"state":"held"},
      "prior_resolutions":[{"resolution_id":"res-budget-1","outcome":"held","actor":"example-reviewer","at":"2030-04-02T08:45:00Z","basis_refs":["ticket:budget-042"]}]
    }
  ],
  "capabilities":[
    {"capability_id":"request_evidence","scope":"subject","holder":"example-reviewer","granted_by":"example-policy-authority","expires_at":"2030-04-02T17:00:00Z"},
    {"capability_id":"propose_correction","scope":"item:item-budget-042","holder":"example-agent","granted_by":"example-policy-authority","expires_at":"2030-04-02T17:00:00Z"}
  ],
  "policies":[{"policy_id":"business-payment-review","rule":"budget claims require human review; this envelope does not authorize payment approval"}],
  "permitted_next_actions":[
    {"action":"request_evidence","target_refs":["item-budget-042"],"requires_review":false},
    {"action":"propose_correction","target_refs":["item-budget-042"],"requires_review":true}
  ],
  "assembly":{"assembled_by":"example-runtime","completeness":{"state":"known"},"limitations":["payment approval authority is absent"]}
}
```

This synthetic envelope deliberately has no `approve_payment` action. No business member, ledger, ticket, or payment table is prescribed by the example.

## 10. Compatibility and validation expectations

A v0.1 producer MUST emit the version identifier and MUST preserve unknown extension members or report them as unsupported; it MUST NOT reinterpret an unknown field as permission. A consumer MUST fail closed for malformed required structure, expired envelopes where expiry is enforced, missing provenance on claims that policy marks consequential, and actions absent from `permitted_next_actions`.

This specification is intentionally not a claim that any repository, runtime, Household deployment, or Business deployment implements or conforms to it. Conformance, if later defined, requires a separately published probe suite covering unknowns, conflicts, provenance attribution, stale-state suppression, prior-resolution preservation, capability expiry, policy denial, and action allowlisting.

### 10.1 Deferred conformance and security profile

v0.1 makes bounded semantic claims only. Canonical serialization, signature/MAC formats and verification, key lifecycle, action replay and time-of-check/time-of-use (TOCTOU) protections, deterministic validation, and immutable provenance binding are deferred to a separately versioned conformance/security profile. This document therefore does not claim cryptographic authenticity, replay resistance, race-free execution, byte-level interoperability, or deterministic acceptance across implementations. The profile MUST define those guarantees before they are relied upon.

That deferral does not weaken the v0.1 semantic boundary: action absence remains fail-closed, and `unknown`, `unavailable`, `not_applicable`, and `conflict` remain explicit states with the handling requirements in this document. Unknown extensions MUST NOT be interpreted as authority, and conflicts MUST NOT be resolved by incidental ordering.
