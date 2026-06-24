# Implementation Plan

## Phase 0: Bootstrap

- Initialize repository and branching workflow.
- Add `AGENTS.md`, architecture notes, and a minimal Next.js shell.
- Confirm the live Supabase project and inspect schema, views, RPC functions, and RLS.

## Phase 1: Authentication and data access

- Add Supabase Auth.
- Add server-side Supabase client utilities.
- Confirm authenticated reads work under current RLS.
- Document any missing policy instead of weakening security.

## Phase 2: Wiki reader

- Build page-tree generation from slash-separated `wiki_pages.path` values.
- Add `/wiki/[...path]` rendering.
- Render Markdown through `react-markdown`, `remark-gfm`, and `rehype-sanitize`.
- Show breadcrumbs, tags, workstream, status, authority, provenance, and timestamps.

## Phase 3: Search and related content

- Search titles, paths, content, tags, workstreams, and memories.
- Add deterministic related-page ranking using path, tags, and workstream.
- Add backlink parsing for internal wiki paths.

## Phase 4: Memory surfaces

- Add memories view with authority/status distinctions.
- Add hot-topic dashboard.
- Add supersede-chain visibility.

## Phase 5: Governance surfaces

- Add read-only review queue.
- Add separate authenticated model-chatroom threads.
- Keep chatroom content out of ordinary wiki search by default.

## Phase 6: Quality gate

- Unit tests for path-tree creation and metadata normalization.
- Security tests for Markdown sanitization.
- Lint, type checking, and production build.
- Manual RLS and secret-exposure review.

## Deferred

- Editing wiki pages
- Promotion/rejection actions
- Memory correction actions
- Graph visualization
- Semantic recommendations beyond existing reviewed functions
- Any Supabase schema migration
