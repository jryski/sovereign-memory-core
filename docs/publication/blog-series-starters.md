# Blog series starters: building Sovereign Memory Core

Status: draft starter set.
Goal: help Jesse tell the story in public without overclaiming.
Tone: practical, builder-led, transparent about tradeoffs.

## Series title options

1. Building a Memory Layer I Actually Own
2. Trustworthy Memory Transfer
3. My AI Remembered Me, But I Did Not Own the Memory
4. From Chat History to Chain of Custody
5. The Personal Data Layer AI Should Have Had

## Post 1: The problem was not memory. It was custody.

### Hook

AI memory sounds convenient until you realize you do not really own it. It lives inside products, chats, settings, and vendor decisions. The first time you try to move it, audit it, or prove what changed, “memory” turns into a custody problem.

### What to cover

- Repeating context across chats gets old fast.
- Vendor memory is useful, but siloed.
- Copy/paste summaries are not evidence.
- The real question became: how do I own the durable layer?
- Introduce the idea of memory as user-controlled infrastructure.

### Key line

The goal was not to make one assistant smarter. It was to stop making every new assistant start from zero.

### Boundaries to state

This was not born as a polished product. It started as dogfood for one person's real project continuity problem.

## Post 2: Why I split memory into facts and wiki pages

### Hook

Not everything an AI should remember is the same shape. Some things are small durable facts. Some things are living project documents. Treating both as the same thing makes the system messy fast.

### What to cover

- Small memories are good for boot context and retrieval.
- Wiki pages are better for operating contracts, project state, and durable documentation.
- Why source-of-record pages need more caution than ordinary notes.
- The first governance lesson: assistant-written docs can accidentally become “truth.”

### Key line

A memory system needs places to write things down, but it also needs rules for what counts as accepted truth.

## Post 3: Session boot changed the system from archive to operating layer

### Hook

A database of memories is useful. A database that can brief a new assistant at the start of a session is different.

### What to cover

- Hot topics.
- Deadlines.
- Proposed-for-review counts.
- Instruction integrity.
- Model-channel coordination.
- Why dogfooding matters: the system began running the project that was building the system.

### Key line

The memory layer became useful when it stopped being a storage bin and started becoming a session operating state.

## Post 4: Consequential memory needs a vault

### Hook

It is one thing to remember a project preference. It is another to remember health, finance, identity, or legal context. Those domains need a different posture.

### What to cover

- Preserve raw source evidence before normalization.
- Temporal truth beats overwriting.
- Provenance and citation requirements.
- Audit without duplicating sensitive data.
- Why “helpful” is not enough in consequential domains.

### Key line

The more important the memory, the less it should depend on the assistant being careful.

## Post 5: Migration without amnesia

### Hook

Moving memory is easy if you do not care what gets lost. Trustworthy transfer is harder.

### What to cover

- Why row copy is not enough.
- Source systems and import batches.
- Raw payload preservation.
- Manifest review: import, hold, exclude, evidence.
- Readiness checks and cutover probes.
- Rollback as part of the design.

### Key line

A migration is not done when the data lands. It is done when you can prove what happened.

## Post 6: The pivot from product to protocol

### Hook

At first, I thought I was building a personal memory app. Eventually, I realized the app was not the important part.

### What to cover

- Apps are replaceable clients.
- Models are replaceable clients.
- Adapters are replaceable producers.
- The durable custody layer is the core.
- Why a protocol-like posture makes the project more useful and less fragile.

### Key line

The UI can change. The model can change. The custody record should survive both.

## Post 7: Why Chat-Mine is not solved yet

### Hook

Mining old AI chats sounds straightforward until you try it on real conversations.

### What to cover

- Long chats contain topic shifts, aliases, stale decisions, and assistant suggestions.
- Chunk-to-model extraction is not enough.
- Deterministic package rails are useful but not proof of mining quality.
- Research gates: whole-conversation maps, entity resolution, temporal state, known-answer evals.
- The value of saying “not solved yet.”

### Key line

A model can extract plausible memories. That is not the same as proving what the user actually decided.

## Post 8: Candidate-level evidence

### Hook

Preserving the whole source file is not enough when one file produces many proposed memories.

### What to cover

- Whole payload hashes.
- Candidate locators.
- Support quotes.
- Quote hashes.
- Why reviewers need exact evidence spans.

### Key line

Evidence has to attach to the claim, not just to the box the claim came from.

## Post 9: Cutover is a decision, not a feeling

### Hook

The dangerous moment in any migration is when you start acting like the new system is authoritative before it has earned that status.

### What to cover

- Positive probes.
- Negative probes.
- Conflict probes.
- Stale-state probes.
- Evidence-request probes.
- Critical misses as blockers.
- The exact moment of authority.

### Key line

A new memory home becomes the truth only when the scorecard passes and a human-approved workflow says so.

## Post 10: What this project taught me about AI sovereignty

### Hook

The more I built, the more this stopped being just a technical project. It became a question of leverage.

### What to cover

- Personal data is training fuel, context, and value.
- If users cannot own/export/prove their memory, value flows one way.
- Custody enables negotiation.
- Provenance enables trust.
- Review prevents models from laundering guesses into truth.
- The goal is not anti-AI. It is pro-human agency.

### Key line

No custody, no leverage. No provenance, no trust. No review, no truth.

## Suggested publishing order

1. Start with the custody problem.
2. Show the practical memory/wiki split.
3. Explain dogfooding and session boot.
4. Introduce the vault.
5. Move into migration/cutover.
6. Then talk about protocol, Chat-Mine limits, and sovereignty.

## Reusable disclaimer language

This project is early and dogfooded. It is not claiming full conformance to any finalized SMP standard, and it is not claiming that real-world conversation mining is solved. The current work focuses on custody rails: evidence preservation, candidate review, source-import accounting, and explicit cutover.
