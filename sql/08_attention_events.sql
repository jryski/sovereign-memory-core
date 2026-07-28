-- ============================================================================
-- SOVEREIGN MEMORY :: ATTENTION EVENTS + PROJECTION V2
-- Target: PostgreSQL 15+. Run after sql/01_core.sql.
--
-- Fresh-install/additive contract:
--   * no destructive topic eviction or fixed topic-count worldview;
--   * native append-only source-semantic events;
--   * stable identity with linked observed revisions;
--   * separate append-only project/workstream/topic assignments;
--   * proposed->active captured as memory_activated, not memory_created;
--   * exact serialized-character, deterministic monotonic boot projection.
--
-- Existing deployments require a reviewed upgrade. Do not fabricate historical
-- events or rewrite old attention state. See docs/upgrades/work-memory-v2.md.
-- ============================================================================

create table if not exists attention_events (
  id                     uuid primary key default gen_random_uuid(),
  contract_version       text not null default 'attention-event/0.2'
                           check (contract_version ~ '[^[:space:]]'),
  source_system          text not null check (source_system ~ '[^[:space:]]'),
  source_namespace       text not null check (source_namespace ~ '[^[:space:]]'),
  source_event_type      text not null check (source_event_type ~ '[^[:space:]]'),
  source_native_event_id text,
  identity_key           text not null check (identity_key ~ '^[0-9a-f]{64}$'),
  revision_key           text not null unique check (revision_key ~ '^[0-9a-f]{64}$'),
  source_revision        text,
  revision_ordinal       integer not null default 1 check (revision_ordinal>0),
  supersedes_event_id    uuid references attention_events(id) on delete restrict,
  memory_id              uuid references memories(id) on delete restrict,
  principal_key          text,
  owner                  text,
  visibility             text check (visibility is null or visibility in ('shared','private')),
  actor_key              text,
  credential_ref         text,
  runtime_ref            text,
  workstream_as_of       text,
  topic_key_as_of        text,
  occurred_at            timestamptz not null,
  recorded_at            timestamptz not null default now(),
  source_evidence_ref    text not null check (source_evidence_ref ~ '[^[:space:]]'),
  observation_method     text not null check (observation_method ~ '[^[:space:]]'),
  historical_import      boolean not null default false,
  metadata               jsonb not null default '{}',
  constraint attention_events_revision_shape check (
    (revision_ordinal=1 and supersedes_event_id is null)
    or (revision_ordinal>1 and supersedes_event_id is not null)
  )
);

create unique index if not exists attention_events_identity_revision_uq
  on attention_events(identity_key,revision_ordinal);
create unique index if not exists attention_events_one_successor_uq
  on attention_events(supersedes_event_id)
  where supersedes_event_id is not null;
create index if not exists attention_events_memory_idx
  on attention_events(memory_id,recorded_at);

create table if not exists attention_event_assignments (
  id                       uuid primary key default gen_random_uuid(),
  event_id                 uuid not null references attention_events(id) on delete restrict,
  assignment_kind          text not null check (assignment_kind in ('project','workstream','topic')),
  assignment_key           text not null check (assignment_key ~ '[^[:space:]]'),
  confidence               numeric check (confidence is null or confidence between 0 and 1),
  assigned_by              text not null check (assigned_by ~ '[^[:space:]]'),
  assignment_model_version text,
  supersedes               uuid references attention_event_assignments(id) on delete restrict,
  assigned_at              timestamptz not null default now(),
  constraint attention_assignment_not_self check (supersedes is null or supersedes<>id),
  unique(event_id,assignment_kind,assignment_key,assigned_by)
);

create unique index if not exists attention_assignment_one_successor_uq
  on attention_event_assignments(supersedes)
  where supersedes is not null;

comment on table attention_events is
  'Append-only non-content observation envelopes. Stable identity may have multiple linked observed revisions.';
comment on table attention_event_assignments is
  'Append-only derived project/workstream/topic classifications linked to attention events.';

alter table attention_events enable row level security;
alter table attention_event_assignments enable row level security;
revoke all on attention_events,attention_event_assignments from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on attention_events,attention_event_assignments from anon';
  end if;
  if exists(select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on attention_events,attention_event_assignments from authenticated';
  end if;
  if exists(select 1 from pg_roles where rolname='service_role') then
    execute 'revoke all on attention_events,attention_event_assignments from service_role';
    execute 'grant select on attention_events,attention_event_assignments to service_role';
  end if;
end $$;

create or replace function attention_hash_parts(variadic p_parts text[])
returns text
language sql immutable set search_path=public,extensions as $$
select encode(extensions.digest(convert_to(string_agg(
  case when part is null then '-1:' else octet_length(part)::text||':'||part end,
  '|' order by ord
),'UTF8'),'sha256'),'hex')
from unnest(p_parts) with ordinality as u(part,ord);
$$;

create or replace function attention_workstream_key(p_workstream text)
returns text
language sql immutable set search_path=public as $$
select case
  when p_workstream is null or p_workstream !~ '[^[:space:]]' then null
  else 'workstream/'||trim(both '-' from lower(regexp_replace(btrim(p_workstream),'[^a-zA-Z0-9]+','-','g')))
end;
$$;

create or replace function attention_summary_at_word_boundary(p_text text,p_max_chars integer)
returns text
language plpgsql immutable set search_path=public as $$
declare v_cut text;v_trimmed text;
begin
  if p_text is null then return null; end if;
  if p_max_chars<1 then return ''; end if;
  if char_length(p_text)<=p_max_chars then return btrim(p_text); end if;
  v_cut:=left(p_text,p_max_chars);
  if v_cut !~ '[[:space:]]' then return ''; end if;
  v_trimmed:=regexp_replace(v_cut,'[[:space:]][^[:space:]]*$','');
  return btrim(v_trimmed);
end;
$$;

create or replace function guard_attention_append_only()
returns trigger language plpgsql set search_path=public as $$
begin
  raise exception '% is append-only; % is not permitted',tg_table_name,tg_op;
end;
$$;

create or replace function guard_attention_truncate()
returns trigger language plpgsql set search_path=public as $$
begin
  raise exception '% is append-only; TRUNCATE is not permitted',tg_table_name;
end;
$$;

drop trigger if exists trg_attention_events_append_only on attention_events;
create trigger trg_attention_events_append_only
before update or delete on attention_events
for each row execute function guard_attention_append_only();
drop trigger if exists trg_attention_events_no_truncate on attention_events;
create trigger trg_attention_events_no_truncate
before truncate on attention_events
for each statement execute function guard_attention_truncate();

drop trigger if exists trg_attention_assignments_append_only on attention_event_assignments;
create trigger trg_attention_assignments_append_only
before update or delete on attention_event_assignments
for each row execute function guard_attention_append_only();
drop trigger if exists trg_attention_assignments_no_truncate on attention_event_assignments;
create trigger trg_attention_assignments_no_truncate
before truncate on attention_event_assignments
for each statement execute function guard_attention_truncate();

create or replace function validate_attention_event_revision_lineage()
returns trigger language plpgsql set search_path=public as $$
declare v_previous attention_events%rowtype;
begin
  if new.revision_ordinal=1 then
    if new.supersedes_event_id is not null then raise exception 'revision 1 cannot supersede another event'; end if;
    return new;
  end if;
  select * into v_previous from attention_events where id=new.supersedes_event_id;
  if not found then raise exception 'superseded event not found'; end if;
  if v_previous.identity_key<>new.identity_key then raise exception 'revision identity mismatch'; end if;
  if v_previous.revision_ordinal<>new.revision_ordinal-1 then raise exception 'revision ordinal must follow predecessor'; end if;
  return new;
end;
$$;

drop trigger if exists trg_attention_revision_lineage on attention_events;
create trigger trg_attention_revision_lineage
before insert on attention_events
for each row execute function validate_attention_event_revision_lineage();

-- First-touch visibility is immediate. Storage grows; presentation performs the
-- limiting. The legacy staging table remains for upgrade compatibility but is no
-- longer part of the v2 write path.
create or replace function hot_touch(
  p_topic_key text,p_memory_id uuid,p_summary text default null,p_workstream text default null
) returns text
language plpgsql security definer set search_path=public as $$
declare v_owner text;v_visibility text;v_workstream text;v_summary text;v_content text;
begin
  if p_topic_key is null or p_topic_key !~ '[^[:space:]]' then raise exception 'hot_touch: topic key must contain non-whitespace'; end if;
  select owner,visibility,workstream,content
  into v_owner,v_visibility,v_workstream,v_content
  from memories where id=p_memory_id and status='active';
  if not found then raise exception 'hot_touch: active memory % not found',p_memory_id; end if;
  v_workstream:=coalesce(p_workstream,v_workstream);
  v_summary:=left(coalesce(p_summary,v_content),200);
  update memories set hot_touched=true where id=p_memory_id;
  insert into memory_hot_index(memory_id,topic_key,owner,visibility,summary,workstream,touch_count,last_touched)
  values(p_memory_id,p_topic_key,v_owner,v_visibility,v_summary,v_workstream,1,now())
  on conflict(owner,topic_key) do update set
    memory_id=excluded.memory_id,
    visibility=excluded.visibility,
    summary=excluded.summary,
    workstream=excluded.workstream,
    touch_count=memory_hot_index.touch_count+1,
    last_touched=now();
  delete from memory_hot_staging where owner=v_owner and topic_key=p_topic_key;
  return 'indexed';
end;
$$;

create or replace view memory_hot_ranked with (security_invoker=true) as
select hi.id,hi.memory_id,hi.topic_key,m.owner,m.visibility,hi.summary,
       hi.workstream,hi.touch_count,hi.last_touched,hi.created_at,
       (hi.touch_count::numeric/(1.0+(extract(epoch from (now()-hi.last_touched))/86400.0))) as score
from memory_hot_index hi
join memories m on m.id=hi.memory_id and m.status='active';

create or replace function record_native_memory_attention(p_memory_id uuid)
returns uuid
language plpgsql security definer set search_path=public,extensions as $$
declare v_memory memories%rowtype;v_identity text;v_revision text;v_event uuid;v_topic text;
begin
  select * into v_memory from memories where id=p_memory_id;
  if not found then raise exception 'record_native_memory_attention: memory not found'; end if;
  if v_memory.status<>'active' or v_memory.source_kind not in ('agent','human','manual') then return null; end if;
  v_topic:=attention_workstream_key(v_memory.workstream);
  v_identity:=attention_hash_parts('attention-event/0.2','sovereign-memory','memory','memory_created',v_memory.id::text);
  v_revision:=attention_hash_parts(v_identity,'native-revision:1');
  insert into attention_events(
    contract_version,source_system,source_namespace,source_event_type,source_native_event_id,
    identity_key,revision_key,source_revision,revision_ordinal,memory_id,principal_key,owner,visibility,actor_key,
    workstream_as_of,topic_key_as_of,occurred_at,source_evidence_ref,observation_method,historical_import,metadata
  ) values(
    'attention-event/0.2','sovereign-memory','memory','memory_created',v_memory.id::text,
    v_identity,v_revision,'1',1,v_memory.id,v_memory.owner,v_memory.owner,v_memory.visibility,v_memory.source_agent,
    v_memory.workstream,v_topic,v_memory.created_at,'memory:'||v_memory.id::text,'native_insert_trigger',false,
    jsonb_build_object('source_kind',v_memory.source_kind::text)
  ) on conflict(revision_key) do nothing returning id into v_event;
  if v_event is null then select id into v_event from attention_events where revision_key=v_revision; end if;
  if v_topic is not null then
    insert into attention_event_assignments(event_id,assignment_kind,assignment_key,confidence,assigned_by,assignment_model_version)
    values(v_event,'workstream',v_topic,1.0,'declared-source-field','attention-assignment/0.2')
    on conflict do nothing;
    if coalesce(current_setting('app.attention_explicit_topic',true),'')<>'on' and not v_memory.hot_touched then
      perform hot_touch(v_topic,v_memory.id,left(v_memory.content,200),v_memory.workstream);
    end if;
  end if;
  return v_event;
end;
$$;

create or replace function capture_memory_attention_after_insert()
returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
  perform record_native_memory_attention(new.id);
  return new;
end;
$$;

drop trigger if exists trg_capture_native_memory_attention on memories;
create trigger trg_capture_native_memory_attention
after insert on memories
for each row execute function capture_memory_attention_after_insert();

create or replace function record_native_memory_activation(p_memory_id uuid,p_actor text default null)
returns uuid
language plpgsql security definer set search_path=public,extensions as $$
declare v_memory memories%rowtype;v_identity text;v_revision text;v_event uuid;v_topic text;v_actor text;
begin
  select * into v_memory from memories where id=p_memory_id;
  if not found then raise exception 'record_native_memory_activation: memory not found'; end if;
  if v_memory.status<>'active' or v_memory.source_kind not in ('agent','human','manual') then return null; end if;
  v_actor:=coalesce(nullif(btrim(p_actor),''),v_memory.source_agent,'shared-runtime');
  v_topic:=attention_workstream_key(v_memory.workstream);
  v_identity:=attention_hash_parts('attention-event/0.2','sovereign-memory','memory','memory_activated',v_memory.id::text);
  v_revision:=attention_hash_parts(v_identity,'native-revision:1');
  insert into attention_events(
    contract_version,source_system,source_namespace,source_event_type,source_native_event_id,
    identity_key,revision_key,source_revision,revision_ordinal,memory_id,principal_key,owner,visibility,actor_key,
    workstream_as_of,topic_key_as_of,occurred_at,source_evidence_ref,observation_method,historical_import,metadata
  ) values(
    'attention-event/0.2','sovereign-memory','memory','memory_activated',v_memory.id::text,
    v_identity,v_revision,'1',1,v_memory.id,v_memory.owner,v_memory.owner,v_memory.visibility,v_actor,
    v_memory.workstream,v_topic,now(),'memory:'||v_memory.id::text,'native_status_transition',false,
    jsonb_build_object('source_kind',v_memory.source_kind::text,'transition','proposed_to_active')
  ) on conflict(revision_key) do nothing returning id into v_event;
  if v_event is null then select id into v_event from attention_events where revision_key=v_revision; end if;
  if v_topic is not null then
    insert into attention_event_assignments(event_id,assignment_kind,assignment_key,confidence,assigned_by,assignment_model_version)
    values(v_event,'workstream',v_topic,1.0,'declared-source-field','attention-assignment/0.2')
    on conflict do nothing;
    if not v_memory.hot_touched then perform hot_touch(v_topic,v_memory.id,left(v_memory.content,200),v_memory.workstream); end if;
  end if;
  return v_event;
end;
$$;

create or replace function capture_memory_activation_after_update()
returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
  if old.status='proposed' and new.status='active'
     and new.source_kind in ('agent','human','manual') then
    perform record_native_memory_activation(
      new.id,coalesce(new.metadata->>'promoted_by',current_setting('app.actor_agent',true),new.source_agent)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_capture_memory_activation on memories;
create trigger trg_capture_memory_activation
after update of status on memories
for each row when(old.status is distinct from new.status)
execute function capture_memory_activation_after_update();

create or replace function append_attention_event_revision(
  p_predecessor_event_id uuid,p_source_revision text,p_occurred_at timestamptz,
  p_source_evidence_ref text,p_observation_method text,p_metadata jsonb default '{}'
) returns uuid
language plpgsql security definer set search_path=public,extensions as $$
declare v_old attention_events%rowtype;v_revision_key text;v_existing uuid;v_new uuid;
begin
  if p_source_revision is null or p_source_revision !~ '[^[:space:]]'
     or p_source_evidence_ref is null or p_source_evidence_ref !~ '[^[:space:]]'
     or p_observation_method is null or p_observation_method !~ '[^[:space:]]' then
    raise exception 'revision, evidence and observation method must contain non-whitespace';
  end if;
  select * into v_old from attention_events where id=p_predecessor_event_id;
  if not found then raise exception 'predecessor event not found'; end if;
  v_revision_key:=attention_hash_parts(v_old.identity_key,p_source_revision);
  select id into v_existing from attention_events
  where identity_key=v_old.identity_key and revision_key=v_revision_key;
  if found then return v_existing; end if;
  select * into v_old from attention_events where id=p_predecessor_event_id for update;
  if exists(select 1 from attention_events where supersedes_event_id=v_old.id) then
    raise exception 'predecessor is not the current revision';
  end if;
  insert into attention_events(
    contract_version,source_system,source_namespace,source_event_type,source_native_event_id,
    identity_key,revision_key,source_revision,revision_ordinal,supersedes_event_id,
    memory_id,principal_key,owner,visibility,actor_key,credential_ref,runtime_ref,workstream_as_of,topic_key_as_of,
    occurred_at,source_evidence_ref,observation_method,historical_import,metadata
  ) values(
    v_old.contract_version,v_old.source_system,v_old.source_namespace,v_old.source_event_type,v_old.source_native_event_id,
    v_old.identity_key,v_revision_key,p_source_revision,v_old.revision_ordinal+1,v_old.id,
    v_old.memory_id,v_old.principal_key,v_old.owner,v_old.visibility,v_old.actor_key,v_old.credential_ref,v_old.runtime_ref,
    v_old.workstream_as_of,v_old.topic_key_as_of,p_occurred_at,p_source_evidence_ref,p_observation_method,
    v_old.historical_import,coalesce(p_metadata,'{}')
  ) returning id into v_new;
  insert into attention_event_assignments(
    event_id,assignment_kind,assignment_key,confidence,assigned_by,assignment_model_version,supersedes
  )
  select v_new,assignment_kind,assignment_key,confidence,assigned_by,assignment_model_version,id
  from attention_event_assignments where event_id=v_old.id;
  return v_new;
end;
$$;

-- Keep explicit topic keys compatible while allowing zero-ceremony default
-- workstream orientation for ordinary direct inserts.
create or replace function remember(
  p_content text,p_workstream text,p_topic_key text,p_source_agent text,p_owner text,
  p_summary text default null,p_tags text[] default '{}',p_visibility text default 'shared',
  p_due_date timestamptz default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not exists(select 1 from trusted_agents where agent_id=p_source_agent and active) then
    raise exception 'remember: source_agent % is not a known active trusted agent',p_source_agent;
  end if;
  if p_topic_key is not null and p_topic_key ~ '[^[:space:]]' then
    perform set_config('app.attention_explicit_topic','on',true);
  end if;
  insert into memories(content,workstream,tags,owner,visibility,source_agent,source_kind,due_date,due_status)
  values(p_content,p_workstream,p_tags,p_owner,p_visibility,p_source_agent,'agent',p_due_date,
         case when p_due_date is not null then 'pending' else null end)
  returning id into v_id;
  if p_topic_key is not null and p_topic_key ~ '[^[:space:]]' then
    perform hot_touch(p_topic_key,v_id,coalesce(p_summary,left(p_content,200)),p_workstream);
  end if;
  return v_id;
end;
$$;

create or replace function promote_memory(p_id uuid,p_note text,p_actor text)
returns text
language plpgsql security definer set search_path=public as $$
begin
  if p_actor is null or p_actor !~ '[^[:space:]]' then raise exception 'actor must contain non-whitespace'; end if;
  perform set_config('app.actor_agent',p_actor,true);
  update memories
  set status='active',metadata=metadata||jsonb_build_object('promoted_at',now()::text,'promote_note',p_note,'promoted_by',p_actor)
  where id=p_id and status='proposed';
  if not found then return 'no-proposed-row-with-that-id'; end if;
  return 'promoted';
end;
$$;

create or replace function promote_memory(p_id uuid,p_note text default null)
returns text
language sql security definer set search_path=public as $$
select promote_memory(p_id,p_note,'shared-runtime');
$$;

create or replace function attention_boot_projection_v2(
  p_viewer text,p_char_budget integer default 12000,p_summary_chars integer default 240
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_budget integer:=greatest(coalesce(p_char_budget,12000),512);
  v_summary_limit integer:=greatest(coalesce(p_summary_chars,240),0);
  v_total integer;
  v_topics jsonb:='[]'::jsonb;
  v_candidate_topics jsonb;
  v_candidate jsonb;
  v_payload jsonb;
  v_represented integer:=0;
  r record;
begin
  select count(*) into v_total
  from memory_hot_ranked
  where visibility='shared' or owner=p_viewer;

  for r in
    select topic_key,owner,visibility,summary,workstream,touch_count,score
    from memory_hot_ranked
    where visibility='shared' or owner=p_viewer
    order by case when owner=p_viewer then 0 else 1 end,
             score desc,last_touched desc,topic_key,memory_id
  loop
    v_candidate:=jsonb_build_object(
      'topic_key',r.topic_key,
      'owner',r.owner,
      'visibility',r.visibility,
      'summary',attention_summary_at_word_boundary(r.summary,v_summary_limit),
      'workstream',r.workstream,
      'touch_count',r.touch_count,
      'score',round(r.score::numeric,6)
    );
    v_candidate_topics:=v_topics||jsonb_build_array(v_candidate);
    v_payload:=jsonb_build_object(
      'topics',v_candidate_topics,
      'coverage',jsonb_build_object(
        'requested_char_budget',p_char_budget,
        'effective_char_budget',v_budget,
        'summary_char_limit',v_summary_limit,
        'total_topics',v_total,
        'represented_topics',v_represented+1,
        'omitted_topics',v_total-(v_represented+1),
        'compression','budgeted-prefix',
        'retrieval_handle',jsonb_build_object(
          'view','public.memory_hot_ranked',
          'projection_rpc','public.attention_boot_projection_v2(text,integer,integer)'
        )
      )
    );
    if char_length(v_payload::text)<=v_budget then
      v_topics:=v_candidate_topics;
      v_represented:=v_represented+1;
    else
      exit;
    end if;
  end loop;

  v_payload:=jsonb_build_object(
    'topics',v_topics,
    'coverage',jsonb_build_object(
      'requested_char_budget',p_char_budget,
      'effective_char_budget',v_budget,
      'summary_char_limit',v_summary_limit,
      'total_topics',v_total,
      'represented_topics',v_represented,
      'omitted_topics',v_total-v_represented,
      'compression','budgeted-prefix',
      'retrieval_handle',jsonb_build_object(
        'view','public.memory_hot_ranked',
        'projection_rpc','public.attention_boot_projection_v2(text,integer,integer)'
      )
    )
  );
  v_payload:=jsonb_set(v_payload,'{coverage,rendered_chars}',to_jsonb(char_length(v_payload::text)),true);
  -- rendered_chars changes its own serialized width at most by a few digits. Recompute
  -- until stable; two passes are sufficient for practical envelope sizes.
  v_payload:=jsonb_set(v_payload,'{coverage,rendered_chars}',to_jsonb(char_length(v_payload::text)),true);
  if char_length(v_payload::text)>v_budget then
    raise exception 'attention projection envelope exceeds effective character budget';
  end if;
  return v_payload;
end;
$$;

create or replace function attention_budget_conformance_v2(
  p_viewer text,p_char_budget integer default 12000,p_summary_chars integer default 240
) returns jsonb
language sql stable security definer set search_path=public as $$
with p as (select attention_boot_projection_v2(p_viewer,p_char_budget,p_summary_chars) payload),
m as (select payload,char_length(payload::text) actual_chars,octet_length(convert_to(payload::text,'UTF8')) actual_bytes from p)
select jsonb_build_object(
  'contract_unit','serialized_characters',
  'viewer',p_viewer,
  'requested_char_budget',p_char_budget,
  'effective_char_budget',(payload->'coverage'->>'effective_char_budget')::integer,
  'reported_chars',(payload->'coverage'->>'rendered_chars')::integer,
  'actual_chars',actual_chars,
  'actual_utf8_bytes',actual_bytes,
  'byte_delta',actual_bytes-actual_chars,
  'pass_reported_exact',(payload->'coverage'->>'rendered_chars')::integer=actual_chars,
  'pass_character_budget',actual_chars<=(payload->'coverage'->>'effective_char_budget')::integer,
  'does_not_guarantee',jsonb_build_array('UTF-8 bytes','model tokens')
) from m;
$$;

comment on function attention_boot_projection_v2(text,integer,integer) is
  'Deterministic longest-prefix projection with an exact serialized PostgreSQL character budget. It does not guarantee bytes or model tokens.';

-- Replace the fixed-count boot presentation while retaining the baseline envelope.
create or replace function session_boot(p_viewer text default 'shared')
returns jsonb
language sql stable security definer set search_path=public,extensions as $$
with attention as (select attention_boot_projection_v2(p_viewer,12000,240) payload)
select jsonb_build_object(
  'viewer',p_viewer,
  'hot_topics',(select payload->'topics' from attention),
  'attention_coverage',(select payload->'coverage' from attention),
  'deadlines',(select coalesce(jsonb_agg(jsonb_build_object(
    'content',left(content,100),'owner',owner,'due_date',due_date,'overdue',overdue,'days_until',days_until
  ) order by due_date),'[]'::jsonb) from deadlines_upcoming where visibility='shared' or owner=p_viewer),
  'channel_inbox',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (
    select jsonb_build_object('seq',seq,'from',from_agent,'kind',kind,'subject',subject,'due_at',due_at,'add_to_calendar',add_to_calendar) x
    from household_channel where status='open' and to_principal in (p_viewer,'shared')
    order by due_at asc nulls last,created_at asc limit 25
  ) s),
  'instruction_integrity',(select state from verify_doc_integrity('_system/ai-instructions')),
  'health',jsonb_build_object(
    'memories_visible',(select count(*) from memories where status='active' and (visibility='shared' or owner=p_viewer)),
    'hot_touch_pending',(select count(*) from hot_touch_pending where owner=p_viewer or owner='shared'),
    'attention_invalid_links',(
      (select count(*) from memory_hot_index i where not exists(select 1 from memories m where m.id=i.memory_id and m.status='active'))+
      (select count(*) from memory_hot_staging s where not exists(select 1 from memories m where m.id=s.memory_id and m.status='active'))
    ),
    'attention_events',(select count(*) from attention_events),
    'attention_events_unassigned',(select count(*) from attention_events e where not exists(select 1 from attention_event_assignments a where a.event_id=e.id)),
    'proposed_for_review',(select count(*) from memories where status='proposed' and (visibility='shared' or owner=p_viewer)),
    'channel_open',(select count(*) from household_channel where status='open' and to_principal in (p_viewer,'shared'))
  ),
  'booted_at',now()
);
$$;

revoke all on function attention_hash_parts(text[]) from public;
revoke all on function attention_workstream_key(text) from public;
revoke all on function record_native_memory_attention(uuid) from public;
revoke all on function record_native_memory_activation(uuid,text) from public;
revoke all on function append_attention_event_revision(uuid,text,timestamptz,text,text,jsonb) from public;
revoke all on function attention_boot_projection_v2(text,integer,integer) from public;
revoke all on function attention_budget_conformance_v2(text,integer,integer) from public;
revoke all on function promote_memory(uuid,text,text) from public;
revoke all on function promote_memory(uuid,text) from public;

do $$
declare r text;f text;
begin
  foreach r in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=r) then
      foreach f in array array[
        'record_native_memory_attention(uuid)',
        'record_native_memory_activation(uuid,text)',
        'append_attention_event_revision(uuid,text,timestamptz,text,text,jsonb)',
        'attention_boot_projection_v2(text,integer,integer)',
        'attention_budget_conformance_v2(text,integer,integer)',
        'promote_memory(uuid,text,text)','promote_memory(uuid,text)'
      ] loop execute format('revoke all on function %s from %I',f,r); end loop;
    end if;
  end loop;
  if exists(select 1 from pg_roles where rolname='service_role') then
    foreach f in array array[
      'record_native_memory_attention(uuid)',
      'record_native_memory_activation(uuid,text)',
      'append_attention_event_revision(uuid,text,timestamptz,text,text,jsonb)',
      'attention_boot_projection_v2(text,integer,integer)',
      'attention_budget_conformance_v2(text,integer,integer)',
      'promote_memory(uuid,text,text)','promote_memory(uuid,text)'
    ] loop execute format('grant execute on function %s to service_role',f); end loop;
  end if;
end $$;

-- End of attention-events and projection v2 contract.
