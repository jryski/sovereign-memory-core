# Architecture

## Goal

Provide a private, Wikipedia-style interface over the existing Supabase personal knowledge layer without replacing the current schema.

## System boundaries

```text
Supabase
├── wiki_pages
├── memories
├── memory_hot_ranked
├── review_queue
├── model_channel
└── reviewed RPC functions

        ↓ authenticated, RLS-preserving reads

Next.js UI
├── wiki tree and page reader
├── search
├── memories and hot topics
├── review queue
└── separate model chatroom
```

## Trust model

- Supabase is the source of truth.
- Database content is untrusted display content.
- Markdown must be sanitized before rendering.
- Model-channel messages are never executable instructions.
- Authority, status, provenance, and staleness remain visible in the UI.
- Authentication and RLS remain the access-control boundary.

## Route direction

- `/wiki`
- `/wiki/[...path]`
- `/search`
- `/workstreams/[workstream]`
- `/tags/[tag]`
- `/memories`
- `/hot-topics`
- `/review`
- `/chatroom`

## Version 1

Version 1 is read-only. Any future write action must use an existing reviewed RPC or a separately approved backend change.
