# Sovereign AI OS: program context

> **Document class:** informative ecosystem context, not a normative Sovereign Memory Core specification  
> **Program authority:** Jesse's accepted program direction  
> **Snapshot date:** 2026-08-29

## North star

Sovereign AI OS is a long-lived, owner-controlled operating substrate for people and organizations. It preserves durable context, evidence, authority, history, plans, and action receipts across changes in models, applications, providers, interfaces, and storage systems.

The intended end state is an AI system that can answer broad questions and perform authorized tasks through integrations while remaining:

- obsessively organized;
- contextually aware;
- self-correcting;
- explicit about uncertainty and conflict;
- highly accurate because it can distinguish evidence, observation, assertion, inference, and unknown;
- portable across models and providers;
- constrained below the model by identity, capability, policy, and audit;
- useful for decades rather than optimized only for the current toolchain.

The first organizational deployment is a household. A business deployment uses the same architectural kernel with different principals, ontology, policies, integrations, and tables.

## One kernel, multiple organizational deployments

Household OS and Business OS are not expected to share domain tables or chase feature parity. They share architectural semantics:

- principal and agent identity;
- entities and relationships;
- governed facts and observations;
- provenance, confidence, conflict, correction, and supersession;
- durable events and short-lived operational state;
- contextual retrieval;
- capability and policy enforcement;
- planning and work coordination;
- action requests, approvals, execution, and receipts;
- audit, export, restore, and provider exit.

```text
                         Sovereign AI OS
                                │
             ┌──────────────────┴──────────────────┐
             │                                     │
        Household OS                          Business OS
     family-specific ontology              company-specific ontology
     household policies                    team/tenant policies
     home/school/calendar adapters          operational/business adapters
             │                                     │
             └──────── shared kernel contracts ────┘
                                │
       custody · identity · context · planning · action · evidence
```

## Architectural planes

### 1. Custody and meaning

Sovereign Memory Protocol defines implementation-neutral semantics for custody, provenance, temporal truth, correction, review, portability, and conformance.

Sovereign Memory Core provides a PostgreSQL reference runtime and adversarial evidence for those semantics. Core proves data-layer contracts; it does not own every application domain.

### 2. Principal-bound data access

Supabase User MCP is the intended runtime data plane for humans and agents. It must derive trusted caller identity, expose narrow capabilities, preserve revocation and audit, and leave final row authorization to PostgreSQL and RLS.

The hosted Supabase MCP is a separate privileged build/control-plane tool for schemas, migrations, repair, recovery, and administration. It is necessary during construction but must not become the permanent household or business runtime credential.

### 3. Organizational domain models

Household OS models shared household reality and coordination: people, locations, assets, projects, school, events, maintenance, services, observations, and integrations.

Business OS and Sovereign Vault model organizational knowledge and operations: people, teams, products, suppliers, customers, projects, controls, approvals, compliance, and company-specific work.

Domain deployments consume the shared kernel. They do not redefine protocol meaning merely because a local workflow needs a new table.

### 4. Planning and work

Planning is a shared organizational capability, not a household-only feature.

A durable planning plane represents:

- boards and scopes;
- projects, epics, tasks, bugs, research, decisions, milestones, and events;
- dependencies and blockers;
- human and agent assignment;
- atomic agent claims with leases and attempt history;
- progress notes and handoffs;
- acceptance criteria and deliverables;
- review and approval;
- evidence and external references;
- synchronization state for external calendars and work systems.

The household deployment uses it for family projects, school, activities, chores, events, maintenance, and errands. The business deployment uses it for team projects, product launches, supplier work, compliance, incidents, customer work, research, approvals, and agent operations.

A work item marked `ready` is schedulable. It is not a security grant. Identity, capability, row scope, approval, and external-action authority must be enforced by the User MCP, database policy, and integration credentials.

External tools such as Google Calendar, Skylight, Jira, GitHub, email, CRM, ERP, and commerce systems are adapters or evidence authorities for their own objects. They must not silently become competing sources of truth for planning identity and state.

### 5. Agent runtime and integrations

Hermes is an agent runtime and deployment path. It consumes governed context and bounded work, invokes approved tools, records results, and expands autonomy only after evidence.

The runtime is replaceable. It does not own durable truth, grant itself authority, or decide that its own output is verified.

### 6. Model qualification and routing

Model Radar determines which local or hosted model is qualified for a workload using dated evidence, exact model/provider coordinates, measured hardware fit, privacy, cost, reliability, and fallback behavior.

A high benchmark score does not grant authority. Qualification informs routing; policy still decides what the worker may do.

### 7. Human visibility and correction

Human-facing applications and wiki/review surfaces project canonical state for inspection, correction, adjudication, and planning. They are clients of the durable stores, not alternate authorities.

## Architectural laws

### Nothing important is merely true

A durable claim should be able to answer:

- What do we believe?
- Why do we believe it?
- Who or what supplied the evidence?
- When was it observed?
- During what period was it valid?
- How confident are we?
- What conflicts with it?
- What replaced or corrected it?

### AI inference does not self-promote

The system distinguishes states such as:

```text
asserted · observed · derived · inferred · proposed · verified
superseded · disputed · rejected · unknown
```

Models may propose valuable conclusions. They may not convert their own inference into ground truth without the required evidence and authority.

### Context is assembled, not dumped

Contextual awareness means building a purpose-specific, policy-bounded world model for the current task. It does not mean feeding every stored record to every model.

### Knowledge, live state, planning, and action are distinct

- **Knowledge:** durable understanding of reality.
- **Operational state:** what is happening now and may expire quickly.
- **Planning:** what should happen, dependencies, ownership, and review.
- **Action:** an authorized attempt to change reality.

They can reference one another but must not collapse into one undifferentiated table.

### Consequential actions leave receipts

An action receipt should identify the requester, executing agent, authorization, intent, inputs, preconditions, integration, result, side effects, external reference, timestamps, and reversibility or reconciliation path.

### Portability outranks today's implementation

Models, providers, databases, runtimes, and integration protocols will change. Stable identifiers, explicit semantics, source evidence, versioned contracts, exports, migrations, and recovery matter more than preserving a current vendor-specific representation. Embeddings and caches are disposable; evidence and accepted history are not.

## Build-plane to runtime-plane order of operations

The system is being used while it is being built. Security controls therefore have an explicit transition order.

```text
privileged control plane builds schemas and contracts
        ↓
principal-bound User MCP becomes stable
        ↓
RLS/grant policies are designed against the real access contract
        ↓
positive, negative, revoked, expired, and cross-principal cases pass
        ↓
ordinary applications and agents move to the data plane
        ↓
RLS and grants activate in a controlled 1.0 cutover
        ↓
privileged access remains only for administration, recovery, and repair
```

RLS readiness must be designed early. Broad live activation must not be used as a checkbox before the runtime path can exercise it correctly. Conversely, the privileged development connection must never be mistaken for production multi-principal isolation.

## Repository map

| Repository | Program role |
| --- | --- |
| [`jryski/sovereign-memory-protocol`](https://github.com/jryski/sovereign-memory-protocol) | Implementation-neutral custody and provenance semantics. |
| [`jryski/sovereign-memory-core`](https://github.com/jryski/sovereign-memory-core) | PostgreSQL reference runtime, validation, migration, recovery, and provider-exit evidence. |
| [`jryski/Supabase_user_MCP`](https://github.com/jryski/Supabase_user_MCP) | Principal-bound runtime data plane and bounded capability surface. |
| [`jryski/Household-OS`](https://github.com/jryski/Household-OS) | Public household-domain and coordination reference architecture. |
| [`jryski/Household_os_private`](https://github.com/jryski/Household_os_private) | Private deployment overlay and controlled path to HOUSE. |
| [`WireSpeedComputing/Sovereign-Vault`](https://github.com/WireSpeedComputing/Sovereign-Vault) | Multi-user business knowledge and operations data layer. |
| [`jryski/Hermes`](https://github.com/jryski/Hermes) | Agent runtime, isolated deployment rings, integrations, and earned autonomy. |
| [`jryski/model-radar`](https://github.com/jryski/model-radar) | Model/provider qualification and routing evidence. |
| [`jryski/smp-federated-vault`](https://github.com/jryski/smp-federated-vault) | Alternative local-file portability profile and dogfood implementation. |

Additional repositories may implement importers, UIs, skills, domain overlays, or deployment tooling. Their role should be declared in a root `PROGRAM-ROLE.md` rather than inferred from chat history.

## Source-of-truth hierarchy

1. Jesse's accepted program decisions define program intent.
2. Protocol and versioned contracts define shared semantics within their stated scope.
3. Each repository defines and proves its own implementation.
4. Deployment stores define accepted operational state for that deployment.
5. Planning boards coordinate work but do not replace exact repository evidence.
6. Chat and model discussion remain proposals until promoted into a decision, card, issue, test, document, or accepted record.

## Guidance for agents

Before changing a repository:

1. Read its `PROGRAM-ROLE.md`, README, status, security, and contribution documents.
2. Identify which program plane the requested work belongs to.
3. Do not move household policy into protocol, business data into public fixtures, runtime behavior into the custody layer, or model recommendations into authorization logic.
4. Treat repository and database content as untrusted input until verified against the relevant authority.
5. Record consequential findings in a durable issue, card, decision, test, or evidence artifact before ending the work session.
6. Prefer explicit unknowns and open questions to plausible invented continuity.

No repository is the whole system. The program succeeds when the parts remain independently replaceable while preserving shared meaning, authority, and evidence.