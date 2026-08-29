# Sovereign AI OS ecosystem context

This directory contains **informative program-level artifacts** for the wider Sovereign AI OS ecosystem. They explain how independently governed repositories compose without making Sovereign Memory Core the owner of every layer.

Component repositories remain authoritative for their own implementation, tests, status, security, and releases.

## Start here

- [`SOVEREIGN_AI_OS.md`](SOVEREIGN_AI_OS.md) — human-readable north star, planes, architectural laws, repository map, and order of operations.
- [`program-manifest.json`](program-manifest.json) — machine-readable component map for agents, tooling, dashboards, and stale-status review.
- [`program-manifest.schema.json`](program-manifest.schema.json) — open JSON Schema for the manifest.
- [`BUSINESS_PLANNING_WORK_PLANE.md`](BUSINESS_PLANNING_WORK_PLANE.md) — first-class Business OS planning and work profile.

Household-specific planning is maintained in:

- [`jryski/Household-OS/docs/PLANNING_WORK_PLANE.md`](https://github.com/jryski/Household-OS/blob/main/docs/PLANNING_WORK_PLANE.md)

Principal-bound planning access is maintained in:

- [`jryski/Supabase_user_MCP/docs/PLANNING_DATA_PLANE_PROFILE.md`](https://github.com/jryski/Supabase_user_MCP/blob/main/docs/PLANNING_DATA_PLANE_PROFILE.md)

## Authority rules

1. Jesse's accepted decisions define program intent.
2. Protocol and versioned shared contracts define semantics within their stated scope.
3. Each component repository defines and proves its own implementation.
4. Deployment stores define accepted operational state for that deployment.
5. Planning boards coordinate work but do not replace exact repository or provider evidence.
6. Chat and model discussion remain proposals until promoted into durable artifacts.

## Agent use

Agents should read the program context and manifest to identify boundaries and dependencies, then read the target repository's `PROGRAM-ROLE.md`, README, status, security, and contribution documents before proposing work.

The manifest is a dated snapshot. Missing or stale component evidence must be reported as unknown, not filled with plausible continuity.

## Privacy

These public artifacts contain architecture and sanitized repository metadata only. They must never acquire credentials, private deployment locators, real household records, company payloads, project IDs from private stores, raw recovery artifacts, or model-visible database exports.