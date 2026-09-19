# Core status checkpoint

Updated September 7, 2026. This checkpoint supplements the historical status scorecard; it does not rerate the project.

Core is the PostgreSQL reference implementation beneath household and business applications. SMP is now a [public draft](https://github.com/jryski/sovereign-memory-protocol), not a published standard. Existing release and restore evidence remains limited to its recorded scope. No database replay or fresh restore acceptance was performed for this documentation update.

Open partial-store coverage work in PR 73 is relevant to the household discovery failure: searching one store cannot establish global absence. Its implementation is still under review. Household routing behavior belongs in Household OS; generic coverage and custody invariants belong here.

User MCP's 134 passing local offline tests are downstream evidence, not Core or live-deployment certification. Preserve history and exact-base/head review. No new release, license change or production rollout is included.
