# Sovereign Memory Core project story timeline

Status: draft narrative scaffolding for documentation, blog posts, and wiki pages.
Audience: public readers, future contributors, and AI/human collaborators.
Boundary: this is a project-history narrative, not a conformance claim.

## Narrative thesis

Sovereign Memory Core started as a practical personal-memory problem and evolved into a custody-layer project: a way to move AI memory between tools without losing, inventing, or silently rewriting what was known.

The most important shift was from “make my assistant remember better” to “make memory transfer trustworthy.” The repository now frames the work around custody, provenance, review, and authoritative cutover rather than around any one model, UI, or mining tool.

## Timeline

### 1. Personal memory pain becomes the seed

The starting problem was ordinary but deep: AI assistants remember inconsistently across chats, products, and vendors. Useful context gets trapped in one surface, forgotten in another, or distorted when copied forward manually.

Early work focused on a shared memory database that assistants could use as a continuity layer. The practical need was simple:

- keep project state durable;
- reduce repeated re-explanation;
- make corrections persist;
- let multiple assistants coordinate without one chat owning the whole truth.

The design pressure was already visible: memory needed to be owned by the user, not by a chat window.

### 2. The wiki/database split emerges

The project separated two kinds of knowledge:

- small durable facts, stored as memory records;
- longer operating documents, stored as wiki pages.

That split made the system more useful immediately. Facts could be searched and surfaced at boot. Project pages could hold richer context, operating contracts, migration notes, and durable decisions.

This also introduced the first governance problem: when an assistant writes directly into durable wiki pages, it can accidentally turn a suggestion into source-of-record truth. That incident later became a design requirement: producers can propose truth, but approved workflows promote it.

### 3. Hot topics, boot state, and model coordination

The next layer made the database operational instead of archival.

Session boot gave each assistant a compact current-state packet: hot topics, deadlines, proposed-for-review counts, and instruction integrity. Model-channel coordination let agents leave scoped messages for each other instead of relying on one chat's hidden context.

This was the first dogfood moment: the memory system was not just storing notes about the project. It was being used to run the project.

### 4. Vault work forces higher standards

Once health, finance, identity, and other consequential domains entered scope, plain memory records were not enough.

The vault design introduced stricter ideas:

- preserve raw source evidence before normalization;
- separate private/restricted data from general memory;
- use temporal truth instead of overwriting facts;
- keep provenance attached to consequential records;
- audit changes without duplicating sensitive payloads.

This made the project less like a notes app and more like a custody system.

### 5. Manifest thinking replaces blind migration

As the system grew, migration became the real problem.

A memory transfer cannot be trusted just because rows moved from one database to another. A trustworthy migration has to answer harder questions:

- What was the source?
- Was every source item accounted for?
- What was imported, held, excluded, or preserved only as evidence?
- What changed after review?
- What is still unresolved?
- When, exactly, did the new system become authoritative?

This produced the source-import and cutover foundation: source systems, import batches, raw payload evidence, manifests, readiness checks, and cutover probes.

### 6. The project pivots from product to protocol

A key reframing happened when the project stopped treating any single app, miner, or UI as the center.

The durable idea became a protocol-like custody layer around many possible producers and consumers:

- AI chat exports;
- file wikis;
- notes apps;
- spreadsheets;
- databases;
- future memory systems;
- local or hosted assistants.

The core does not need to be the best UI. It needs to be the place where custody, evidence, review state, and cutover are verifiable.

### 7. Chat-Mine becomes research-grade, not the foundation

Chat-Mine started as a tempting path: mine old conversations and convert them into memory candidates.

The hard lesson was that real chat mining is not solved by chunking text and asking a model for facts. Long-running conversations include aliases, topic shifts, stale statements, assistant suggestions, user decisions, contradictions, and project evolution.

The project therefore reframed Chat-Mine as a research producer. It can emit deterministic packages and prove package rails, but it does not yet prove high-quality mining of real conversations.

This was an important anti-overclaiming moment.

### 8. Candidate-level provenance closes a gap

Whole-item payload hashes are useful, but not enough.

A long chat, file, or export can produce many candidate memories. Each candidate needs its own locator, quote, and quote hash so reviewers can inspect the exact supporting span.

That led to candidate locators and quote hashes. The system moved from “this source item was preserved” to “this specific candidate is tied to this specific evidence span.”

### 9. Cutover probes expand beyond positive retrieval

Early cutover thinking focused on whether the system could retrieve expected facts.

That is necessary but weak. A good cutover must also test whether the system can:

- say it does not know;
- surface conflicts;
- avoid stale state;
- ask for evidence;
- fail critical probes visibly.

Richer cutover probe categories turned cutover from a vibe check into an operational scorecard.

### 10. Public repo hardening and pre-license posture

As the repo became public-facing, a separate discipline became necessary:

- avoid publishing private identifiers;
- avoid claiming the project is more complete than it is;
- keep commercial/license posture unresolved until Jesse decides;
- keep scripts from accidentally pointing at non-local databases;
- keep public documentation aligned with actual readiness.

This shifted the project from “personal tool” toward “shareable blueprint,” while still protecting against corporate free-riding and premature claims.

### 11. Live/repo parity dogfood

The current dogfood work compares the live Supabase deployment against the repo implementation.

The key finding is that the live system is usable as a memory layer, but it intentionally diverges from the generic blueprint. The right migration target is not a full core retrofit. The near-term parity work is scoped to source-import and cutover SQL 04-06.

This is the project testing its own doctrine:

- live state is evidence;
- repo SQL is proposed target implementation;
- drift is classified, not hand-waved;
- unresolved findings are held for review;
- no cutover is declared without approval.

## Current story in one paragraph

Sovereign Memory Core is evolving from a personal AI memory database into a custody and cutover layer for trustworthy memory transfer. It treats AI models and import tools as producers of candidates, not owners of truth. The database preserves evidence, stages proposed facts, exposes review state, guards consequential domains, and defines the moment a new memory home becomes authoritative. The live system is already useful for dogfooding, but public claims must stay bounded: custody rails are advancing, full conformance is not yet claimed, and real conversation mining remains research-grade.
