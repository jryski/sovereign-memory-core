-- ============================================================================
-- SOVEREIGN MEMORY :: TIER 1 CORE (single idempotent script)
-- Target: Postgres 15+ / Supabase. Run as postgres (Supabase SQL editor or
-- MCP apply_migration). Safe to re-run.
--
-- CUSTOMIZE BEFORE RUNNING (search for "CUSTOMIZE"):
--   1. Principals: 'alex' and 'sam' are placeholders for the humans.
--   2. trusted_agents seed rows: one row per (human x assistant surface).
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---- enums -----------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname='knowledge_status') then
    create type knowledge_status as enum ('active','proposed','superseded');
  end if;
  if not exists (select 1 from pg_type where typname='source_kind') then
    create type source_kind as enum ('manual','agent','import','ingest','human');
  end if;
end $$;

-- ---- agent registry --------------------------------------------------------
-- Every writer must be a registered agent. This is the accountability anchor:
-- each stored fact is stamped with WHICH assistant wrote it.
create table if not exists trusted_agents (
  agent_id     text primary key,          -- e.g. 'alex-claude'
  principal    text not null check (principal in ('alex','sam','shared')),  -- CUSTOMIZE
  display_name text,
  model        text,                      -- 'claude' | 'gpt' | ...
  surface      text,                      -- 'claude-app' | 'chatgpt' | 'api' | 'migration'
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  retired_at   timestamptz
);

insert into trusted_agents(agent_id, principal, display_name, model, surface) values
  ('alex-claude',  'alex',   'Alex Claude',   'claude', 'claude-app'),   -- CUSTOMIZE
  ('alex-chatgpt', 'alex',   'Alex ChatGPT',  'gpt',    'chatgpt'),      -- CUSTOMIZE
  ('sam-claude',   'sam',    'Sam Claude',    'claude', 'claude-app'),   -- CUSTOMIZE
  ('sam-chatgpt',  'sam',    'Sam ChatGPT',   'gpt',    'chatgpt'),      -- CUSTOMIZE
  ('system',       'shared', 'System / Setup','-',      'migration')
on conflict (agent_id) do nothing;

-- ---- core tables -----------------------------------------------------------
-- Two dimensions on every fact:
--   owner      = who the fact is ABOUT ('alex' | 'sam' | 'shared')
--   visibility = who may SEE it ('shared' default | 'private')
-- A row is visible to viewer V when visibility='shared' OR owner=V.
create table if not exists memories (
  id           uuid primary key default gen_random_uuid(),
  content      text not null,
  tags         text[] not null default '{}',
  workstream   text,                       -- coarse topic bucket, e.g. 'finance'
  owner        text not null check (owner in ('alex','sam','shared')),      -- CUSTOMIZE
  visibility   text not null default 'shared' check (visibility in ('shared','private')),
  source_kind  source_kind not null default 'manual',
  source_agent text not null references trusted_agents(agent_id),
  source_ref   text,                       -- url / file / conversation id
  confidence   numeric,
  status       knowledge_status not null default 'active',
  supersedes   uuid references memories(id),
  metadata     jsonb not null default '{}',
  due_date     timestamptz,
  due_status   text check (due_status in ('pending','done','cancelled')),
  hot_touched  boolean not null default false,   -- receipt set by hot_touch()
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint shared_cannot_be_private check (not (owner='shared' and visibility='private'))
);

create table if not exists wiki_pages (
  id           uuid primary key default gen_random_uuid(),
  path         text not null,              -- e.g. '_system/ai-instructions'
  title        text,
  content      text not null,
  tags         text[] not null default '{}',
  workstream   text,
  owner        text not null check (owner in ('alex','sam','shared')),      -- CUSTOMIZE
  visibility   text not null default 'shared' check (visibility in ('shared','private')),
  source_kind  source_kind not null default 'manual',
  source_agent text not null references trusted_agents(agent_id),
  source_ref   text,
  confidence   numeric,
  status       knowledge_status not null default 'active',
  supersedes   uuid references wiki_pages(id),
  frontmatter  jsonb not null default '{}',   -- page metadata; NOT named "metadata"
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint wiki_shared_cannot_be_private check (not (owner='shared' and visibility='private'))
);
create unique index if not exists wiki_pages_active_path
  on wiki_pages(path) where status='active';

-- Attention layer: a small "hot" list of topics the assistants keep warm.
-- Second-touch gate: first sighting stages; second sighting promotes.
create table if not exists memory_hot_index (
  id           uuid primary key default gen_random_uuid(),
  memory_id    uuid not null references memories(id) on delete cascade,
  topic_key    text not null,              -- slug: workstream/kebab-noun
  owner        text not null check (owner in ('alex','sam','shared')),      -- CUSTOMIZE
  visibility   text not null default 'shared' check (visibility in ('shared','private')),
  summary      text not null,
  workstream   text,
  touch_count  integer not null default 1,
  last_touched timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  unique (owner, topic_key),
  constraint hi_shared_not_private check (not (owner='shared' and visibility='private'))
);

create table if not exists memory_hot_staging (
  owner      text not null check (owner in ('alex','sam','shared')),        -- CUSTOMIZE
  topic_key  text not null,
  first_seen timestamptz not null default now(),
  memory_id  uuid not null references memories(id) on delete cascade,
  summary    text not null,
  workstream text,
  visibility text not null default 'shared' check (visibility in ('shared','private')),
  primary key (owner, topic_key),
  constraint hs_shared_not_private check (not (owner='shared' and visibility='private'))
);

-- Tamper-evidence for operating documents (warn-and-confirm, never lock out).
create table if not exists doc_integrity (
  path           text primary key,
  blessed_sha256 text not null,
  blessed_at     timestamptz not null default now(),
  blessed_note   text
);

-- Append-only audit of status changes + guarded hard deletes.
create table if not exists audit_log (
  id           bigint generated always as identity primary key,
  occurred_at  timestamptz not null default now(),
  table_name   text not null,
  row_id       uuid not null,
  action       text not null,
  source_agent text,
  detail       jsonb not null default '{}'
);

-- Cross-assistant coordination channel (tasks/reminders between the humans'
-- assistants). Each assistant reads its inbox at boot and acts on it.
create table if not exists household_channel (
  seq             bigint generated always as identity primary key,
  from_agent      text not null references trusted_agents(agent_id),
  to_principal    text not null check (to_principal in ('alex','sam','shared')), -- CUSTOMIZE
  kind            text not null check (kind in ('task','todo','reminder','note')),
  subject         text not null,
  body            text,
  due_at          timestamptz,
  add_to_calendar boolean not null default false,
  status          text not null default 'open' check (status in ('open','done','dismissed')),
  re_seq          bigint references household_channel(seq),
  created_at      timestamptz not null default now(),
  completed_at    timestamptz
);
create index if not exists household_channel_inbox
  on household_channel(to_principal, status, due_at);

-- ---- updated_at maintenance ------------------------------------------------
create or replace function set_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end; $$;

drop trigger if exists trg_memories_updated on memories;
create trigger trg_memories_updated before update on memories
  for each row execute function set_updated_at();
drop trigger if exists trg_wiki_updated on wiki_pages;
create trigger trg_wiki_updated before update on wiki_pages
  for each row execute function set_updated_at();

-- ---- views (all security_invoker) -------------------------------------------
-- Hot list ranks only ACTIVE memories; owner/visibility come from the memory.
create or replace view memory_hot_ranked with (security_invoker=true) as
  select hi.id, hi.memory_id, hi.topic_key, m.owner, m.visibility, hi.summary,
         hi.workstream, hi.touch_count, hi.last_touched, hi.created_at,
         (hi.touch_count::numeric
            / (1.0 + (extract(epoch from (now()-hi.last_touched))/86400.0))) as score
  from memory_hot_index hi
  join memories m on m.id = hi.memory_id and m.status='active'
  order by score desc;

create or replace view deadlines_upcoming with (security_invoker=true) as
  select id, content, workstream, owner, visibility, due_date, source_agent,
         (due_date < now()) as overdue,
         (extract(day from (due_date - now())))::int as days_until
  from memories
  where due_date is not null and due_status='pending'
    and status='active' and due_date < (now() + interval '14 days')
  order by due_date;

create or replace view hot_touch_pending with (security_invoker=true) as
  select id, owner, left(content,80) as snippet, workstream, source_agent, created_at
  from memories
  where hot_touched=false and status='active'
    and source_kind='agent' and created_at < (now() - interval '1 hour')
  order by created_at desc;

-- ---- doc integrity functions -------------------------------------------------
create or replace function current_doc_hash(p_path text) returns text
language sql stable security definer set search_path to 'public','extensions'
as $$ select encode(digest(content,'sha256'),'hex')
      from wiki_pages where path=p_path and status='active'; $$;

create or replace function verify_doc_integrity(p_path text)
returns table(path text, state text, blessed_sha256 text, current_sha256 text, blessed_at timestamptz)
language sql stable security definer set search_path to 'public','extensions'
as $$
  select p_path,
    case when di.blessed_sha256 is null then 'no-blessing'
         when di.blessed_sha256 = current_doc_hash(p_path) then 'match'
         else 'mismatch' end,
    di.blessed_sha256, current_doc_hash(p_path), di.blessed_at
  from (select 1) x left join doc_integrity di on di.path=p_path;
$$;

create or replace function bless_doc(p_path text, p_note text default null) returns text
language plpgsql security definer set search_path to 'public','extensions'
as $$
declare v_hash text;
begin
  v_hash := current_doc_hash(p_path);
  if v_hash is null then return 'no-active-doc-at-path'; end if;
  insert into doc_integrity(path, blessed_sha256, blessed_at, blessed_note)
  values (p_path, v_hash, now(), p_note)
  on conflict (path) do update
    set blessed_sha256=excluded.blessed_sha256, blessed_at=now(), blessed_note=excluded.blessed_note;
  return 'blessed:'||v_hash;
end; $$;

-- ---- hot_touch / remember ----------------------------------------------------
-- hot_touch derives owner/visibility/summary/workstream from the memory itself.
-- Per-owner cap of 15 hot topics; lowest score evicts.
create or replace function hot_touch(p_topic_key text, p_memory_id uuid,
                                     p_summary text default null, p_workstream text default null)
returns text language plpgsql security definer set search_path to 'public'
as $$
declare v_owner text; v_vis text; v_ws text; v_sum text; v_content text;
        v_min_id uuid; v_count int;
begin
  select owner, visibility, workstream, content into v_owner, v_vis, v_ws, v_content
    from memories where id = p_memory_id;
  if v_owner is null then raise exception 'hot_touch: memory % not found', p_memory_id; end if;
  v_ws  := coalesce(p_workstream, v_ws);
  v_sum := left(coalesce(p_summary, v_content), 200);

  update memories set hot_touched=true where id=p_memory_id;

  update memory_hot_index set touch_count=touch_count+1, last_touched=now()
   where topic_key=p_topic_key and owner=v_owner;
  if found then return 'bumped'; end if;

  if exists (select 1 from memory_hot_staging where topic_key=p_topic_key and owner=v_owner) then
    select count(*) into v_count from memory_hot_index where owner=v_owner;
    if v_count >= 15 then
      select hi.id into v_min_id from memory_hot_index hi
        join memories m on m.id=hi.memory_id and m.status='active'
        where hi.owner=v_owner
        order by (hi.touch_count::numeric/(1.0+(extract(epoch from (now()-hi.last_touched))/86400.0))) asc
        limit 1;
      if v_min_id is not null then delete from memory_hot_index where id=v_min_id; end if;
    end if;
    insert into memory_hot_index(memory_id, topic_key, owner, visibility, summary, workstream, touch_count, last_touched)
      values (p_memory_id, p_topic_key, v_owner, v_vis, v_sum, v_ws, 2, now());
    delete from memory_hot_staging where topic_key=p_topic_key and owner=v_owner;
    return 'promoted';
  end if;

  insert into memory_hot_staging(owner, topic_key, memory_id, summary, workstream, visibility)
    values (v_owner, p_topic_key, p_memory_id, v_sum, v_ws, v_vis)
    on conflict (owner, topic_key) do nothing;
  return 'staged';
end; $$;

-- remember(): one-call write (insert + hot_touch). Owner REQUIRED; agent validated.
create or replace function remember(
  p_content text, p_workstream text, p_topic_key text,
  p_source_agent text, p_owner text,
  p_summary text default null, p_tags text[] default '{}',
  p_visibility text default 'shared', p_due_date timestamptz default null
) returns uuid language plpgsql security definer set search_path to 'public'
as $$
declare v_id uuid;
begin
  if not exists (select 1 from trusted_agents where agent_id=p_source_agent and active) then
    raise exception 'remember: source_agent % is not a known active trusted agent', p_source_agent;
  end if;
  insert into memories(content, workstream, tags, owner, visibility, source_agent, source_kind, due_date, due_status)
  values (p_content, p_workstream, p_tags, p_owner, p_visibility, p_source_agent, 'agent', p_due_date,
          case when p_due_date is not null then 'pending' else null end)
  returning id into v_id;
  perform hot_touch(p_topic_key, v_id, coalesce(p_summary, left(p_content,200)), p_workstream);
  return v_id;
end; $$;

-- ---- atomic supersede (correct without deleting) -----------------------------
create or replace function supersede_memory(p_old_id uuid, p_new_content text, p_source_agent text,
  p_summary text default null, p_tags text[] default null, p_due_date timestamptz default null)
returns uuid language plpgsql security definer set search_path to 'public'
as $$
declare v_old memories%rowtype; v_new uuid;
begin
  if not exists (select 1 from trusted_agents where agent_id=p_source_agent and active) then
    raise exception 'supersede_memory: unknown/inactive source_agent %', p_source_agent; end if;
  select * into v_old from memories where id=p_old_id for update;
  if not found then raise exception 'supersede_memory: % not found', p_old_id; end if;
  if v_old.status <> 'active' then raise exception 'supersede_memory: % is % not active', p_old_id, v_old.status; end if;
  insert into memories(content, workstream, tags, owner, visibility, source_agent, source_kind, supersedes, status, due_date, due_status)
  values (p_new_content, v_old.workstream, coalesce(p_tags, v_old.tags), v_old.owner, v_old.visibility,
          p_source_agent, 'agent', p_old_id, 'active', p_due_date,
          case when p_due_date is not null then 'pending' else null end)
  returning id into v_new;
  update memories set status='superseded' where id=p_old_id;
  update memory_hot_index set memory_id=v_new, summary=left(coalesce(p_summary,p_new_content),200), last_touched=now()
   where memory_id=p_old_id;
  return v_new;
end; $$;

create or replace function supersede_wiki(p_path text, p_new_content text, p_source_agent text,
  p_title text default null, p_frontmatter jsonb default null)
returns uuid language plpgsql security definer set search_path to 'public'
as $$
declare v_old wiki_pages%rowtype; v_new uuid;
begin
  if not exists (select 1 from trusted_agents where agent_id=p_source_agent and active) then
    raise exception 'supersede_wiki: unknown/inactive source_agent %', p_source_agent; end if;
  select * into v_old from wiki_pages where path=p_path and status='active' for update;
  if not found then raise exception 'supersede_wiki: no active page at %', p_path; end if;
  update wiki_pages set status='superseded' where id=v_old.id;
  insert into wiki_pages(path, title, content, tags, workstream, owner, visibility, source_kind, source_agent, supersedes, frontmatter, status)
  values (p_path, coalesce(p_title,v_old.title), p_new_content, v_old.tags, v_old.workstream, v_old.owner, v_old.visibility,
          'agent', p_source_agent, v_old.id, coalesce(p_frontmatter, v_old.frontmatter), 'active')
  returning id into v_new;
  return v_new;
end; $$;

-- ---- audit + delete guard ----------------------------------------------------
create or replace function audit_status_changes() returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status then
    insert into audit_log(table_name,row_id,action,source_agent,detail)
    values (TG_TABLE_NAME, new.id, 'status_change', new.source_agent,
            jsonb_build_object('from',old.status,'to',new.status));
  end if;
  if TG_TABLE_NAME='memories' then
    if new.due_status is distinct from old.due_status then
      insert into audit_log(table_name,row_id,action,source_agent,detail)
      values ('memories', new.id, 'due_status_change', new.source_agent,
              jsonb_build_object('from',old.due_status,'to',new.due_status));
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists trg_audit_memories on memories;
create trigger trg_audit_memories after update on memories for each row execute function audit_status_changes();
drop trigger if exists trg_audit_wiki on wiki_pages;
create trigger trg_audit_wiki after update on wiki_pages for each row execute function audit_status_changes();

-- Hard deletes blocked by default; supersede instead. Admin override:
--   set local app.allow_delete='on';  (inside a transaction)
create or replace function guard_hard_delete() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.allow_delete', true),'off') <> 'on' then
    raise exception 'hard delete blocked on %; supersede instead (admin: set local app.allow_delete=''on'')', TG_TABLE_NAME;
  end if;
  insert into audit_log(table_name,row_id,action,detail)
  values (TG_TABLE_NAME, old.id, 'hard_delete', jsonb_build_object('override',true));
  return old;
end; $$;
drop trigger if exists trg_guard_del_memories on memories;
create trigger trg_guard_del_memories before delete on memories for each row execute function guard_hard_delete();
drop trigger if exists trg_guard_del_wiki on wiki_pages;
create trigger trg_guard_del_wiki before delete on wiki_pages for each row execute function guard_hard_delete();

-- ---- channel functions ---------------------------------------------------------
create or replace function channel_send(
  p_from_agent text, p_to_principal text, p_kind text, p_subject text,
  p_body text default null, p_due_at timestamptz default null,
  p_add_to_calendar boolean default false, p_re_seq bigint default null
) returns bigint language plpgsql security definer set search_path to 'public'
as $$
declare v_seq bigint;
begin
  if not exists (select 1 from trusted_agents where agent_id=p_from_agent and active) then
    raise exception 'channel_send: unknown/inactive from_agent %', p_from_agent; end if;
  insert into household_channel(from_agent,to_principal,kind,subject,body,due_at,add_to_calendar,re_seq)
  values (p_from_agent,p_to_principal,p_kind,p_subject,p_body,p_due_at,p_add_to_calendar,p_re_seq)
  returning seq into v_seq;
  return v_seq;
end; $$;

create or replace function channel_complete(p_seq bigint, p_status text default 'done')
returns text language plpgsql security definer set search_path to 'public'
as $$
begin
  if p_status not in ('done','dismissed') then
    raise exception 'channel_complete: status must be done or dismissed'; end if;
  update household_channel set status=p_status, completed_at=now() where seq=p_seq;
  if not found then raise exception 'channel_complete: seq % not found', p_seq; end if;
  return p_status;
end; $$;

-- ---- session_boot: the assistant's first call --------------------------------
create or replace function session_boot(p_viewer text default 'shared') returns jsonb
language sql stable security definer set search_path to 'public','extensions'
as $$
  with visible as (select * from memory_hot_ranked where visibility='shared' or owner=p_viewer),
       own  as (select * from visible where owner=p_viewer order by score desc limit 6),
       rest as (select * from visible where id not in (select id from own)
                order by score desc limit greatest(0, 15 - (select count(*) from own))),
       hot  as (select * from own union all select * from rest)
  select jsonb_build_object(
    'viewer', p_viewer,
    'hot_topics', (select coalesce(jsonb_agg(jsonb_build_object('topic_key',topic_key,'owner',owner,'summary',summary,
                      'workstream',workstream,'touch_count',touch_count,'score',round(score::numeric,2)) order by score desc),'[]'::jsonb) from hot),
    'deadlines', (select coalesce(jsonb_agg(jsonb_build_object('content',left(content,100),'owner',owner,'due_date',due_date,
                      'overdue',overdue,'days_until',days_until) order by due_date),'[]'::jsonb)
                  from deadlines_upcoming where visibility='shared' or owner=p_viewer),
    'channel_inbox', (select coalesce(jsonb_agg(x),'[]'::jsonb) from (
                  select jsonb_build_object('seq',seq,'from',from_agent,'kind',kind,'subject',subject,
                         'due_at',due_at,'add_to_calendar',add_to_calendar) as x
                  from household_channel
                  where status='open' and to_principal in (p_viewer,'shared')
                  order by due_at asc nulls last, created_at asc limit 25) s),
    'instruction_integrity', (select state from verify_doc_integrity('_system/ai-instructions')),
    'health', jsonb_build_object(
        'memories_visible',    (select count(*) from memories where status='active' and (visibility='shared' or owner=p_viewer)),
        'hot_touch_pending',   (select count(*) from hot_touch_pending where owner=p_viewer or owner='shared'),
        'proposed_for_review', (select count(*) from memories where status='proposed' and (visibility='shared' or owner=p_viewer)),
        'channel_open',        (select count(*) from household_channel where status='open' and to_principal in (p_viewer,'shared'))),
    'booted_at', now());
$$;

-- ---- perimeter assertion -------------------------------------------------------
create or replace function assert_perimeter_closed() returns text
language plpgsql security definer set search_path to 'public'
as $$
declare v_tab int; v_fn boolean;
begin
  select count(*) into v_tab from information_schema.role_table_grants
   where table_schema='public' and grantee in ('anon','authenticated','PUBLIC');
  if v_tab > 0 then raise exception 'PERIMETER FAIL: anon/authenticated/PUBLIC hold % table grants', v_tab; end if;
  select exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) acl
    where acl.privilege_type='EXECUTE' and acl.grantee::regrole::text in ('anon','authenticated','-')
  ) into v_fn;
  if v_fn then raise exception 'PERIMETER FAIL: anon/authenticated/PUBLIC can execute public functions'; end if;
  return 'perimeter OK';
end; $$;

-- ---- seed the operating contract (see docs/03; edit before or after seeding) ---
insert into wiki_pages(path, title, content, status, owner, visibility, source_agent, frontmatter)
select '_system/ai-instructions','AI Operating Instructions',
$DOC$# AI Operating Instructions

This database is the shared memory layer for this household's AI assistants.
The full, human-readable contract lives in the repo at docs/03-agent-operations.md.
Replace this page's content with your customized contract, then run:
    select bless_doc('_system/ai-instructions','customized');
$DOC$,
       'active','shared','shared','system',
       '{"authority":"system","is_instruction":true}'::jsonb
where not exists (select 1 from wiki_pages where path='_system/ai-instructions' and status='active');

select bless_doc('_system/ai-instructions','initial seed');

-- ---- close the perimeter --------------------------------------------------------
-- Supabase default-grants anon/authenticated on new public objects. Close it and
-- keep it closed via default privileges. service_role remains the only API path.
revoke all on all tables    in schema public from anon, authenticated, public;
revoke all on all sequences in schema public from anon, authenticated, public;
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public;
grant execute on all functions in schema public to service_role;

select assert_perimeter_closed();
