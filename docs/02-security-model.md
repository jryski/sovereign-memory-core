# 02 · Security model

Read this before storing anything sensitive. It is short and it is all load-bearing.

## The real boundary is the connector, not the schema

If two assistants share one service-role connector, they share one blast radius. Schema
separation (public vs `*_private`) protects against the API surface (anon/authenticated
REST paths), not against a compromised or confused agent holding service-role. Understand
what you actually have:

- **service_role** bypasses RLS by design. Every assistant you connect with it can read
  and write everything the role can reach. That is the deal you are making, and for a
  household of trusted assistants it is a reasonable deal, but make it knowingly.
- Consequently: prompt-injection resistance, agent registration (`trusted_agents`),
  provenance triggers, integrity blessing, delete guards, and the audit log are your
  in-band defenses. They constrain what a misbehaving agent can do QUIETLY, which in
  practice is the attack that matters.

Hardening ladder, in order of effort:
1. Credential discipline: one connector, rotated if ever exposed; never paste keys in chat.
2. Narrow Postgres roles: a dedicated role with EXECUTE only on an API schema of
   SECURITY DEFINER functions (no raw table access). Do this before adding users you
   trust less than your spouse.
3. Separate projects per trust domain (household vs business vs pilot customer), each
   with its own credentials. Do NOT mirror schemas between them; share patterns.

## The Supabase auto-grant trap (the bug that keeps coming back)

Supabase grants anon/authenticated on **new** objects in `public` by default. Two failure
modes seen in the wild while building this:

1. A migration creates a table, enables RLS, adds no policies, and everyone assumes
   default-deny. But the GRANT is still there; RLS-with-no-policies blocks rows, yet the
   grant surface is live and one permissive policy away from exposure. Worse, views and
   functions are not covered by table RLS at all.
2. A migration revokes on FUNCTIONS but forgets tables, or vice versa. Postgres also
   grants EXECUTE on new functions to PUBLIC by default.

The fix is mechanical and belongs in EVERY migration that creates objects:

```sql
revoke all on all tables    in schema public from anon, authenticated, public;
revoke all on all sequences in schema public from anon, authenticated, public;
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;
select assert_perimeter_closed();   -- raises if anything is still open
```

`01_core.sql` also sets `alter default privileges` so future objects are born closed,
including the postgres-owned sequence gap. Belt and suspenders: keep the assert anyway,
because "default privileges" only cover the role they were set for.

`assert_perimeter_closed()` is the acceptance test made permanent: it raises an exception
if anon/authenticated/PUBLIC hold any table grant or can execute any public function.
Run it at the end of every migration. A migration that reopens the perimeter fails loudly
instead of shipping silently.

Known benign residue on Supabase: extension-internal functions (e.g. pgvector operators)
granted by `supabase_admin` cannot be revoked by `postgres` and have no data access.
If you extend the assert to cover them you will chase ghosts; scope it to non-extension
grantors if needed.

## Views must be security_invoker

Postgres views default to definer semantics: they execute with the view OWNER's
privileges. A view created by postgres over a locked table quietly bypasses the lock for
anyone who can select the view. Every view in this repo is created
`with (security_invoker=true)`; keep that habit for any view you add.

## SECURITY DEFINER functions: pin the search_path

Every SECURITY DEFINER function here sets `search_path` explicitly (usually
`to 'public'` or `= ''` with schema-qualified references). Without it, a caller who can
create objects in an earlier schema on the path can hijack name resolution inside your
privileged function. Non-negotiable on definer functions.

## In-band integrity: the blessed operating doc

The assistants' behavior contract lives in the database they operate on, which means a
sufficiently confused agent could be induced to edit its own rules. `bless_doc()` +
`verify_doc_integrity()` make that tamper-EVIDENT: the human blesses a hash after every
approved edit; every boot compares. Policy on mismatch is warn-and-confirm, never
hard-refuse; the failure mode of locking the owner out of their own system is worse than
the attack.

## Delete posture

Hard deletes on Tier 1 are trigger-blocked (supersede instead). The override
(`set local app.allow_delete='on'`) is transaction-scoped, admin-only in practice, and
audit-logged. Data disappears from this system on purpose, with a paper trail, or not
at all.

## Audit posture

- Tier 1: `audit_log` records status transitions and any override-deleted rows.
- Tier 2: `vault_audit.change_log` records every write to every domain table with
  principal, action, table, id, and column keys only. Keys-only is deliberate: an audit
  trail must not become an unguarded second copy of health and finance payloads.

## What to tell your threat model

This design assumes: the humans are trusted; the assistants are semi-trusted (helpful
but occasionally confused or injectable); the vendor is honest-but-replaceable; the
network path uses the vendor's connector auth. It defends well against quiet corruption,
provenance laundering, contract tampering, accidental exposure via API defaults, and
vendor lock-in. It does not defend against a malicious human with the service key or a
compromised database host; those need role narrowing (ladder step 2/3) and standard
infrastructure hygiene respectively.
