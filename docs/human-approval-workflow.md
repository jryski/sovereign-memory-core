# Human approval workflow

This is the reference contract for authenticated human approval of an authority-bearing mutation. It separates a staged proposal from the decision that executes it. The first executable operation is memory promotion. The request envelope can register later operations, and a decision on an operation without an executor fails closed.

This slice is schema and functions only. It does not add a hosted review UI, does not call a live Supabase project, and does not change the v0.3-alpha conformance labels.

## Trust boundary

An agent login may stage a bounded promotion. Staging records the target, the expected version, the proposed transition, the proposer, the reason, evidence references, and an expiry. It does not change the memory.

Approval and rejection do not take an acting principal. The authorizer is the current database login, and only when that login has an open row in `human_approval.sessions`. Opening a session reads `human_approval.trust_anchors` for that login and stamps the principal and assurance from the anchor. Placeholder values supplied inside the insert are overwritten before the row is stored. A caller-supplied principal, including a session setting, is not an authority substitute.

The reference anchor maps the login `human_approval_reviewer` to principal `example-user` with assurance `deployment-authenticated-human`. That anchor is the deployment-specific authenticated surface for Primary Users. A deployment replaces the anchor with its own human login. This repository does not choose an enterprise identity provider.

`human_approval_agent` and `service_role` may stage a promotion and list unexpired pending requests. They cannot open a session, approve, or reject. Direct table writes are revoked. Receipts are append-only, and a second decision on a resolved request fails closed.

Legacy `public.promote_memory` is unchanged. Where a deployment still grants it, that RPC is not this receipt and does not record human assurance.

## Decision receipt

Approval updates the proposed memory and inserts one receipt in the same transaction. The receipt binds:

- authorizer principal, assurance, and authenticator role
- proposer login and untrusted proposer label
- proposal reason and decision reason
- evidence
- prior state and resulting state, including the version
- decision nonce and timestamp

The request stores the receipt id and the same timestamp. Rolling the transaction back removes the promotion, the receipt, and the status-change audit row together.

Rejection writes the same kind of receipt with decision `rejected`. Prior state and resulting state match, the memory stays proposed, and the rejector is the session authorizer.

These conditions fail closed and leave the target unchanged:

- the login is not a trust anchor, or this backend has no open unexpired session
- the request is missing, expired, or already resolved
- the presented version does not match the staged version
- the memory version or status changed after staging
- the decision nonce does not match, or it was already consumed by another receipt
- the operation is not the implemented promotion
- two decisions race; the loser sees the request already resolved

Expired requests stay pending and leave the review list. They cannot be approved or rejected after expiry.

## Disposable validation

Apply `sql/01_core.sql`, then `sql/13_human_approval_requests.sql`, on a local PostgreSQL 15+ database. The validation fixture rolls back. The runner also races two approval sessions against one committed request.

```bash
DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/postgres" \
  bash scripts/validate_human_approval.sh
```

The runner creates and drops a disposable database on that server. It does not use a hosted project. `sql/13_human_approval_requests.sql` is outside the v0.3-alpha migration set, so this contract does not by itself move the published schema fingerprint.
