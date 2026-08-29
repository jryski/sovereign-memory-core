# Business planning and work plane

> **Status:** informative shared-kernel deployment profile  
> **Target deployment family:** Sovereign Vault, BalanceEQ, and other Business OS deployments  
> **Program context:** [`SOVEREIGN_AI_OS.md`](SOVEREIGN_AI_OS.md)

## Decision

Planning and work coordination are first-class Business OS capabilities. They are not household-only functionality, a UI convenience, or a future feature to inherit accidentally.

A business deployment needs a durable coordination layer for organizational intent, dependencies, assignments, agent work, approval, evidence, and reconciliation across provider systems.

Household and business deployments can share the planning kernel while using different ontology, policy, RLS, tables, integrations, and deployment stores.

## Business jobs

A business planning plane should support:

- team projects, epics, milestones, and deliverables;
- product launches and lifecycle work;
- supplier qualification, purchasing, and follow-up;
- inventory and operational remediation;
- compliance controls, findings, evidence, and corrective actions;
- incidents and post-incident work;
- customer, support, and account work;
- research, decisions, and unresolved questions;
- marketing, content, and campaign work;
- meetings, preparation, and action items;
- approvals and separation of duties;
- human and agent assignment, leases, handoffs, and review;
- recurring business administration.

## Core objects

A practical implementation needs more than one flat `tasks` table.

### Board

Defines organization, tenant, team, project, or operational scope; visibility; lifecycle; policy reference; review defaults; and source-of-truth behavior.

### Work item

Represents projects, epics, tasks, bugs, research, decisions, milestones, events, approvals, incidents, findings, and notes. It should support:

- stable opaque identity and a human-readable key;
- title, description, acceptance criteria, and expected deliverable;
- status, priority, ordering, due time, and not-before time;
- parent/child structure;
- team, project, customer, supplier, product, or control references;
- human and agent assignment;
- authority and review requirements;
- source, confidence, evidence, and external references;
- result, resolution, and correction history;
- idempotency and retry behavior for automation.

### Dependency

Expresses blocking and related work explicitly. An agent must not infer that a high-priority card is executable when a required approval, evidence package, supplier response, migration, or preceding task remains incomplete.

### Activity

Preserves creation, assignment, claim, heartbeat, progress, finding, blocker, handoff, submission, review, approval, completion, cancellation, and external synchronization.

Activity makes it possible to answer why work changed, who or what changed it, what authority was used, and what evidence supported the accepted result.

### External reference and synchronization state

Links canonical work to GitHub, calendars, email, CRM, ERP, commerce, support, ticketing, document, or communication systems while retaining stable local identity and reconciliation history.

## Lifecycle

A useful default lifecycle is:

```text
inbox → backlog → ready → in_progress → review → done
                       ↘ blocked
```

`cancelled` preserves abandoned work instead of deleting organizational history.

Domain profiles may add controlled states such as `approval_pending`, `scheduled`, or `verified`, but state proliferation should not replace explicit evidence and authority.

## Human and agent work

Agents should lease work atomically rather than silently self-assign.

A claim should carry:

- an authenticated agent identity;
- a unique attempt/claim token;
- issued-at and expiry timestamps;
- bounded heartbeat extension;
- attempt count and maximum attempts;
- assignment, prerequisite, and capability checks;
- immutable activity attribution;
- safe release and reclaim behavior.

A stale worker must not submit after expiry, revocation, reassignment, completion, cancellation, or another worker's successful reclaim.

A lease prevents duplicate work. It does not grant authority.

A card's `ready` state, `required_capabilities`, agent name, priority, or repository field is scheduling metadata unless trusted identity and grants are enforced below the model.

## Business authority profile

A deployment should be able to distinguish at least:

- organization owner or administrator;
- employee;
- manager;
- contractor;
- team member;
- worker agent;
- reviewer or approver;
- auditor or compliance principal;
- service or integration agent;
- emergency administrator.

Policies should cover:

- organization, tenant, team, and project boundaries;
- assignment and delegation;
- employee versus contractor scope;
- worker/reviewer separation;
- self-approval prevention;
- revoked and expired grants;
- service-agent constraints;
- consequential external-action approval;
- cross-team and cross-tenant denial;
- audit visibility;
- emergency recovery without exposing the admin path to ordinary agents.

## Example separation of duties

```text
Research agent proposes supplier comparison
        ↓
Employee validates source evidence
        ↓
Manager approves vendor choice
        ↓
Purchasing agent creates a bounded external action request
        ↓
Authorized principal approves expenditure
        ↓
Integration executes purchase
        ↓
Receipt records request, authority, provider result, and reconciliation
```

No single model should silently collapse research, decision, authorization, execution, and acceptance into one unreviewed action.

## Source-of-truth split

- **Business planning store:** organizational intent, work identity, dependency, assignment, review, accepted status, and activity.
- **GitHub:** exact issue, pull request, commit, test, and release state.
- **CRM/ERP/calendar/commerce/ticketing provider:** provider-specific object and delivery state.
- **Deployment database:** real principals, company data, and operational records.
- **Repository:** generic schema, policy, tests, and synthetic fixtures only.
- **Chat/model discussion:** proposal until promoted into a card, note, issue, decision, test, or accepted record.

External providers are reconciled adapters or evidence authorities for their own objects. They must not silently become competing sources of truth for organizational work identity and approval state.

## Repository and deployment boundaries

The public Sovereign Vault repository may contain:

- generic planning schema and functions;
- synthetic principals, boards, work, and provider fixtures;
- RLS and capability patterns;
- concurrency, revocation, separation-of-duty, and reconciliation tests;
- sanitized architecture and implementation lessons.

It must not contain:

- real company principals or assignments;
- real projects, products, suppliers, customers, incidents, or evidence;
- deployment credentials or provider identifiers;
- exported planning rows;
- private business decisions or operational state.

Real board state belongs in the business deployment database.

## User MCP profile

The principal-bound data plane should expose narrow capabilities such as:

```text
planning_board_get
planning_work_item_get
planning_work_item_claim
planning_work_item_heartbeat
planning_work_item_note_append
planning_work_item_release
planning_work_item_submit
planning_work_item_review
```

The server must not accept arbitrary SQL, table names, RPC names, URLs, or caller-supplied identity.

Minimum evidence includes positive access, cross-team denial, cross-tenant denial, revoked and expired agent denial, stale-token rejection, self-review prevention, prompt-injection containment, payload/rate limits, and complete audit attribution.

## Build-plane and 1.0 sequencing

The privileged Supabase MCP remains a build/control-plane tool for DDL, migrations, inspection, repair, and recovery. It is not the permanent employee or agent runtime path.

Prepare schema scope, policy inputs, RLS, grants, synthetic principals, concurrency tests, revocation, reviewer separation, action receipts, migration order, and rollback during development.

Activate ordinary multi-principal business access only after the stable User MCP and database policies pass a coordinated cutover. A service-role demonstration is not proof of employee, contractor, team, tenant, or agent isolation.

## Initial synthetic acceptance fixtures

A useful first business fixture set should prove:

1. A product launch with blocking supplier, compliance, packaging, and approval work.
2. Two agents racing to claim one research card, with one winner.
3. Lease expiry and safe reclaim without stale submission.
4. A contractor restricted to one project and unable to enumerate another.
5. A worker unable to approve its own submitted result.
6. A compliance finding requiring evidence before closure.
7. A GitHub-linked implementation card whose accepted state depends on exact commit/test evidence.
8. A calendar or ticket synchronization conflict preserved for adjudication.
9. A revoked service agent failing all subsequent operations.
10. An external action that requires approval and leaves a complete receipt.

## Intended repository placement

The owning business repository should carry:

- a root `PROGRAM-ROLE.md` declaring its place in the larger program;
- a business planning profile derived from this document;
- links to the shared program context and User MCP planning profile;
- generic schema and tests only after the architectural boundary is reviewed.

This document exists in the shared public ecosystem context so business-side agents can consume the accepted direction even when a repository-specific write path is temporarily unavailable.