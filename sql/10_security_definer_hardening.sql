-- ============================================================================
-- SOVEREIGN MEMORY :: SECURITY DEFINER TEMP-SHADOW HARDENING V1
-- Issue #57 fix-forward migration. Run after 09_perimeter_refresh.sql.
--
-- Every installed public SECURITY DEFINER routine is recreated from the current
-- package definition with protected relations and authority helpers explicitly
-- schema-qualified. pg_catalog is explicit and pg_temp is explicit last, so an
-- omitted protected qualification fails closed instead of resolving through a
-- caller temporary schema. The exact reviewed inventory is enforced by
-- tests/10_security_definer_temp_shadow.sql and documented in
-- docs/security-definer-inventory.md.
-- ============================================================================

-- Authority-adjacent helpers are hardened too; a qualified call from a
-- SECURITY DEFINER routine must not enter an unsafe helper-local search path.
CREATE OR REPLACE FUNCTION public.attention_fixed_point_chars(p_base_chars integer)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_value integer:=greatest(coalesce(p_base_chars,0),0);
  v_next integer;
  v_i integer;
begin
  for v_i in 1..32 loop
    v_next:=greatest(coalesce(p_base_chars,0),0)+char_length(v_value::text);
    if v_next=v_value then return v_value; end if;
    v_value:=v_next;
  end loop;
  raise exception 'decimal self-length failed to reach a fixed point';
end;
$function$;

CREATE OR REPLACE FUNCTION public.attention_hash_parts(VARIADIC p_parts text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select encode(extensions.digest(convert_to(string_agg(
  case when part is null then '-1:' else octet_length(part)::text||':'||part end,
  '|' order by ord
),'UTF8'),'sha256'),'hex')
from unnest(p_parts) with ordinality as u(part,ord);
$function$;

CREATE OR REPLACE FUNCTION public.attention_set_rendered_chars(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_payload jsonb;
  v_base integer;
  v_fixed integer;
  v_actual integer;
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object'
     or jsonb_typeof(p_payload->'coverage')<>'object' then
    raise exception 'attention_set_rendered_chars requires an object with a coverage object';
  end if;
  v_payload:=jsonb_set(p_payload,'{coverage,rendered_chars}','0'::jsonb,true);
  v_base:=char_length(v_payload::text)-1;
  v_fixed:=public.attention_fixed_point_chars(v_base);
  v_payload:=jsonb_set(v_payload,'{coverage,rendered_chars}',to_jsonb(v_fixed),true);
  v_actual:=char_length(v_payload::text);
  if v_actual<>v_fixed then
    raise exception 'rendered_chars fixed-point assertion failed: reported %, actual %',v_fixed,v_actual;
  end if;
  return v_payload;
end;
$function$;

CREATE OR REPLACE FUNCTION public.attention_summary_at_word_boundary(p_text text, p_max_chars integer)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.attention_workstream_key(p_workstream text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select case
  when p_workstream is null or p_workstream !~ '[^[:space:]]' then null
  else 'workstream/'||trim(both '-' from lower(regexp_replace(btrim(p_workstream),'[^a-zA-Z0-9]+','-','g')))
end;
$function$;

CREATE OR REPLACE FUNCTION public.audit_status_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  if new.status is distinct from old.status then
    insert into public.audit_log(table_name,row_id,action,source_agent,detail)
    values (TG_TABLE_NAME, new.id, 'status_change', new.source_agent,
            jsonb_build_object('from',old.status,'to',new.status));
  end if;
  if TG_TABLE_NAME='memories' then
    if new.due_status is distinct from old.due_status then
      insert into public.audit_log(table_name,row_id,action,source_agent,detail)
      values ('memories', new.id, 'due_status_change', new.source_agent,
              jsonb_build_object('from',old.due_status,'to',new.due_status));
    end if;
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.guard_attention_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  raise exception '% is append-only; % is not permitted',tg_table_name,tg_op;
end;
$function$;

CREATE OR REPLACE FUNCTION public.guard_attention_truncate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  raise exception '% is append-only; TRUNCATE is not permitted',tg_table_name;
end;
$function$;

CREATE OR REPLACE FUNCTION public.guard_hard_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  if coalesce(current_setting('app.allow_delete', true),'off') <> 'on' then
    raise exception 'hard delete blocked on %; supersede instead (admin: set local app.allow_delete=''on'')', TG_TABLE_NAME;
  end if;
  insert into public.audit_log(table_name,row_id,action,detail)
  values (TG_TABLE_NAME, old.id, 'hard_delete', jsonb_build_object('override',true));
  return old;
end; $function$;

CREATE OR REPLACE FUNCTION public.guard_work_lesson_custody_write_path()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  if tg_op='INSERT' then
    if coalesce(current_setting('app.work_lesson_custody_write',true),'')<>'on' then
      raise exception '%: direct insert is not permitted; use sanctioned functions',tg_table_name;
    end if;
    return new;
  end if;
  raise exception '% is append-only; % is not permitted',tg_table_name,tg_op;
end;
$function$;

CREATE OR REPLACE FUNCTION public.guard_work_lesson_truncate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  raise exception '%: TRUNCATE is not permitted',tg_table_name;
end;
$function$;

CREATE OR REPLACE FUNCTION public.guard_work_lessons_write_path()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  if coalesce(current_setting('app.work_lessons_write',true),'')<>'on' then
    raise exception 'work_lessons: direct mutation is not permitted; use sanctioned functions';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.is_canonical_work_lesson_locator(p_kind text, p_locator text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select case p_kind
  when 'coordination_ref' then p_locator ~ '^coordination:[a-z][a-z0-9+.-]*:[^[:space:]]+$'
  when 'memory' then p_locator ~ '^memory:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  when 'migration' then p_locator ~ '^migration:[a-z0-9][a-z0-9_]*$'
  when 'artifact' then p_locator ~ '^artifact:sha256:[0-9a-f]{64}$'
  when 'public_source' then p_locator ~ '^public_source:https://[^[:space:]]+$'
  when 'other_durable_locator' then p_locator ~ '^other:[a-z][a-z0-9+.-]*:[^[:space:]]+$'
  else false
end;
$function$;

CREATE OR REPLACE FUNCTION public.perimeter_acl_violations()
 RETURNS TABLE(boundary text, object_identity text, grantee text, privilege_type text, privilege_source text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
with policy as (
  select public.perimeter_policy_roles('owner') owners,
         public.perimeter_policy_roles('schema_create') schema_creators,
         public.perimeter_policy_roles('function_execute') function_executors,
         public.perimeter_policy_roles('internal_execute') internal_executors
), protected_schemas as (
  select s.*,n.nspowner from public.perimeter_protected_schemas() s join pg_namespace n on n.oid=s.schema_oid
), schema_acl as (
  select s.schema_oid,a.grantee from protected_schemas s
  cross join lateral aclexplode(coalesce((select nspacl from pg_namespace where oid=s.schema_oid),acldefault('n',s.nspowner))) a
  where a.privilege_type='CREATE'
), schema_public as (
  select 'schema'::text,s.schema_name,'PUBLIC'::text,'CREATE'::text,'PUBLIC'::text
  from protected_schemas s
  where exists(select 1 from schema_acl a where a.schema_oid=s.schema_oid and a.grantee=0)
    and not ('PUBLIC'=any(((select schema_creators from policy))::text[]))
), schema_roles as (
  select 'schema'::text,s.schema_name,r.rolname,'CREATE'::text,
         case when exists(select 1 from schema_acl a where a.schema_oid=s.schema_oid and a.grantee=r.oid) then 'direct'
              when exists(select 1 from schema_acl a where a.schema_oid=s.schema_oid and a.grantee=0) then 'PUBLIC'
              else 'inherited' end::text
  from protected_schemas s join pg_roles r on has_schema_privilege(r.oid,s.schema_oid,'CREATE')
  where r.oid<>s.nspowner and not (r.rolname=any(((select owners from policy))::text[]))
    and not (r.rolname=any(((select schema_creators from policy))::text[]))
), authority_functions as (
  select f.*,p.proowner,p.proacl from public.perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid
), function_acl as (
  select f.function_oid,a.grantee from authority_functions f
  cross join lateral aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a
  where a.privilege_type='EXECUTE'
), function_public as (
  select case when f.is_internal then 'internal_function' else 'authority_function' end,
         f.function_identity,'PUBLIC'::text,'EXECUTE'::text,'PUBLIC'::text
  from authority_functions f
  where exists(select 1 from function_acl a where a.function_oid=f.function_oid and a.grantee=0)
    and not ('PUBLIC'=any((case when f.is_internal then (select internal_executors from policy) else (select function_executors from policy) end)::text[]))
), function_roles as (
  select case when f.is_internal then 'internal_function' else 'authority_function' end,
         f.function_identity,r.rolname,'EXECUTE'::text,
         case when exists(select 1 from function_acl a where a.function_oid=f.function_oid and a.grantee=r.oid) then 'direct'
              when exists(select 1 from function_acl a where a.function_oid=f.function_oid and a.grantee=0) then 'PUBLIC'
              else 'inherited' end::text
  from authority_functions f join pg_roles r on has_function_privilege(r.oid,f.function_oid,'EXECUTE')
  where r.oid<>f.proowner and not (r.rolname=any(((select owners from policy))::text[]))
    and not (r.rolname=any((case when f.is_internal then (select internal_executors from policy) else (select function_executors from policy) end)::text[]))
), default_targets as (
  select s.schema_oid,s.schema_name,r.oid nspowner,r.rolname owner_name,x.objtype,x.boundary,x.privilege
  from protected_schemas s cross join policy p
  cross join lateral unnest(p.owners) owner_name
  join pg_roles r on r.rolname=owner_name
  cross join (values('r'::"char",'default_table'::text,'ALL'::text),('S'::"char",'default_sequence','ALL'),('f'::"char",'default_function','EXECUTE')) x(objtype,boundary,privilege)
), default_entries as (
  -- PostgreSQL's built-in function default grants EXECUTE to PUBLIC even when
  -- no pg_default_acl row exists. Treat both that baseline and explicit catalog
  -- rows as owner-global policy; neither may be repaired schema-locally.
  select t.*,a.grantee,a.privilege_type,'global'::text default_scope
  from default_targets t
  cross join lateral aclexplode(coalesce(
    (select d.defaclacl from pg_default_acl d where d.defaclrole=t.nspowner and d.defaclnamespace=0 and d.defaclobjtype=t.objtype),
    acldefault(t.objtype,t.nspowner))) a
  union all
  select t.*,a.grantee,a.privilege_type,'schema'::text
  from default_targets t
  join pg_default_acl d on d.defaclrole=t.nspowner and d.defaclnamespace=t.schema_oid and d.defaclobjtype=t.objtype
  cross join lateral aclexplode(d.defaclacl) a
), default_public as (
  select case when d.default_scope='global' then 'global_'||d.boundary else d.boundary end,
         d.owner_name||' '||d.default_scope||' for '||d.schema_name,'PUBLIC'::text,d.privilege_type,'PUBLIC'::text
  from default_entries d where d.grantee=0
), default_roles as (
  select case when d.default_scope='global' then 'global_'||d.boundary else d.boundary end,
         d.owner_name||' '||d.default_scope||' for '||d.schema_name,r.rolname,d.privilege_type,'direct'::text
  from default_entries d join pg_roles r on r.oid=d.grantee where d.grantee<>d.nspowner
)
select * from schema_public
union all select * from schema_roles
union all select * from function_public
union all select * from function_roles
union all select * from default_public
union all select * from default_roles;
$function$;

CREATE OR REPLACE FUNCTION public.perimeter_authority_functions()
 RETURNS TABLE(function_oid oid, function_identity text, is_internal boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select p.oid,format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),r.is_internal
from public.perimeter_authority_function_registry r
join pg_proc p on p.oid=to_regprocedure(r.function_identity)
join pg_namespace n on n.oid=p.pronamespace;
$function$;

CREATE OR REPLACE FUNCTION public.perimeter_policy_roles(p_kind text)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_roles text[];
begin
  select case p_kind
    when 'owner' then owner_roles
    when 'schema_create' then schema_create_roles
    when 'function_execute' then function_execute_roles
    when 'internal_execute' then internal_execute_roles
    else null
  end into v_roles from public.perimeter_acl_policy where singleton;
  if v_roles is null then
    raise exception 'PERIMETER FAIL: unknown perimeter policy kind %',p_kind;
  end if;
  return v_roles;
end;
$function$;

CREATE OR REPLACE FUNCTION public.perimeter_protected_schemas()
 RETURNS TABLE(schema_oid oid, schema_name text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select n.oid,n.nspname
from public.perimeter_protected_schema_registry r
join pg_namespace n on n.nspname=r.schema_name;
$function$;

CREATE OR REPLACE FUNCTION public.perimeter_setting_roles(p_setting text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select case p_setting
  when 'sovereign_memory.perimeter_allowed_owner_roles' then owner_roles
  when 'sovereign_memory.perimeter_allowed_schema_create_roles' then schema_create_roles
  when 'sovereign_memory.perimeter_allowed_function_execute_roles' then function_execute_roles
  when 'sovereign_memory.perimeter_allowed_internal_execute_roles' then internal_execute_roles
  else array[]::text[]
end
from public.perimeter_acl_policy where singleton;
$function$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$ begin new.updated_at := now(); return new; end; $function$;

CREATE OR REPLACE FUNCTION public.validate_attention_event_revision_lineage()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_previous public.attention_events%ROWTYPE;
begin
  if new.revision_ordinal=1 then
    if new.supersedes_event_id is not null then raise exception 'revision 1 cannot supersede another event'; end if;
    return new;
  end if;
  select * into v_previous from public.attention_events where id=new.supersedes_event_id;
  if not found then raise exception 'superseded event not found'; end if;
  if v_previous.identity_key<>new.identity_key then raise exception 'revision identity mismatch'; end if;
  if v_previous.revision_ordinal<>new.revision_ordinal-1 then raise exception 'revision ordinal must follow predecessor'; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.accept_work_lesson(p_id uuid, p_accepted_by text, p_authority_ref text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_row public.work_lessons%ROWTYPE;
begin
  if p_accepted_by is null or p_accepted_by !~ '[^[:space:]]'
     or p_authority_ref is null or p_authority_ref !~ '[^[:space:]]' then
    raise exception 'acceptor and authority reference must contain non-whitespace';
  end if;
  select * into v_row from public.work_lessons
  where id=p_id and status='active' and authority_state='proposed' for update;
  if not found then raise exception 'no active proposed lesson'; end if;
  if v_row.kind in ('rule','prohibition') and not exists(
    select 1 from public.work_lesson_evidence_current where lesson_id=v_row.id and resolution_state='resolvable'
  ) then raise exception 'behavioral lesson requires current resolvable evidence'; end if;
  perform set_config('app.work_lessons_write','on',true);
  perform set_config('app.work_lesson_custody_write','on',true);
  if v_row.supersedes is not null then
    update public.work_lessons set status='superseded'
    where id=v_row.supersedes and status='active' and authority_state='accepted';
    if not found then raise exception 'predecessor is not active and accepted'; end if;
    insert into public.work_lesson_events(lesson_id,event_type,actor,authority_ref,details)
    values(v_row.supersedes,'superseded',p_accepted_by,p_authority_ref,jsonb_build_object('successor',v_row.id));
  end if;
  update public.work_lessons
  set authority_state='accepted',accepted_by=p_accepted_by,accepted_at=now(),authority_ref=p_authority_ref
  where id=v_row.id;
  insert into public.work_lesson_events(lesson_id,event_type,actor,authority_ref)
  values(v_row.id,'accepted',p_accepted_by,p_authority_ref);
  return v_row.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.append_attention_event_revision(p_predecessor_event_id uuid, p_source_revision text, p_occurred_at timestamp with time zone, p_source_evidence_ref text, p_observation_method text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_requested public.attention_events%ROWTYPE;
  v_tip public.attention_events%ROWTYPE;
  v_revision_key text;
  v_existing uuid;
  v_new uuid;
  v_actor text:=coalesce(nullif(current_setting('app.actor_agent',true),''),'shared-runtime');
  v_credential text:=nullif(current_setting('app.credential_ref',true),'');
  v_runtime text:=coalesce(nullif(current_setting('app.runtime_ref',true),''),'shared-runtime');
  v_metadata jsonb;
begin
  if p_source_revision is null or p_source_revision !~ '[^[:space:]]'
     or p_occurred_at is null
     or p_source_evidence_ref is null or p_source_evidence_ref !~ '[^[:space:]]'
     or p_observation_method is null or p_observation_method !~ '[^[:space:]]' then
    raise exception 'revision, occurrence time, evidence and observation method are required';
  end if;
  select * into v_requested from public.attention_events where id=p_predecessor_event_id;
  if not found then raise exception 'predecessor event not found'; end if;
  v_revision_key:=public.attention_hash_parts(v_requested.identity_key,p_source_revision);
  perform pg_advisory_xact_lock(hashtextextended(v_requested.identity_key,0));
  select id into v_existing from public.attention_events
  where identity_key=v_requested.identity_key and revision_key=v_revision_key;
  if found then return v_existing; end if;
  select * into v_tip from public.attention_events
  where identity_key=v_requested.identity_key
  order by revision_ordinal desc,recorded_at desc,id
  limit 1 for update;
  if v_tip.id is distinct from p_predecessor_event_id then
    raise exception 'predecessor is not the current revision';
  end if;
  v_metadata:=coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
    'attribution_assurance',case when v_credential is null then 'shared-runtime-assertion' else 'credential-asserted' end
  );
  insert into public.attention_events(
    contract_version,source_system,source_namespace,source_event_type,source_native_event_id,
    identity_key,revision_key,source_revision,revision_ordinal,supersedes_event_id,
    memory_id,principal_key,owner,visibility,actor_key,credential_ref,runtime_ref,
    workstream_as_of,topic_key_as_of,occurred_at,source_evidence_ref,observation_method,historical_import,metadata
  ) values(
    'attention-event/0.3',v_tip.source_system,v_tip.source_namespace,v_tip.source_event_type,v_tip.source_native_event_id,
    v_tip.identity_key,v_revision_key,p_source_revision,v_tip.revision_ordinal+1,v_tip.id,
    v_tip.memory_id,v_tip.principal_key,v_tip.owner,v_tip.visibility,v_actor,v_credential,v_runtime,
    v_tip.workstream_as_of,v_tip.topic_key_as_of,p_occurred_at,p_source_evidence_ref,p_observation_method,
    v_tip.historical_import,v_metadata
  ) on conflict(revision_key) do nothing returning id into v_new;
  if v_new is null then
    select id into v_new from public.attention_events where revision_key=v_revision_key;
    return v_new;
  end if;
  insert into public.attention_event_assignments(
    event_id,assignment_kind,assignment_key,confidence,assigned_by,assignment_model_version,supersedes
  )
  select v_new,assignment_kind,assignment_key,confidence,assigned_by,assignment_model_version,id
  from public.attention_event_assignments where event_id=v_tip.id;
  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.append_work_lesson_evidence(p_lesson_id uuid, p_evidence_kind text, p_locator text, p_source_authority text, p_actor text, p_resolution_state text DEFAULT 'unverified'::text, p_integrity_hash text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_id uuid;
begin
  if p_actor is null or p_actor !~ '[^[:space:]]'
     or p_source_authority is null or p_source_authority !~ '[^[:space:]]' then
    raise exception 'actor and source authority must contain non-whitespace';
  end if;
  if p_resolution_state not in ('unverified','resolvable','invalid') then raise exception 'invalid resolution state'; end if;
  if not public.is_canonical_work_lesson_locator(p_evidence_kind,p_locator) then raise exception 'evidence locator must be canonical'; end if;
  perform 1 from public.work_lessons where id=p_lesson_id;
  if not found then raise exception 'lesson not found'; end if;
  if exists(select 1 from public.work_lesson_evidence_current where lesson_id=p_lesson_id and evidence_kind=p_evidence_kind and locator=p_locator) then
    raise exception 'current evidence already exists';
  end if;
  perform set_config('app.work_lesson_custody_write','on',true);
  insert into public.work_lesson_evidence(lesson_id,evidence_kind,locator,source_authority,integrity_hash,resolution_state,created_by)
  values(p_lesson_id,p_evidence_kind,p_locator,p_source_authority,p_integrity_hash,p_resolution_state,p_actor)
  returning id into v_id;
  insert into public.work_lesson_events(lesson_id,event_type,actor,details)
  values(p_lesson_id,'evidence_added',p_actor,jsonb_build_object('evidence_id',v_id,'locator',p_locator,'resolution_state',p_resolution_state));
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.assert_perimeter_closed()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_bad text;v_item text;v_owner text[]:=public.perimeter_policy_roles('owner');
  v_tables text[]:=array['work_lessons','work_lesson_evidence','work_lesson_events','attention_events','attention_event_assignments'];
begin
  with control_tables as (
    select c.oid,c.relname,c.relowner,r.rolname owner_name
    from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_roles r on r.oid=c.relowner
    where n.nspname='public'
      and c.relname=any(array['perimeter_acl_policy','perimeter_protected_schema_registry','perimeter_authority_function_registry'])
  ), violations as (
    select 'public.'||relname object_identity,owner_name grantee,'OWNER'::text privilege_type,'owner'::text privilege_source
    from control_tables where relowner<>current_user::regrole
    union all
    select 'public.'||c.relname,r.rolname,p.privilege,
      case when exists(
        select 1 from pg_class x cross join lateral aclexplode(coalesce(x.relacl,acldefault('r',x.relowner))) a
        where x.oid=c.oid and a.grantee=r.oid and a.privilege_type=p.privilege
      ) then 'direct' else 'inherited_or_PUBLIC' end
    from control_tables c cross join pg_roles r
    cross join (values('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) p(privilege)
    where r.oid<>c.relowner
      and not (r.rolname like 'pg\_%' escape '\' and not r.rolcanlogin)
      and has_table_privilege(r.oid,c.oid,p.privilege)
    union all
    select 'public.'||c.relname,r.rolname,
      p.privilege||'('||att.attname||')',
      case when exists(
        select 1 from pg_attribute x cross join lateral aclexplode(x.attacl) a
        where x.attrelid=c.oid and x.attnum=att.attnum
          and a.grantee=r.oid and a.privilege_type=p.privilege
      ) then 'direct' else 'inherited_or_PUBLIC' end
    from control_tables c
    join pg_attribute att on att.attrelid=c.oid and att.attnum>0 and not att.attisdropped
    cross join pg_roles r
    cross join (values('SELECT'),('INSERT'),('UPDATE'),('REFERENCES')) p(privilege)
    where r.oid<>c.relowner
      and not (r.rolname like 'pg\_%' escape '\' and not r.rolcanlogin)
      and has_column_privilege(r.oid,c.oid,att.attnum,p.privilege)
  )
  select string_agg(format('durable_control_table %s %s %s via %s',grantee,privilege_type,object_identity,privilege_source),', ' order by object_identity,grantee,privilege_type)
    into v_bad from violations;
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: durable control-table ownership/effective ACL drift: %',v_bad;
  end if;

  select string_agg(format('%s %s %s %s via %s',boundary,grantee,privilege_type,object_identity,privilege_source),', ' order by boundary,object_identity,grantee)
    into v_bad from public.perimeter_acl_violations() where boundary like 'global_default_%';
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: owner-global default ACLs: operator action required (global grants cannot be negated schema-locally): %',v_bad;
  end if;

  select string_agg(format('%s %s %s %s via %s',boundary,grantee,privilege_type,object_identity,privilege_source),', ' order by boundary,object_identity,grantee)
    into v_bad from public.perimeter_acl_violations() where boundary not like 'global_default_%';
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected effective ACL grantees: %',v_bad; end if;

  select string_agg(format('%s owner=%s',s.schema_name,r.rolname),', ' order by s.schema_name) into v_bad
  from public.perimeter_protected_schemas() s join pg_namespace n on n.oid=s.schema_oid join pg_roles r on r.oid=n.nspowner
  where not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected protected-schema owner: %',v_bad; end if;

  select string_agg(c.relname,', ' order by c.relname) into v_bad from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=any(v_tables) and(not c.relrowsecurity or not c.relforcerowsecurity);
  if v_bad is not null then raise exception 'PERIMETER FAIL: protected tables lack RLS/FORCE RLS: %',v_bad; end if;

  select string_agg(c.relname||' owner='||r.rolname,', ' order by c.relname) into v_bad
  from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_roles r on r.oid=c.relowner
  where n.nspname='public' and c.relname=any(v_tables) and not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected protected-table owner: %',v_bad; end if;

  select string_agg(f.function_identity||' owner='||r.rolname,', ' order by f.function_identity) into v_bad
  from public.perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid join pg_roles r on r.oid=p.proowner
  where not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected authority-function owner: %',v_bad; end if;

  select string_agg(grantee||':'||table_name||':'||privilege_type,', ' order by grantee,table_name,privilege_type) into v_bad
  from information_schema.role_table_grants where table_schema='public' and table_name=any(v_tables)
    and grantee<>all(v_owner) and grantee<>'service_role';
  if v_bad is not null then raise exception 'PERIMETER FAIL: stale protected-table grantees: %',v_bad; end if;

  if exists(select 1 from pg_roles where rolname='service_role') then
    foreach v_item in array v_tables loop
      if has_table_privilege('service_role',format('public.%I',v_item),'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'PERIMETER FAIL: service_role has direct mutation on %',v_item;
      end if;
    end loop;
    if exists(select 1 from pg_roles where rolname='pg_write_all_data') and pg_has_role('service_role','pg_write_all_data','MEMBER') then
      raise exception 'PERIMETER FAIL: service_role inherits pg_write_all_data';
    end if;
  end if;

  -- Audit the complete installed SECURITY DEFINER inventory, including this
  -- checker. Empty search_path is safest. A retained path is accepted only in
  -- one of the declared trusted orders, with pg_temp present exactly once and
  -- last. This rejects omission, misordering, $user, and untrusted schemas.
  select string_agg(format('%I.%I(%s) path=%s',n.nspname,p.proname,
           oidvectortypes(p.proargtypes),coalesce(cfg.path,'<missing>')),
           ', ' order by n.nspname,p.proname,oidvectortypes(p.proargtypes))
    into v_bad
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  left join lateral (
    select x path
    from unnest(p.proconfig) x
    where x like 'search_path=%'
  ) cfg on true
  where p.prosecdef and n.nspname='public'
    and (cfg.path is null or cfg.path not in (
      'search_path=',
      'search_path=pg_catalog, pg_temp',
      'search_path=pg_catalog, extensions, pg_temp',
      'search_path=pg_catalog, public, pg_temp'
    ));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unsafe or missing function search_path: %',v_bad; end if;

  return 'perimeter OK: bounded schema/function/default ACLs, owners, RLS/FORCE, runtime mutation, inheritance, PUBLIC and SECURITY DEFINER search paths verified';
end;
$function$;

CREATE OR REPLACE FUNCTION public.attention_boot_projection_v2(p_viewer text, p_char_budget integer DEFAULT 12000, p_summary_chars integer DEFAULT 240)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
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
  from public.memory_hot_ranked
  where visibility='shared' or owner=p_viewer;
  for r in
    select topic_key,owner,visibility,summary,workstream,touch_count,score
    from public.memory_hot_ranked
    where visibility='shared' or owner=p_viewer
    order by case when owner=p_viewer then 0 else 1 end,
             score desc,last_touched desc,topic_key,memory_id
  loop
    v_candidate:=jsonb_build_object(
      'topic_key',r.topic_key,'owner',r.owner,'visibility',r.visibility,
      'summary',public.attention_summary_at_word_boundary(r.summary,v_summary_limit),
      'workstream',r.workstream,'touch_count',r.touch_count,'score',round(r.score::numeric,6)
    );
    v_candidate_topics:=v_topics||jsonb_build_array(v_candidate);
    v_payload:=public.attention_set_rendered_chars(jsonb_build_object(
      'topics',v_candidate_topics,
      'coverage',jsonb_build_object(
        'requested_char_budget',p_char_budget,'effective_char_budget',v_budget,
        'rendered_chars',0,'summary_char_limit',v_summary_limit,'total_topics',v_total,
        'represented_topics',v_represented+1,'omitted_topics',v_total-(v_represented+1),
        'compression','budgeted-prefix',
        'retrieval_handle',jsonb_build_object(
          'view','public.memory_hot_ranked',
          'projection_rpc','public.attention_boot_projection_v2(text,integer,integer)'
        )
      )
    ));
    if char_length(v_payload::text)<=v_budget then
      v_topics:=v_candidate_topics;v_represented:=v_represented+1;
    else exit;
    end if;
  end loop;
  v_payload:=public.attention_set_rendered_chars(jsonb_build_object(
    'topics',v_topics,
    'coverage',jsonb_build_object(
      'requested_char_budget',p_char_budget,'effective_char_budget',v_budget,
      'rendered_chars',0,'summary_char_limit',v_summary_limit,'total_topics',v_total,
      'represented_topics',v_represented,'omitted_topics',v_total-v_represented,
      'compression',case when v_total=0 then 'empty' when v_total=v_represented then 'complete' else 'budgeted-prefix' end,
      'retrieval_handle',jsonb_build_object(
        'view','public.memory_hot_ranked',
        'projection_rpc','public.attention_boot_projection_v2(text,integer,integer)'
      )
    )
  ));
  if char_length(v_payload::text)>v_budget then
    raise exception 'attention projection envelope exceeds effective character budget';
  end if;
  return v_payload;
end;
$function$;

CREATE OR REPLACE FUNCTION public.attention_budget_conformance_v2(p_viewer text, p_char_budget integer DEFAULT 12000, p_summary_chars integer DEFAULT 240)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
with p as (select public.attention_boot_projection_v2(p_viewer,p_char_budget,p_summary_chars) payload),
m as (select payload,char_length(payload::text) actual_chars,octet_length(convert_to(payload::text,'UTF8')) actual_bytes from p)
select jsonb_build_object(
  'contract_unit','serialized_characters','viewer',p_viewer,
  'requested_char_budget',p_char_budget,
  'effective_char_budget',(payload->'coverage'->>'effective_char_budget')::integer,
  'reported_chars',(payload->'coverage'->>'rendered_chars')::integer,
  'actual_chars',actual_chars,'actual_utf8_bytes',actual_bytes,'byte_delta',actual_bytes-actual_chars,
  'pass_reported_exact',(payload->'coverage'->>'rendered_chars')::integer=actual_chars,
  'pass_character_budget',actual_chars<=(payload->'coverage'->>'effective_char_budget')::integer,
  'does_not_guarantee',jsonb_build_array('UTF-8 bytes','model tokens')
) from m;
$function$;

CREATE OR REPLACE FUNCTION public.bless_doc(p_path text, p_note text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_hash text;
begin
  v_hash := public.current_doc_hash(p_path);
  if v_hash is null then return 'no-active-doc-at-path'; end if;
  insert into public.doc_integrity(path, blessed_sha256, blessed_at, blessed_note)
  values (p_path, v_hash, now(), p_note)
  on conflict (path) do update
    set blessed_sha256=excluded.blessed_sha256, blessed_at=now(), blessed_note=excluded.blessed_note;
  return 'blessed:'||v_hash;
end; $function$;

CREATE OR REPLACE FUNCTION public.capture_memory_activation_after_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_identity text;
  v_source_revision text:='native-revision:1';
  v_revision text;
  v_event uuid;
  v_topic text;
  v_actor text;
  v_credential text:=nullif(current_setting('app.credential_ref',true),'');
  v_runtime text:=coalesce(nullif(current_setting('app.runtime_ref',true),''),'shared-runtime');
begin
  if old.status<>'proposed' or new.status<>'active'
     or new.source_kind not in ('agent','human','manual') then return new; end if;
  v_actor:=coalesce(nullif(new.metadata->>'promoted_by',''),nullif(current_setting('app.actor_agent',true),''),new.source_agent,'shared-runtime');
  v_topic:=public.attention_workstream_key(new.workstream);
  v_identity:=public.attention_hash_parts('attention-event/0.3','sovereign-memory','memory','memory_activated',new.id::text);
  v_revision:=public.attention_hash_parts(v_identity,v_source_revision);
  insert into public.attention_events(
    contract_version,source_system,source_namespace,source_event_type,source_native_event_id,
    identity_key,revision_key,source_revision,revision_ordinal,memory_id,principal_key,owner,visibility,
    actor_key,credential_ref,runtime_ref,workstream_as_of,topic_key_as_of,occurred_at,
    source_evidence_ref,observation_method,historical_import,metadata
  ) values(
    'attention-event/0.3','sovereign-memory','memory','memory_activated',new.id::text,
    v_identity,v_revision,v_source_revision,1,new.id,new.owner,new.owner,new.visibility,
    v_actor,v_credential,v_runtime,new.workstream,v_topic,clock_timestamp(),
    'memory:'||new.id::text,'native_status_transition',false,
    jsonb_build_object(
      'source_kind',new.source_kind::text,'transition','proposed_to_active',
      'attribution_assurance',case when v_credential is null then 'shared-runtime-assertion' else 'credential-asserted' end
    )
  ) on conflict(revision_key) do nothing returning id into v_event;
  if v_event is null then select id into v_event from public.attention_events where revision_key=v_revision; end if;
  if v_topic is not null and v_event is not null then
    insert into public.attention_event_assignments(event_id,assignment_kind,assignment_key,confidence,assigned_by,assignment_model_version)
    values(v_event,'workstream',v_topic,1.0,'declared-source-field','attention-assignment/0.3')
    on conflict do nothing;
    if not new.hot_touched then perform public.hot_touch(v_topic,new.id,left(new.content,200),new.workstream); end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.capture_memory_attention_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_identity text;
  v_source_revision text:='native-revision:1';
  v_revision text;
  v_event uuid;
  v_topic text;
  v_credential text:=nullif(current_setting('app.credential_ref',true),'');
  v_runtime text:=coalesce(nullif(current_setting('app.runtime_ref',true),''),'shared-runtime');
begin
  if new.status<>'active' or new.source_kind not in ('agent','human','manual') then return new; end if;
  v_topic:=public.attention_workstream_key(new.workstream);
  v_identity:=public.attention_hash_parts('attention-event/0.3','sovereign-memory','memory','memory_created',new.id::text);
  v_revision:=public.attention_hash_parts(v_identity,v_source_revision);
  insert into public.attention_events(
    contract_version,source_system,source_namespace,source_event_type,source_native_event_id,
    identity_key,revision_key,source_revision,revision_ordinal,memory_id,principal_key,owner,visibility,
    actor_key,credential_ref,runtime_ref,workstream_as_of,topic_key_as_of,occurred_at,
    source_evidence_ref,observation_method,historical_import,metadata
  ) values(
    'attention-event/0.3','sovereign-memory','memory','memory_created',new.id::text,
    v_identity,v_revision,v_source_revision,1,new.id,new.owner,new.owner,new.visibility,
    new.source_agent,v_credential,v_runtime,new.workstream,v_topic,new.created_at,
    'memory:'||new.id::text,'native_insert_trigger',false,
    jsonb_build_object(
      'source_kind',new.source_kind::text,
      'attribution_assurance',case when v_credential is null then 'shared-runtime-assertion' else 'credential-asserted' end
    )
  ) on conflict(revision_key) do nothing returning id into v_event;
  if v_event is null then select id into v_event from public.attention_events where revision_key=v_revision; end if;
  if v_topic is not null and v_event is not null then
    insert into public.attention_event_assignments(event_id,assignment_kind,assignment_key,confidence,assigned_by,assignment_model_version)
    values(v_event,'workstream',v_topic,1.0,'declared-source-field','attention-assignment/0.3')
    on conflict do nothing;
    if coalesce(current_setting('app.attention_explicit_topic',true),'')<>'on' and not new.hot_touched then
      perform public.hot_touch(v_topic,new.id,left(new.content,200),new.workstream);
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.channel_complete(p_seq bigint, p_status text DEFAULT 'done'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  if p_status not in ('done','dismissed') then
    raise exception 'channel_complete: status must be done or dismissed'; end if;
  update public.household_channel set status=p_status, completed_at=now() where seq=p_seq;
  if not found then raise exception 'channel_complete: seq % not found', p_seq; end if;
  return p_status;
end; $function$;

CREATE OR REPLACE FUNCTION public.channel_send(p_from_agent text, p_to_principal text, p_kind text, p_subject text, p_body text DEFAULT NULL::text, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_add_to_calendar boolean DEFAULT false, p_re_seq bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_seq bigint;
begin
  if not exists (select 1 from public.trusted_agents where agent_id=p_from_agent and active) then
    raise exception 'channel_send: unknown/inactive from_agent %', p_from_agent; end if;
  insert into public.household_channel(from_agent,to_principal,kind,subject,body,due_at,add_to_calendar,re_seq)
  values (p_from_agent,p_to_principal,p_kind,p_subject,p_body,p_due_at,p_add_to_calendar,p_re_seq)
  returning seq into v_seq;
  return v_seq;
end; $function$;

CREATE OR REPLACE FUNCTION public.correct_work_lesson_evidence(p_evidence_id uuid, p_evidence_kind text, p_locator text, p_source_authority text, p_actor text, p_correction_reason text, p_resolution_state text DEFAULT 'unverified'::text, p_integrity_hash text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_old public.work_lesson_evidence%ROWTYPE;v_new uuid;
begin
  if p_actor is null or p_actor !~ '[^[:space:]]'
     or p_source_authority is null or p_source_authority !~ '[^[:space:]]'
     or p_correction_reason is null or p_correction_reason !~ '[^[:space:]]' then
    raise exception 'actor, source authority and correction reason must contain non-whitespace';
  end if;
  if p_resolution_state not in ('unverified','resolvable','invalid') then raise exception 'invalid resolution state'; end if;
  if not public.is_canonical_work_lesson_locator(p_evidence_kind,p_locator) then raise exception 'evidence locator must be canonical'; end if;
  select * into v_old from public.work_lesson_evidence where id=p_evidence_id for update;
  if not found then raise exception 'evidence not found'; end if;
  if exists(select 1 from public.work_lesson_evidence where supersedes=v_old.id) then raise exception 'evidence is not current'; end if;
  perform set_config('app.work_lesson_custody_write','on',true);
  insert into public.work_lesson_evidence(
    lesson_id,evidence_kind,locator,source_authority,integrity_hash,resolution_state,created_by,supersedes,correction_reason
  ) values(
    v_old.lesson_id,p_evidence_kind,p_locator,p_source_authority,p_integrity_hash,p_resolution_state,p_actor,v_old.id,p_correction_reason
  ) returning id into v_new;
  insert into public.work_lesson_events(lesson_id,event_type,actor,details)
  values(v_old.lesson_id,'evidence_corrected',p_actor,jsonb_build_object('old_evidence_id',v_old.id,'new_evidence_id',v_new,'locator',p_locator,'reason',p_correction_reason));
  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.current_doc_hash(p_path text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$ select encode(extensions.digest(content,'sha256'),'hex')
      from public.wiki_pages where path=p_path and status='active'; $function$;

CREATE OR REPLACE FUNCTION public.hot_touch(p_topic_key text, p_memory_id uuid, p_summary text DEFAULT NULL::text, p_workstream text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_owner text;v_visibility text;v_workstream text;v_summary text;v_content text;
begin
  if p_topic_key is null or p_topic_key !~ '[^[:space:]]' then
    raise exception 'hot_touch: topic key must contain non-whitespace';
  end if;
  select owner,visibility,workstream,content
  into v_owner,v_visibility,v_workstream,v_content
  from public.memories where id=p_memory_id and status='active';
  if not found then raise exception 'hot_touch: active memory % not found',p_memory_id; end if;
  v_workstream:=coalesce(p_workstream,v_workstream);
  v_summary:=left(coalesce(p_summary,v_content),200);
  update public.memories set hot_touched=true where id=p_memory_id;
  insert into public.memory_hot_index as mhi(memory_id,topic_key,owner,visibility,summary,workstream,touch_count,last_touched)
  values(p_memory_id,p_topic_key,v_owner,v_visibility,v_summary,v_workstream,1,now())
  on conflict(owner,topic_key) do update set
    memory_id=excluded.memory_id,visibility=excluded.visibility,summary=excluded.summary,
    workstream=excluded.workstream,touch_count=mhi.touch_count+1,last_touched=now();
  delete from public.memory_hot_staging where owner=v_owner and topic_key=p_topic_key;
  return 'indexed';
end;
$function$;

CREATE OR REPLACE FUNCTION public.promote_memory(p_id uuid, p_note text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select public.promote_memory(p_id,p_note,'shared-runtime');
$function$;

CREATE OR REPLACE FUNCTION public.promote_memory(p_id uuid, p_note text, p_actor text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  if p_actor is null or p_actor !~ '[^[:space:]]' then raise exception 'actor must contain non-whitespace'; end if;
  perform set_config('app.actor_agent',p_actor,true);
  update public.memories
  set status='active',metadata=metadata||jsonb_build_object('promoted_at',now()::text,'promote_note',p_note,'promoted_by',p_actor)
  where id=p_id and status='proposed';
  if not found then return 'no-proposed-row-with-that-id'; end if;
  return 'promoted';
end;
$function$;

CREATE OR REPLACE FUNCTION public.propose_lesson_supersession(p_predecessor_id uuid, p_claim text, p_detail text, p_evidence_kind text, p_evidence_locator text, p_source_authority text, p_created_by text, p_resolution_state text DEFAULT 'unverified'::text, p_integrity_hash text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_old public.work_lessons%ROWTYPE;v_new uuid;
begin
  select * into v_old from public.work_lessons
  where id=p_predecessor_id and status='active' and authority_state='accepted' for update;
  if not found then raise exception 'no active accepted predecessor'; end if;
  if p_claim is null or p_claim !~ '[^[:space:]]' then raise exception 'claim must contain non-whitespace'; end if;
  if p_created_by is null or p_created_by !~ '[^[:space:]]'
     or p_source_authority is null or p_source_authority !~ '[^[:space:]]' then
    raise exception 'creator and source authority must contain non-whitespace';
  end if;
  if p_resolution_state not in ('unverified','resolvable','invalid') then raise exception 'invalid resolution state'; end if;
  if not public.is_canonical_work_lesson_locator(p_evidence_kind,p_evidence_locator) then raise exception 'evidence locator must be canonical'; end if;
  perform set_config('app.work_lessons_write','on',true);
  perform set_config('app.work_lesson_custody_write','on',true);
  insert into public.work_lessons(kind,claim,detail,applies_to,status,supersedes,authority_state,created_by)
  values(v_old.kind,p_claim,p_detail,v_old.applies_to,'active',v_old.id,'proposed',p_created_by)
  returning id into v_new;
  insert into public.work_lesson_evidence(lesson_id,evidence_kind,locator,source_authority,integrity_hash,resolution_state,created_by)
  values(v_new,p_evidence_kind,p_evidence_locator,p_source_authority,p_integrity_hash,p_resolution_state,p_created_by);
  insert into public.work_lesson_events(lesson_id,event_type,actor,details)
  values(v_new,'proposed',p_created_by,jsonb_build_object('supersedes',v_old.id,'locator',p_evidence_locator));
  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.propose_work_lesson(p_kind text, p_claim text, p_detail text, p_evidence_kind text, p_evidence_locator text, p_source_authority text, p_created_by text, p_resolution_state text DEFAULT 'unverified'::text, p_integrity_hash text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_id uuid;
begin
  if p_kind not in ('worked','failed','prohibition','rule') then raise exception 'invalid kind'; end if;
  if p_claim is null or p_claim !~ '[^[:space:]]' then raise exception 'claim must contain non-whitespace'; end if;
  if p_created_by is null or p_created_by !~ '[^[:space:]]'
     or p_source_authority is null or p_source_authority !~ '[^[:space:]]' then
    raise exception 'creator and source authority must contain non-whitespace';
  end if;
  if p_resolution_state not in ('unverified','resolvable','invalid') then raise exception 'invalid resolution state'; end if;
  if not public.is_canonical_work_lesson_locator(p_evidence_kind,p_evidence_locator) then
    raise exception 'evidence locator must be canonical';
  end if;
  perform set_config('app.work_lessons_write','on',true);
  perform set_config('app.work_lesson_custody_write','on',true);
  insert into public.work_lessons(kind,claim,detail,authority_state,created_by)
  values(p_kind,p_claim,p_detail,'proposed',p_created_by) returning id into v_id;
  insert into public.work_lesson_evidence(lesson_id,evidence_kind,locator,source_authority,integrity_hash,resolution_state,created_by)
  values(v_id,p_evidence_kind,p_evidence_locator,p_source_authority,p_integrity_hash,p_resolution_state,p_created_by);
  insert into public.work_lesson_events(lesson_id,event_type,actor,details)
  values(v_id,'proposed',p_created_by,jsonb_build_object('evidence_kind',p_evidence_kind,'locator',p_evidence_locator));
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_native_memory_activation(p_memory_id uuid, p_actor text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select e.id from public.attention_events e
where e.memory_id=p_memory_id and e.source_event_type='memory_activated' and e.revision_ordinal=1
order by e.recorded_at,e.id limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.record_native_memory_attention(p_memory_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
select e.id from public.attention_events e
where e.memory_id=p_memory_id and e.source_event_type='memory_created' and e.revision_ordinal=1
order by e.recorded_at,e.id limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.reject_work_lesson(p_id uuid, p_actor text, p_authority_ref text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin
  if p_actor is null or p_actor !~ '[^[:space:]]'
     or p_authority_ref is null or p_authority_ref !~ '[^[:space:]]' then
    raise exception 'actor and authority reference must contain non-whitespace';
  end if;
  perform set_config('app.work_lessons_write','on',true);
  perform set_config('app.work_lesson_custody_write','on',true);
  update public.work_lessons set authority_state='rejected'
  where id=p_id and status='active' and authority_state='proposed';
  if not found then raise exception 'no active proposed lesson'; end if;
  insert into public.work_lesson_events(lesson_id,event_type,actor,authority_ref)
  values(p_id,'rejected',p_actor,p_authority_ref);
  return p_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.remediate_perimeter_acl()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_mode text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_acl_mode',true),''),'revoke');
  v_object record;v_acl record;v_allowed text[];v_owner text[]:=public.perimeter_policy_roles('owner');v_revoked integer:=0;
begin
  if v_mode not in ('revoke','fail') then raise exception 'PERIMETER FAIL: unknown sovereign_memory.perimeter_acl_mode %',v_mode; end if;
  if v_mode='fail' then return 'perimeter ACL policy is fail-only'; end if;

  -- The SECURITY DEFINER owner is the trusted control-table owner. Never derive
  -- a repair target from the durable policy row, which is precisely the object
  -- under review. Ownership drift must be handled by the owner-run migration,
  -- which validates shape/ACLs and refreshes the policy before calling here.
  for v_object in
    select c.relname,c.relowner from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname=any(array['perimeter_acl_policy','perimeter_protected_schema_registry','perimeter_authority_function_registry'])
  loop
    if v_object.relowner<>current_user::regrole then
      raise exception 'PERIMETER FAIL: unsafe durable control-table owner for public.%: rerun the owner migration',v_object.relname;
    end if;
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      left join pg_roles r on r.oid=a.grantee
      where c.oid=format('public.%I',v_object.relname)::regclass and a.grantee<>c.relowner
    loop
      execute format('revoke all on table public.%I from %s',v_object.relname,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
    for v_acl in
      select att.attname,a.privilege_type,a.grantee,
             case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from pg_attribute att cross join lateral aclexplode(att.attacl) a
      left join pg_roles r on r.oid=a.grantee
      where att.attrelid=format('public.%I',v_object.relname)::regclass
        and att.attnum>0 and not att.attisdropped and att.attacl is not null
        and a.grantee<>v_object.relowner
    loop
      execute format('revoke %s (%I) on table public.%I from %s',v_acl.privilege_type,v_acl.attname,v_object.relname,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;

  for v_object in select s.schema_oid,s.schema_name,n.nspowner from public.perimeter_protected_schemas() s join pg_namespace n on n.oid=s.schema_oid loop
    v_allowed:=public.perimeter_policy_roles('schema_create');
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from aclexplode(coalesce((select nspacl from pg_namespace where oid=v_object.schema_oid),acldefault('n',v_object.nspowner))) a
      left join pg_roles r on r.oid=a.grantee
      where a.privilege_type='CREATE' and a.grantee<>v_object.nspowner
        and not (coalesce(r.rolname,'PUBLIC')=any(v_owner)) and not (coalesce(r.rolname,'PUBLIC')=any(v_allowed))
    loop
      execute format('revoke create on schema %I from %s',v_object.schema_name,case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;

  for v_object in select f.function_oid,f.function_identity,f.is_internal,p.proowner,p.proacl from public.perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid loop
    v_allowed:=case when v_object.is_internal then public.perimeter_policy_roles('internal_execute') else public.perimeter_policy_roles('function_execute') end;
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from aclexplode(coalesce(v_object.proacl,acldefault('f',v_object.proowner))) a left join pg_roles r on r.oid=a.grantee
      where a.privilege_type='EXECUTE' and a.grantee<>v_object.proowner
        and not (coalesce(r.rolname,'PUBLIC')=any(v_owner)) and not (coalesce(r.rolname,'PUBLIC')=any(v_allowed))
    loop
      execute format('revoke execute on function %s from %s',v_object.function_identity,case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;

  -- Owner-global defaults apply to every schema owned by that role. This
  -- repository cannot safely mutate them; only schema-scoped defaults for an
  -- explicitly registered schema are remediated below.
  for v_object in
    select s.schema_name,r.oid nspowner,r.rolname owner_name,x.objtype,x.object_kind
    from public.perimeter_protected_schemas() s
    cross join lateral unnest(public.perimeter_policy_roles('owner')) owner_name
    join pg_roles r on r.rolname=owner_name
    cross join (values('r'::"char",'tables'::text),('S'::"char",'sequences'),('f'::"char",'functions')) x(objtype,object_kind)
  loop
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
      left join pg_roles r on r.oid=a.grantee
      where d.defaclrole=v_object.nspowner
        and d.defaclnamespace=(select oid from pg_namespace where nspname=v_object.schema_name)
        and d.defaclobjtype=v_object.objtype and a.grantee<>v_object.nspowner
    loop
      execute format('alter default privileges for role %I in schema %I revoke all on %s from %s',
        v_object.owner_name,v_object.schema_name,v_object.object_kind,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;
  return format('perimeter ACL remediation revoked %s direct grant(s)',v_revoked);
end;
$function$;

CREATE OR REPLACE FUNCTION public.remember(p_content text, p_workstream text, p_topic_key text, p_source_agent text, p_owner text, p_summary text DEFAULT NULL::text, p_tags text[] DEFAULT '{}'::text[], p_visibility text DEFAULT 'shared'::text, p_due_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_id uuid;
begin
  if not exists(select 1 from public.trusted_agents where agent_id=p_source_agent and active) then
    raise exception 'remember: source_agent % is not a known active trusted agent',p_source_agent;
  end if;
  if p_topic_key is not null and p_topic_key ~ '[^[:space:]]' then
    perform set_config('app.attention_explicit_topic','on',true);
  end if;
  insert into public.memories(content,workstream,tags,owner,visibility,source_agent,source_kind,due_date,due_status)
  values(p_content,p_workstream,p_tags,p_owner,p_visibility,p_source_agent,'agent',p_due_date,
         case when p_due_date is not null then 'pending' else null end)
  returning id into v_id;
  if p_topic_key is not null and p_topic_key ~ '[^[:space:]]' then
    perform public.hot_touch(p_topic_key,v_id,coalesce(p_summary,left(p_content,200)),p_workstream);
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.session_boot(p_viewer text DEFAULT 'shared'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
with attention as (select public.attention_boot_projection_v2(p_viewer,12000,240) payload)
select jsonb_build_object(
  'viewer',p_viewer,
  'hot_topics',(select payload->'topics' from attention),
  'attention_coverage',(select payload->'coverage' from attention),
  'work_lessons',public.work_lessons_boot_fragment(),
  'deadlines',(select coalesce(jsonb_agg(jsonb_build_object(
    'content',left(content,100),'owner',owner,'due_date',due_date,'overdue',overdue,'days_until',days_until
  ) order by due_date),'[]'::jsonb) from public.deadlines_upcoming where visibility='shared' or owner=p_viewer),
  'channel_inbox',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (
    select jsonb_build_object('seq',seq,'from',from_agent,'kind',kind,'subject',subject,'due_at',due_at,'add_to_calendar',add_to_calendar) x
    from public.household_channel where status='open' and to_principal in (p_viewer,'shared')
    order by due_at asc nulls last,created_at asc limit 25
  ) s),
  'instruction_integrity',(select state from public.verify_doc_integrity('_system/ai-instructions')),
  'health',jsonb_build_object(
    'memories_visible',(select count(*) from public.memories where status='active' and (visibility='shared' or owner=p_viewer)),
    'hot_touch_pending',(select count(*) from public.hot_touch_pending where owner=p_viewer or owner='shared'),
    'attention_events',(select count(*) from public.attention_events),
    'attention_events_unassigned',(select count(*) from public.attention_events e where not exists(select 1 from public.attention_event_assignments a where a.event_id=e.id)),
    'proposed_for_review',(select count(*) from public.memories where status='proposed' and (visibility='shared' or owner=p_viewer))
  ),
  'booted_at',now()
);
$function$;

CREATE OR REPLACE FUNCTION public.supersede_memory(p_old_id uuid, p_new_content text, p_source_agent text, p_summary text DEFAULT NULL::text, p_tags text[] DEFAULT NULL::text[], p_due_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_old public.memories%ROWTYPE; v_new uuid;
begin
  if not exists (select 1 from public.trusted_agents where agent_id=p_source_agent and active) then
    raise exception 'supersede_memory: unknown/inactive source_agent %', p_source_agent; end if;
  select * into v_old from public.memories where id=p_old_id for update;
  if not found then raise exception 'supersede_memory: % not found', p_old_id; end if;
  if v_old.status <> 'active' then raise exception 'supersede_memory: % is % not active', p_old_id, v_old.status; end if;
  insert into public.memories(content, workstream, tags, owner, visibility, source_agent, source_kind, supersedes, status, due_date, due_status)
  values (p_new_content, v_old.workstream, coalesce(p_tags, v_old.tags), v_old.owner, v_old.visibility,
          p_source_agent, 'agent', p_old_id, 'active', p_due_date,
          case when p_due_date is not null then 'pending' else null end)
  returning id into v_new;
  update public.memories set status='superseded' where id=p_old_id;
  update public.memory_hot_index set memory_id=v_new, summary=left(coalesce(p_summary,p_new_content),200), last_touched=now()
   where memory_id=p_old_id;
  return v_new;
end; $function$;

CREATE OR REPLACE FUNCTION public.supersede_wiki(p_path text, p_new_content text, p_source_agent text, p_title text DEFAULT NULL::text, p_frontmatter jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare v_old public.wiki_pages%ROWTYPE; v_new uuid;
begin
  if not exists (select 1 from public.trusted_agents where agent_id=p_source_agent and active) then
    raise exception 'supersede_wiki: unknown/inactive source_agent %', p_source_agent; end if;
  select * into v_old from public.wiki_pages where path=p_path and status='active' for update;
  if not found then raise exception 'supersede_wiki: no active page at %', p_path; end if;
  update public.wiki_pages set status='superseded' where id=v_old.id;
  insert into public.wiki_pages(path, title, content, tags, workstream, owner, visibility, source_kind, source_agent, supersedes, frontmatter, status)
  values (p_path, coalesce(p_title,v_old.title), p_new_content, v_old.tags, v_old.workstream, v_old.owner, v_old.visibility,
          'agent', p_source_agent, v_old.id, coalesce(p_frontmatter, v_old.frontmatter), 'active')
  returning id into v_new;
  return v_new;
end; $function$;

CREATE OR REPLACE FUNCTION public.verify_doc_integrity(p_path text)
 RETURNS TABLE(path text, state text, blessed_sha256 text, current_sha256 text, blessed_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select p_path,
    case when di.blessed_sha256 is null then 'no-blessing'
         when di.blessed_sha256 = public.current_doc_hash(p_path) then 'match'
         else 'mismatch' end,
    di.blessed_sha256, public.current_doc_hash(p_path), di.blessed_at
  from (select 1) x left join public.doc_integrity di on di.path=p_path;
$function$;

CREATE OR REPLACE FUNCTION public.work_lessons_boot_fragment()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
with bootable as (
  select wl.* from public.work_lessons wl
  where wl.status='active' and wl.authority_state='accepted' and wl.applies_to='all-agents'
    and (
      wl.kind not in ('rule','prohibition')
      or exists(
        select 1 from public.work_lesson_evidence_current e
        where e.lesson_id=wl.id and e.resolution_state='resolvable'
      )
    )
)
select jsonb_build_object(
  'prohibitions',(select coalesce(jsonb_agg(claim order by learned_on desc,created_at desc,id),'[]'::jsonb) from bootable where kind='prohibition'),
  'rules',(select coalesce(jsonb_agg(claim order by learned_on desc,created_at desc,id),'[]'::jsonb) from bootable where kind='rule'),
  'counts',jsonb_build_object(
    'worked',(select count(*) from public.work_lessons where status='active' and authority_state='accepted' and kind='worked'),
    'failed',(select count(*) from public.work_lessons where status='active' and authority_state='accepted' and kind='failed'),
    'proposed',(select count(*) from public.work_lessons where status='active' and authority_state='proposed'),
    'evidence_blocked',(select count(*) from public.work_lessons wl where wl.status='active' and wl.authority_state='accepted' and wl.kind in ('rule','prohibition') and not exists(select 1 from public.work_lesson_evidence_current e where e.lesson_id=wl.id and e.resolution_state='resolvable'))
  )
);
$function$;

select public.assert_perimeter_closed();
