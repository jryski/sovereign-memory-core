# ADR-0008: Least-privilege access model

## Status

Proposed.

This note is a design. It is not an implemented control. It is not a grant, a role, or a function that exists. Adding this file does not issue, narrow, or revoke a credential.

An independent peer review of this design has not happened. Implementation waits on that later review. This note does not record a review outcome, and it does not authorize implementation.

## Context

The security boundary for assistants and browser-facing interfaces is the connector, API, or database credential those surfaces actually hold. Schema separation and in-band checks do not shrink the blast radius of a credential that can already read and write everything it can reach.

Issue #8 asks for a reusable access model in which a broad database credential is not the default for every surface. Primary Users may still run a small trusted deployment with few credentials. That operational choice must not become the design default for the browser, for each assistant, or for every later interface.

Any later narrowing has to keep four custody properties intact: provenance, the review flow, agent attribution, and document integrity. A design that drops those properties in exchange for narrower credentials is not an acceptable access model.

Refs #8.

## Decision

Adopt a least-privilege access model as the design target for assistants and browser-facing interfaces.

Each surface below has its own capability inventory. Read and write are separate. Propose, promote, bless, import, audit read, and administrative override are separate capabilities. The reusable default is a narrow role whose only reach is the function surface for its inventory. A broad database credential is an operator break-glass tool, not the credential issued to every surface.

The names below are design labels for this note. They are not database roles, grants, or functions, and this note does not create them.

### Capability inventory by surface

| Surface | Who may hold it | Read capabilities | Write capabilities | Excluded |
|---|---|---|---|---|
| Browser read | A browser session for Primary Users | Orientation, viewer-scoped rows, review status, and the document-integrity verification result | None | Propose, promote, bless, import, audit mutation, administrative override, and any privileged credential |
| Assistant read | One assistant, acting as itself | Boot orientation, viewer-scoped rows, review status, and the document-integrity verification result | None | Every write capability, including propose |
| Assistant propose | One assistant, acting as itself | The read set it needs in order to draft | Propose a memory or document, stage a candidate, and address a channel note as itself | Promote, reject, bless, hard-delete, administrative override, and writing as another agent |
| Review and promotion | Primary Users | Candidates, their provenance, and their agent attribution | Promote, hold, or reject a candidate | Rewriting provenance, replacing agent attribution, blessing a document, and administrative override |
| Import and staging | A dedicated import path | Validation results for a package it is staging | Land preserved source bytes and candidate rows in a staged state | Promotion, blessing, and silent replacement of current rows |
| Document integrity | Primary Users | Current content hash and verification result | Bless an approved operating document, or record a human decision on mismatch | Assistant or browser blessing, and administrative override |
| Audit read | Primary Users, or a dedicated auditor | Audit keys: actor, action, object, and time. Not a second copy of private payloads | None | Mutation of the audit trail |
| Administrative override | Primary Users, break-glass only | The records needed for that incident | A scoped, audited destructive override | Everyday assistant use, browser use, and use as the default credential |

A broad database credential appears in no row as a default. It is outside the inventory on purpose.

### Read and write separation

A read capability does not include a write capability. A propose capability does not include promotion. A promotion capability does not include document blessing. A blessing capability does not include administrative override. Audit read does not include audit mutation.

Primary Users may hold more than one of these capabilities in a simple deployment. Holding them together is an assignment choice. It does not merge the capabilities into one permission.

### Narrow role and function surfaces

The reusable default is one narrow role per surface. That role would be able to call only the function surface designed for its inventory row. It would not receive direct table ownership, and it would not receive a broad database credential. This note does not create that role or that function surface.

In the design, assistant and browser callers reach custody actions through that function surface. Boot, propose, stage, promote, bless, and verify are separate capabilities, each permitted only where the inventory lists it. Callers do not receive a general query-and-mutate credential as a substitute for those capabilities.

A broad database credential may exist for operator recovery. It is not placed in assistant connectors, import jobs, or browser clients, and it is not the credential the design tells a new surface to use.

### Browser read-only boundary

The browser is the read surface in the inventory. Its client code, static bundle, and browser storage hold no privileged credential and no broad database credential.

A browser session may request the read projection for the viewer it represents. It cannot propose, promote, bless, import, or override. If a later interface offers promotion or blessing to Primary Users, that action uses the review surface or the document-integrity surface. It does not reuse a privileged key shipped to the browser.

### Simple start, stronger boundaries later

The same inventory supports a small deployment now and a tighter split later.

1. **Simple.** Primary Users may hold several narrow capabilities, and more than one trusted assistant may share one propose credential. The browser credential is still read-only. Assistants can still only propose. Review and document blessing stay with Primary Users.
2. **Split credentials.** Each inventory row gets its own credential. Capability names stay the same.
3. **Stronger boundaries.** Each assistant credential binds to one agent identity. Reviewer actions bind to Primary Users. Runtime callers stay on their function surfaces, with no direct table ownership as the default. Row visibility remains a second check underneath the credential boundary.

None of these steps drops the following:

- **Provenance.** Source basis, required citation, content hashes, and preserved source bytes stay attached to the record. A narrower credential does not make an unsourced write acceptable.
- **Review flow.** Assistant and import output stays proposed until the review surface promotes, holds, or rejects it. Drafting remains allowed. Promotion stays an explicit human action.
- **Agent attribution.** A write is stamped with the agent that holds the credential used for that write. The caller cannot substitute another agent. An unregistered agent cannot write. Promotion records the reviewer action and leaves the original agent stamp in place.
- **Document integrity.** The operating contract stays hash-blessed by Primary Users through the document-integrity surface. Assistants and the browser may read the verification result. They cannot bless the document, and a drafted replacement does not change the blessed hash.

### Synthetic examples

These examples are fictional and deployment-neutral. The identifiers are design labels. They are not people, hosts, credentials, or deployed roles.

**Browser.** Primary Users open a session labeled `example-browser-session`. The session reads the orientation projection for principal `example-reader`. The page holds no database password and no broad credential. The session cannot insert a row.

**Propose.** Agent `example-assistant-a` serves `example-reader`. It proposes the sentence "Example topic: the workshop meets on the first Monday." The candidate stays proposed. Its agent stamp is `example-assistant-a`. The propose credential cannot mark the candidate current.

**Review.** A Primary User promotes that candidate through the review surface. The promotion records the review action. The agent stamp remains `example-assistant-a`. Provenance on the candidate is left as it was written.

**Integrity.** `example-assistant-a` drafts a replacement operating contract. The draft does not change the blessed hash. A Primary User blesses the approved text through the document-integrity surface. The browser can show match or mismatch. The browser and the assistant do not hold the blessing capability.

**Simple, then split.** At the simple step, one Primary User holds both review and document integrity, and `example-assistant-a` and `example-assistant-b` share one propose credential. The browser still has only the read credential. At the split step, the two assistants receive separate propose credentials. Provenance, review, agent attribution, and document integrity stay as they were. Only the credential split changes.

### Criteria for a later independent peer review

A later independent peer review would use every criterion below before any implementation. That review has not happened. This note is not that review.

1. Every surface that would receive a credential appears in the inventory, and each capability it would receive is allow-listed.
2. Read is a separate permission from write. Propose, promote, bless, import, audit read, and administrative override are separate capabilities.
3. The browser design keeps privileged credentials out of client code, static bundles, and browser storage.
4. A broad database credential is not the default for the browser, assistant, import, or review surfaces.
5. Any later narrow role would be limited to its function surface and would not receive direct table ownership as the default.
6. The simple path and the stronger path both preserve provenance, review-before-promotion, agent attribution, and document integrity.
7. Examples in any implementation change stay synthetic, and they contain no personal name, private identifier, host, or deployment name.
8. The reviewer is independent of the author of the implementation change.
9. The review outcome is recorded before any grant, role, or function is added.
10. Reviewers treat this note as a design input. They do not treat it as a grant, a role, a function, or evidence that review already occurred.

## Consequences

- A new surface can be described by the capability it needs. In this design, a broad database credential is not the default for that surface.
- Primary Users can start with few credentials. Adding a stronger boundary later is a credential split over the same inventory.
- Provenance, review, agent attribution, and document integrity stay in force on the simple path and on every later split.
- Role creation, grants, function changes, client wiring, and live credential changes are out of scope until the peer review above has actually been completed and recorded.
- This note adds no database object. After it is merged, the access model will still be a design, not a grant, a role, or a function.

## Related

- Refs #8
- [ADR-0002](0002-evidence-hashes-prove-custody-not-truth.md)
- [ADR-0003](0003-models-and-miners-are-untrusted-emitters.md)
- [ADR-0004](0004-review-before-promotion.md)
- [ADR-0006](0006-protected-durable-writes-default-to-proposed.md)
- [docs/02-security-model.md](../02-security-model.md)
- [docs/06-patterns.md](../06-patterns.md)
