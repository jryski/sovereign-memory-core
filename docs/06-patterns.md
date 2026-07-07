# 06 · The transferable patterns

If you take nothing else, take these. They are what make the system trustworthy, and
they transfer to any multi-agent data system (a business knowledge base, a team wiki,
a customer deployment) even when the schema does not.

## 1. Verifiable source of truth: facts need sources, enforced by the store
A shared memory that multiple AI models write to is only as trustworthy as its weakest
writer on its worst day. Prompt-level discipline ("always cite sources") decays; a CHECK
constraint does not. Provenance basis is a closed enum (human_direct, decision_record,
imported_artifact, source_document; agent_summary/agent_inference rejected), citation is
mandatory unless a human said it directly, and honest uncertainty is a first-class state
(unverified flag + capped confidence) rather than something models hide. Gate any
multi-user or business deployment on this being enforced, because with multiple writers,
unsourced "facts" compound.

## 2. Preserve-then-normalize
Imports land verbatim with a content hash BEFORE any normalization, and normalized rows
FK back to their preserved source. Cost: pennies of storage. Benefit: every derived
claim is re-checkable against the original forever, and migration/normalization bugs are
recoverable instead of destructive. This is THE one-way door in data migration design:
you can always re-derive from preserved sources; you can never un-lossy a normalization.

## 3. Temporal truth
observed_at / recorded_at / effective_from / effective_to + status
(proposed/current/superseded/retracted/entered_in_error) + predecessor chains.
Corrections create history; nothing is overwritten. When a model (or a person) is wrong,
the wrongness and its correction are both queryable. Trust is built from visible
correction, not from pretended infallibility.

## 4. Principal-before-org (capability access)
Access is an explicit row: who, what domain, what capability, over which subject, valid
when, granted by whom, why. Never an implication of a role name or group membership.
When you later add people (family member, cofounder, pilot customer), onboarding is
inserting rows, and offboarding is setting valid_to, with the whole history auditable.

## 5. The connector is the boundary
Schema separation is API hygiene; the credential is the actual security boundary.
Design for the credential you really have (service-role shared by trusted agents),
harden by narrowing roles when trust tiers appear, and never let a diagram of schemas
substitute for asking "who holds which key."

## 6. Migrations outside the vendor + rehearsed exit
Schema history in a git repo you control, weekly dumps to storage you control, and a
RESTORE REHEARSAL into vanilla Postgres that proves the exit path. Sovereignty is not a
philosophy statement; it is a passed test with a date on it.

## 7. Attention is a mechanism, not a prompt
The hot index with a second-touch gate and recency-decayed scoring gives every fresh
session cheap, relevant orientation. Trying to achieve the same with "important things
to remember" prompt text fails at both ends: it bloats, and it never forgets.

## 8. In-band integrity with warn-and-confirm
The agents' operating contract lives in the store they operate on, hash-blessed by the
human. Tamper-EVIDENT beats tamper-PROOF: on mismatch, warn and ask, never auto-refuse.
A security mechanism that can lock the owner out of their own system is a worse threat
than the one it guards against.

## 9. Diff, don't trust
Any claim from any model channel, any "done," any reported count gets verified against
live ground truth before being acted on or repeated. In practice: acceptance tests in
separate statements, checksums on every transfer, asserts at the end of migrations, and
assistants instructed to check the database rather than their own conversational memory.
Also applies to the operator's own work: the checksums in this repo's process exist
because the author corrupted his own transfers twice and caught it both times only
because verification was mandatory.

## 10. No feature parity across diverged use cases
If you run this pattern in two places (household and business), the shared unit is
PATTERNS AND CONTRACTS, not schema mirroring. Parity between different use cases is an
infinite treadmill that makes both systems worse. Let them diverge; port the ideas.

## 11. Finite plans with DONE conditions
Every build phase in docs/04 has an explicit acceptance test, and the guide ends with
"stop building." Infrastructure projects for your own life fail by never ending. Define
DONE, hit it, then go live in the system instead of on it.
