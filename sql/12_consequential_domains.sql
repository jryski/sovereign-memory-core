-- ============================================================================
-- SOVEREIGN MEMORY :: DECLARED CONSEQUENTIAL DOMAINS (optional)
-- Apply after 01_core.sql. Apply it before 09_perimeter_refresh.sql when that
-- perimeter package is used. 11_perimeter_evaluability.sql stays the last
-- perimeter-report migration. Re-applying this file does not rewrite
-- assert_perimeter_closed().
--
-- This is a declaration layer for Tier 1 memories and wiki_pages. It does not
-- classify prose. A row is consequential only when a schema owner bound its
-- workstream, or when the row names a declared domain. The financial figure
-- guard in 03_provenance_guards.sql is unchanged.
--
-- Main has no provenance_registry, provenance_basis enum, principals table, or
-- app.promoting setting. Those objects are not created here. Provenance stays
-- in memories.metadata and wiki_pages.frontmatter, using the same closed basis
-- list and placeholder citations as the financial figure guard. Authorship
-- stays on source_kind. Review stays on knowledge_status plus
-- promote_memory(uuid, text, text), which moves proposed -> active and does
-- not change source_kind.
--
-- Agent-authored consequential rows are rejected at write time, including
-- status=proposed. The rejection is not limited to "status is not proposed":
-- that form also rejects promote_memory when a human promotes a row. Human
-- and manual rows keep the existing review path. An ordinary agent proposal
-- that is not in a declared domain can still be promoted.
-- ============================================================================

create table if not exists consequential_domains (
  domain text primary key check (domain ~ '^[a-z][a-z0-9_]{0,63}$'),
  allowed_basis text[] not null,
  citation_required boolean not null default true,
  rationale text not null check (btrim(rationale) <> ''),
  declared_at timestamptz not null default now(),
  constraint consequential_domains_basis_nonempty check (cardinality(allowed_basis) > 0),
  constraint consequential_domains_basis_closed check (
    allowed_basis <@ array['human_direct','decision_record','imported_artifact','source_document']::text[]
  )
);

create table if not exists consequential_domain_bindings (
  relation_name text not null check (relation_name in ('memories','wiki_pages')),
  workstream text not null check (btrim(workstream) <> ''),
  domain text not null references consequential_domains(domain),
  declared_at timestamptz not null default now(),
  primary key (relation_name, workstream)
);

comment on table consequential_domains is
  'Declared consequential domains. Baseline rows are financial, legal, medical, and identity. Additional domains are further inserts. Policy rows are schema-owner configuration.';
comment on table consequential_domain_bindings is
  'Schema-owner binding from a memories or wiki_pages workstream to one declared domain. A row cannot name a different domain than its binding.';

-- Re-application must not loosen or replace a baseline a deployment already edited.
insert into consequential_domains(domain, allowed_basis, citation_required, rationale) values
  ('financial',
   array['human_direct','decision_record','imported_artifact','source_document'],
   true,
   'Baseline consequential domain for financial claims. Tier 1 rows need a closed provenance basis and a specific citation. Agent-authored rows are rejected at write time.'),
  ('legal',
   array['human_direct','decision_record','imported_artifact','source_document'],
   true,
   'Baseline consequential domain for legal claims. Tier 1 rows need a closed provenance basis and a specific citation. Agent-authored rows are rejected at write time.'),
  ('medical',
   array['human_direct','decision_record','imported_artifact','source_document'],
   true,
   'Baseline consequential domain for medical claims. Tier 1 rows need a closed provenance basis and a specific citation. Agent-authored rows are rejected at write time.'),
  ('identity',
   array['human_direct','decision_record','imported_artifact','source_document'],
   true,
   'Baseline consequential domain for identity claims. Tier 1 rows need a closed provenance basis and a specific citation. Agent-authored rows are rejected at write time.')
on conflict (domain) do nothing;

alter table memories add column if not exists consequential_domain text;
alter table wiki_pages add column if not exists consequential_domain text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'memories_consequential_domain_fkey'
      and conrelid = 'public.memories'::regclass
  ) then
    alter table memories
      add constraint memories_consequential_domain_fkey
      foreign key (consequential_domain) references consequential_domains(domain);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'wiki_pages_consequential_domain_fkey'
      and conrelid = 'public.wiki_pages'::regclass
  ) then
    alter table wiki_pages
      add constraint wiki_pages_consequential_domain_fkey
      foreign key (consequential_domain) references consequential_domains(domain);
  end if;
end $$;

create index if not exists memories_consequential_domain_idx
  on memories (consequential_domain) where consequential_domain is not null;
create index if not exists wiki_pages_consequential_domain_idx
  on wiki_pages (consequential_domain) where consequential_domain is not null;

create or replace function enforce_consequential_domain()
returns trigger
language plpgsql
set search_path to 'public'
as $fn$
declare
  v_declared text;
  v_bound text;
  v_domain text;
  v_basis text;
  v_citation text;
  v_allowed text[];
  v_citation_required boolean;
  v_bag jsonb;
  v_placeholder text[] := array['none','unknown','memory','estimate','web','supplier','source','tbd','n/a','na',''];
begin
  if tg_table_name = 'memories' then
    v_bag := new.metadata;
  elsif tg_table_name = 'wiki_pages' then
    v_bag := new.frontmatter;
  else
    raise exception 'consequential domain trigger is not installed on %', tg_table_name;
  end if;

  v_declared := nullif(btrim(coalesce(new.consequential_domain, '')), '');

  -- A blank successor inherits the predecessor's classification. An explicit
  -- value still has to agree with a workstream binding.
  if v_declared is null and new.supersedes is not null then
    if tg_table_name = 'memories' then
      select m.consequential_domain into v_declared
      from memories m where m.id = new.supersedes;
    else
      select w.consequential_domain into v_declared
      from wiki_pages w where w.id = new.supersedes;
    end if;
  end if;

  select b.domain into v_bound
  from consequential_domain_bindings b
  where b.relation_name = tg_table_name
    and new.workstream is not null
    and b.workstream = new.workstream;

  if v_bound is not null and v_declared is not null and v_declared is distinct from v_bound then
    raise exception
      'consequential domain conflict on %: workstream "%" is bound to % but the row declares %',
      tg_table_name, new.workstream, v_bound, v_declared;
  end if;

  v_domain := coalesce(v_bound, v_declared);

  -- A classification may be added. It may not be cleared or swapped in place.
  -- Reclassification is a new row. This does not look at status: promotion
  -- keeps the same domain. OLD is read only on UPDATE.
  if tg_op = 'UPDATE' then
    if old.consequential_domain is not null
       and v_domain is distinct from old.consequential_domain then
      raise exception
        'consequential domain is not editable once set (row %, % -> %)',
        new.id, old.consequential_domain, coalesce(v_domain, 'NULL');
    end if;
  end if;

  if v_domain is null then
    return new;
  end if;

  new.consequential_domain := v_domain;

  select d.allowed_basis, d.citation_required
    into v_allowed, v_citation_required
  from consequential_domains d
  where d.domain = v_domain;
  if not found then
    raise exception
      'domain % is not declared in consequential_domains; refusing the write (relation %, row %)',
      v_domain, tg_table_name, new.id;
  end if;

  -- source_kind is the authorship column this schema already stores.
  -- Checked before citation so an agent write is not misreported as a
  -- missing source. Both the resulting row and the previous row count, so
  -- one update cannot relabel an agent row as human. This does not require
  -- status=proposed: promote_memory is an update to active, and a human
  -- promotion must still succeed. Ordinary unclassified agent rows return
  -- above, before this check.
  if new.source_kind = 'agent' then
    raise exception
      'agent-authored consequential fact rejected at write time in the % domain (relation %, row %, source_kind %)',
      v_domain, tg_table_name, new.id, new.source_kind;
  end if;
  if tg_op = 'UPDATE' then
    if old.source_kind = 'agent' then
      raise exception
        'agent-authored consequential fact rejected at write time in the % domain (relation %, row %, source_kind %)',
        v_domain, tg_table_name, new.id, old.source_kind;
    end if;
  end if;

  v_basis := nullif(btrim(coalesce(v_bag->>'basis', '')), '');
  v_citation := lower(btrim(coalesce(v_bag->>'source_citation', '')));

  if v_basis is null or not (v_basis = any (v_allowed)) then
    raise exception
      'unsourced consequential fact: % domain requires basis in (%) (relation %, row %, got %)',
      v_domain, array_to_string(v_allowed, ','), tg_table_name, new.id, coalesce(v_basis, 'null');
  end if;

  if v_citation_required and (v_citation = '' or v_citation = any (v_placeholder)) then
    raise exception
      'unsourced consequential fact: % domain requires a specific source_citation (relation %, row %, citation %)',
      v_domain, tg_table_name, new.id, coalesce(v_bag->>'source_citation', 'null');
  end if;

  return new;
end;
$fn$;

drop trigger if exists trg_consequential_domain_memories on memories;
create trigger trg_consequential_domain_memories
  before insert or update on memories
  for each row execute function enforce_consequential_domain();

drop trigger if exists trg_consequential_domain_wiki on wiki_pages;
create trigger trg_consequential_domain_wiki
  before insert or update on wiki_pages
  for each row execute function enforce_consequential_domain();

revoke all on consequential_domains, consequential_domain_bindings from public, anon, authenticated;
revoke all on function enforce_consequential_domain() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant select on consequential_domains, consequential_domain_bindings to service_role;
    grant execute on function enforce_consequential_domain() to service_role;
  end if;
end $$;

do $$
begin
  if (select count(*) from consequential_domains
      where domain in ('financial','legal','medical','identity')) <> 4 then
    raise exception 'consequential domain baseline is incomplete';
  end if;
end $$;

select assert_perimeter_closed();
