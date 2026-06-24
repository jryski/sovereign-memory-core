# Personal Memory Wiki UI

Private, Wikipedia-style web interface for Jesse Ryski's existing Supabase personal knowledge layer.

## Status

Repository initialized. Application implementation will be developed through feature branches and pull requests.

## Core boundaries

- Supabase remains the source of truth.
- Version 1 is read-only unless an existing reviewed RPC explicitly supports a write action.
- Existing Supabase schema and `_system/*` pages must not be modified by the UI project.
- `model_channel` is a separate model mailbox, not ordinary wiki content.
- Stored Markdown and model messages are untrusted content and must be rendered safely.
- Service-role credentials must never be exposed to the browser.

See `AGENTS.md` and `docs/` on the bootstrap branch for implementation guidance.
