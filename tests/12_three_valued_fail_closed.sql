-- Three-valued logic fail-closed matrix (issue #74).
--
-- Disposable and local. The script opens a transaction and rolls it back.
-- It does not migrate the runtime schema and it does not touch a live database.
--
-- The census below is precommitted. A naive consumer passes each case without
-- having proved the invariant. The corrected consumer rejects that same case.
-- If a case stops discriminating, this file raises instead of reporting pass.

begin;

set local client_min_messages to warning;

drop schema if exists smc_tvl cascade;
create schema smc_tvl;

create table smc_tvl.discrimination (
  case_id text primary key,
  naive_passes boolean not null,
  corrected_rejects boolean not null,
  check (naive_passes and corrected_rejects)
);

-- Corrected assertion helpers. NULL is a failed assertion, and an empty
-- input is a failed assertion. Neither helper is STRICT: STRICT would turn
-- a null argument into a null result and recreate the hole.
create function smc_tvl.all_passed(p_passes boolean[])
returns boolean
language sql
immutable
called on null input
set search_path = pg_catalog
as $$
  select coalesce(bool_and(coalesce(v, false)), false)
  from unnest(coalesce(p_passes, array[]::boolean[])) as u(v);
$$;

create function smc_tvl.not_true_count(p_passes boolean[])
returns bigint
language sql
immutable
called on null input
set search_path = pg_catalog
as $$
  select count(*) filter (where v is not true)
  from unnest(coalesce(p_passes, array[]::boolean[])) as u(v);
$$;

-- The broken guard shape: IF NOT <predicate> does not run when the predicate
-- is NULL. The corrected guard treats every result other than true as failure.
create function smc_tvl.not_guard_fires(p_allow boolean)
returns boolean
language plpgsql
immutable
called on null input
set search_path = pg_catalog
as $$
begin
  if not p_allow then
    return true;
  end if;
  return false;
end;
$$;

create function smc_tvl.failure_guard_fires(p_pass boolean)
returns boolean
language plpgsql
immutable
called on null input
set search_path = pg_catalog
as $$
begin
  if p_pass is not true then
    return true;
  end if;
  return false;
end;
$$;

-- Layer 2 predicates. The nullable body is the hazard. The total body is the
-- required shape. The STRICT wrapper has the total body and still returns
-- NULL when any argument is NULL, so STRICT is not a fix.
create function smc_tvl.owner_or_shared_nullable(
  p_row_owner text,
  p_principal_id text,
  p_row_visibility text
) returns boolean
language sql
immutable
called on null input
set search_path = pg_catalog
as $$
  select p_row_owner = p_principal_id or p_row_visibility = 'shared';
$$;

create function smc_tvl.owner_or_shared_total(
  p_row_owner text,
  p_principal_id text,
  p_row_visibility text
) returns boolean
language sql
immutable
called on null input
set search_path = pg_catalog
as $$
  select coalesce(
    (p_row_owner is not null
      and p_principal_id is not null
      and p_row_owner = p_principal_id)
    or p_row_visibility = 'shared',
    false
  );
$$;

create function smc_tvl.owner_or_shared_strict(
  p_row_owner text,
  p_principal_id text,
  p_row_visibility text
) returns boolean
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select coalesce(
    (p_row_owner is not null
      and p_principal_id is not null
      and p_row_owner = p_principal_id)
    or p_row_visibility = 'shared',
    false
  );
$$;

-- Columns referenced by a CHECK. A constraint that exists is not the same
-- thing as a constraint that cannot evaluate to NULL.
create function smc_tvl.nullable_check_columns(p_rel regclass)
returns table(conname name, attname name)
language sql
stable
set search_path = pg_catalog
as $$
  select c.conname, a.attname
  from pg_constraint as c
  join lateral unnest(c.conkey) as cols(attnum) on true
  join pg_attribute as a
    on a.attrelid = c.conrelid
   and a.attnum = cols.attnum
   and not a.attisdropped
  where c.contype = 'c'
    and c.conrelid = p_rel
    and not a.attnotnull;
$$;

create function smc_tvl.record_discrimination(
  p_case_id text,
  p_naive_passes boolean,
  p_corrected_rejects boolean
) returns void
language plpgsql
called on null input
set search_path = pg_catalog
as $$
begin
  if p_naive_passes is not true or p_corrected_rejects is not true then
    raise exception
      'case % does not discriminate (naive_passes=%, corrected_rejects=%)',
      p_case_id, p_naive_passes, p_corrected_rejects;
  end if;
  insert into smc_tvl.discrimination(case_id, naive_passes, corrected_rejects)
  values (p_case_id, true, true);
end;
$$;

-- Layer 1. A missing jsonb key becomes NULL, comparison stays NULL, NOT NULL
-- stays NULL, bool_and ignores that NULL, and FILTER (WHERE NOT pass) counts
-- zero failures. The corrected forms fail closed.
do $$
declare
  v_comparison boolean;
  v_negated boolean;
  v_naive boolean;
  v_naive_failures bigint;
  v_passes boolean[] := array[true, null, true];
begin
  v_comparison := ('{"a":1}'::jsonb ->> 'missing') = 'x';
  v_negated := not v_comparison;

  if v_comparison is not null or v_negated is not null then
    raise exception 'missing-key comparison did not stay NULL';
  end if;

  select bool_and(v), count(*) filter (where not v)
    into v_naive, v_naive_failures
  from (values (true), (null::boolean), (true)) as t(v);

  if v_naive is not true or v_naive_failures <> 0 then
    raise exception
      'bool_and/FILTER hazard did not reproduce (summary=%, failures=%)',
      v_naive, v_naive_failures;
  end if;

  if smc_tvl.all_passed(v_passes) is not false
     or smc_tvl.not_true_count(v_passes) <> 1 then
    raise exception 'corrected assertion helpers did not fail closed on NULL';
  end if;

  perform smc_tvl.record_discrimination(
    'l1_bool_and_ignores_null',
    v_naive is true,
    smc_tvl.all_passed(v_passes) is false
  );
  perform smc_tvl.record_discrimination(
    'l1_filter_not_ignores_null',
    v_naive_failures = 0,
    smc_tvl.not_true_count(v_passes) = 1
  );
  perform smc_tvl.record_discrimination(
    'l1_not_null_skips_guard',
    smc_tvl.not_guard_fires(v_comparison) is false,
    smc_tvl.failure_guard_fires(v_comparison) is true
  );

  -- An empty aggregate is NULL. "IS NOT FALSE" accepts that NULL as success.
  -- coalesce(bool_and(...), false) does not.
  select bool_and(v) is not false
    into v_naive
  from (select null::boolean as v where false) as empty(v);

  if v_naive is not true or smc_tvl.all_passed(null::boolean[]) is not false then
    raise exception 'empty assertion aggregate was not both naive-pass and corrected-fail';
  end if;

  perform smc_tvl.record_discrimination(
    'l1_empty_aggregate_is_not_false',
    v_naive is true,
    smc_tvl.all_passed(null::boolean[]) is false
  );
end $$;

-- Layer 2. WHERE drops NULL and false alike, so the nullable predicate looks
-- safe there. IF NOT does not treat NULL as denial, and STRICT returns NULL
-- before a total body can run.
do $$
declare
  v_where_yes bigint;
  v_where_not bigint;
  v_where_total_reject bigint;
  v_strict boolean;
  v_total boolean;
  v_proisstrict boolean;
begin
  create table smc_tvl.access_rows (
    row_owner text,
    visibility text
  );
  insert into smc_tvl.access_rows(row_owner, visibility)
  values
    ('example-user', 'private'),
    (null, 'private'),
    ('example-partner', 'shared');

  select count(*) into v_where_yes
  from smc_tvl.access_rows
  where smc_tvl.owner_or_shared_nullable(row_owner, 'example-user', visibility);

  select count(*) into v_where_not
  from smc_tvl.access_rows
  where not smc_tvl.owner_or_shared_nullable(row_owner, 'example-user', visibility);

  select count(*) into v_where_total_reject
  from smc_tvl.access_rows
  where smc_tvl.owner_or_shared_total(row_owner, 'example-user', visibility)
        is not true;

  if v_where_yes <> 2 or v_where_not <> 0 or v_where_total_reject <> 1 then
    raise exception
      'WHERE hid or failed to hide the NULL row (yes=%, not=%, total_reject=%)',
      v_where_yes, v_where_not, v_where_total_reject;
  end if;

  if exists (
    select 1
    from (values
      (null::text, 'example-user'::text, 'private'::text, false),
      (null, null, null, false),
      ('example-user', null, null, false),
      ('example-user', 'example-user', null, true),
      ('example-partner', 'example-user', 'private', false),
      ('example-partner', 'example-user', 'shared', true),
      (null, 'example-user', 'shared', true)
    ) as expected(row_owner, principal_id, visibility, allow)
    where smc_tvl.owner_or_shared_total(row_owner, principal_id, visibility)
          is distinct from allow
  ) then
    raise exception 'total predicate returned NULL or the wrong boolean';
  end if;

  select p.proisstrict
    into v_proisstrict
  from pg_proc as p
  join pg_namespace as n on n.oid = p.pronamespace
  where n.nspname = 'smc_tvl'
    and p.proname = 'owner_or_shared_total';

  if v_proisstrict is not false then
    raise exception 'total predicate is STRICT';
  end if;

  select p.proisstrict
    into v_proisstrict
  from pg_proc as p
  join pg_namespace as n on n.oid = p.pronamespace
  where n.nspname = 'smc_tvl'
    and p.proname = 'owner_or_shared_strict';

  if v_proisstrict is not true then
    raise exception 'STRICT fixture is not STRICT';
  end if;

  v_strict := smc_tvl.owner_or_shared_strict(null, 'example-user', 'private');
  v_total := smc_tvl.owner_or_shared_total(null, 'example-user', 'private');

  if v_strict is not null or v_total is not false then
    raise exception
      'STRICT null-bypass did not reproduce (strict=%, total=%)',
      v_strict, v_total;
  end if;

  -- A true body is also discarded: owner match with NULL visibility.
  if smc_tvl.owner_or_shared_total('example-user', 'example-user', null) is not true
     or smc_tvl.owner_or_shared_strict('example-user', 'example-user', null) is not null then
    raise exception 'STRICT did not discard a true owner match when visibility is NULL';
  end if;

  perform smc_tvl.record_discrimination(
    'l2_not_predicate_skips_guard',
    smc_tvl.not_guard_fires(
      smc_tvl.owner_or_shared_nullable(null, 'example-user', 'private')
    ) is false,
    smc_tvl.failure_guard_fires(
      smc_tvl.owner_or_shared_total(null, 'example-user', 'private')
    ) is true
  );
  perform smc_tvl.record_discrimination(
    'l2_strict_reintroduces_null',
    v_strict is null
      and smc_tvl.not_guard_fires(v_strict) is false,
    v_total is false
      and smc_tvl.failure_guard_fires(v_total) is true
  );
end $$;

-- Layer 3. CHECK accepts UNKNOWN. NOT NULL on every column the invariant
-- reads is what makes the bad row fail. A catalog check that only asks
-- whether the constraint exists still passes on the open table.
do $$
declare
  v_open_accepted boolean := false;
  v_closed_accepted boolean := false;
  v_open_gaps bigint;
  v_closed_gaps bigint;
  v_open_has_check boolean;
  v_closed_has_check boolean;
begin
  create table smc_tvl.binding_open (
    binding_status text,
    review_status text,
    constraint binding_open_dual_control check (
      (binding_status <> 'active') or (review_status = 'approved')
    )
  );

  create table smc_tvl.binding_closed (
    binding_status text not null,
    review_status text not null,
    constraint binding_closed_dual_control check (
      (binding_status <> 'active') or (review_status = 'approved')
    )
  );

  insert into smc_tvl.binding_open(binding_status, review_status)
  values ('active', null);
  v_open_accepted := true;

  insert into smc_tvl.binding_open(binding_status, review_status)
  values ('inactive', null);

  begin
    insert into smc_tvl.binding_open(binding_status, review_status)
    values ('active', 'pending');
    raise exception 'open CHECK accepted active/pending';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into smc_tvl.binding_closed(binding_status, review_status)
    values ('active', null);
    v_closed_accepted := true;
  exception
    when not_null_violation then
      v_closed_accepted := false;
  end;

  if v_closed_accepted then
    raise exception 'NOT NULL pairing accepted active/NULL review';
  end if;

  insert into smc_tvl.binding_closed(binding_status, review_status)
  values ('active', 'approved');

  begin
    insert into smc_tvl.binding_closed(binding_status, review_status)
    values ('active', 'pending');
    raise exception 'closed CHECK accepted active/pending';
  exception
    when check_violation then
      null;
  end;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'smc_tvl.binding_open'::regclass
      and contype = 'c'
      and conkey is not null
  ) then
    raise exception 'CHECK conkey was empty; pairing checker cannot see columns';
  end if;

  select count(*) into v_open_gaps
  from smc_tvl.nullable_check_columns('smc_tvl.binding_open'::regclass);
  select count(*) into v_closed_gaps
  from smc_tvl.nullable_check_columns('smc_tvl.binding_closed'::regclass);

  if v_open_gaps <> 2 or v_closed_gaps <> 0 then
    raise exception 'pairing checker gaps were open=% closed=%', v_open_gaps, v_closed_gaps;
  end if;

  if exists (
    select 1
    from pg_attribute
    where attrelid = 'smc_tvl.binding_closed'::regclass
      and attnum > 0
      and not attisdropped
      and not attnotnull
  ) then
    raise exception 'closed fixture still has a nullable column';
  end if;

  v_open_has_check := exists (
    select 1
    from pg_constraint
    where conrelid = 'smc_tvl.binding_open'::regclass
      and contype = 'c'
  );
  v_closed_has_check := exists (
    select 1
    from pg_constraint
    where conrelid = 'smc_tvl.binding_closed'::regclass
      and contype = 'c'
  );

  if v_open_has_check is not true or v_closed_has_check is not true then
    raise exception 'dual-control CHECK was missing from a fixture table';
  end if;

  perform smc_tvl.record_discrimination(
    'l3_check_accepts_null',
    v_open_accepted is true,
    v_closed_accepted is false
  );
  -- Presence of the CHECK would accept the open table. The pairing query
  -- rejects it because the columns it reads are nullable.
  perform smc_tvl.record_discrimination(
    'l3_presence_is_not_pairing',
    v_open_has_check is true,
    v_open_gaps > 0
  );
end $$;

do $$
declare
  v_count integer;
  v_expected constant integer := 8;
begin
  select count(*) into v_count from smc_tvl.discrimination;
  if v_count <> v_expected then
    raise exception
      'discrimination census % <> precommitted %', v_count, v_expected;
  end if;
end $$;

select 'three_valued_fail_closed: pass discriminated='
    || count(*)::text
    || ' cases='
    || string_agg(case_id, ',' order by case_id)
  from smc_tvl.discrimination;

rollback;
