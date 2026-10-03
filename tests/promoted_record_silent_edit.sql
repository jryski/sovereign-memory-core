-- Disposable negative check for a silent post-promotion edit.
-- Not a migration. Not applied to any deployment. The shell wrapper loads this
-- into a throwaway local database and drops that database.
--
-- Candidate edits must succeed. A silent edit of a promoted record must not be
-- reported as a match. Memories have no receipt, so the honest state is
-- unaudited. A blessed active wiki page must report mismatch. no-blessing is
-- not match and not mismatch. A hash match after re-bless is not a signature.

\set ON_ERROR_STOP on

do $$
declare
  v_candidate uuid;
  v_promoted uuid;
  v_superseded uuid;
  v_successor uuid;
  v_wiki_old uuid;
  v_wiki_new uuid;
  v_text text;
  v_state text;
  v_before text;
  v_after text;
  v_status_n integer;
  v_all_n integer;
  v_receipts integer;
begin
  if to_regclass('public.promoted_record_audit') is not null then
    raise exception 'FAIL CLOSED: unexpected memory receipt table; this check only classifies the current tree';
  end if;

  insert into public.memories(content, owner, visibility, source_agent, source_kind, status)
  values ('candidate original', 'shared', 'shared', 'system', 'manual', 'proposed')
  returning id into v_candidate;

  update public.memories
  set content = 'candidate revised'
  where id = v_candidate and status = 'proposed';

  select content, status::text into v_text, v_state
  from public.memories where id = v_candidate;
  if v_text <> 'candidate revised' or v_state <> 'proposed' then
    raise exception 'FAIL CLOSED: candidate memory edit was not allowed (content=%, status=%)', v_text, v_state;
  end if;
  raise notice 'detection.candidate_memory_edit=allowed';

  insert into public.memories(
    content, owner, visibility, source_agent, source_kind, status, due_date, due_status
  ) values (
    'promoted original', 'shared', 'shared', 'system', 'manual', 'proposed',
    now() + interval '1 day', 'pending'
  ) returning id into v_promoted;

  if public.promote_memory(v_promoted, 'fixture review', 'system') <> 'promoted' then
    raise exception 'FAIL CLOSED: promote_memory did not promote the candidate';
  end if;

  select content into v_before from public.memories where id = v_promoted and status = 'active';
  if v_before <> 'promoted original' then
    raise exception 'FAIL CLOSED: promotion rewrote memory content';
  end if;

  update public.memories
  set content = 'promoted silently rewritten'
  where id = v_promoted and status = 'active';

  select content into v_after from public.memories where id = v_promoted;
  if v_after is not distinct from v_before then
    raise exception 'FAIL CLOSED: silent promoted-record edit did not change content';
  end if;

  -- Receipt absence is its own state. Do not infer match from "nothing
  -- contradicts" and do not infer mismatch from "the test changed the bytes".
  v_state := case
    when to_regclass('public.promoted_record_audit') is null then 'unaudited'
    else 'receipt_present_unclassified'
  end;
  if v_state = 'match' then
    raise exception 'FAIL CLOSED: silent promoted-record edit reported as match';
  end if;
  if v_state = 'mismatch' then
    raise exception 'FAIL CLOSED: absence of a memory receipt reported as mismatch';
  end if;
  if v_state <> 'unaudited' then
    raise exception 'FAIL CLOSED: unexpected memory integrity state %', v_state;
  end if;

  select count(*) filter (where action = 'status_change'), count(*)
  into v_status_n, v_all_n
  from public.audit_log
  where table_name = 'memories' and row_id = v_promoted;
  if v_status_n <> 1 or v_all_n <> 1 then
    raise exception 'FAIL CLOSED: silent content edit produced an audit receipt (status=%, all=%)', v_status_n, v_all_n;
  end if;
  raise notice 'detection.promoted_memory_silent_edit=unaudited';

  update public.memories set due_status = 'done' where id = v_promoted and status = 'active';
  select content into v_text from public.memories where id = v_promoted;
  if v_text <> 'promoted silently rewritten' then
    raise exception 'FAIL CLOSED: operational due_status update rewrote promoted content';
  end if;
  if not exists (
    select 1 from public.audit_log
    where table_name = 'memories' and row_id = v_promoted and action = 'due_status_change'
  ) then
    raise exception 'FAIL CLOSED: operational due_status update lost the existing audit';
  end if;
  raise notice 'detection.operational_due_status=allowed';

  insert into public.memories(content, owner, visibility, source_agent, source_kind, status)
  values ('supersede original', 'shared', 'shared', 'system', 'manual', 'proposed')
  returning id into v_superseded;
  if public.promote_memory(v_superseded, 'fixture review', 'system') <> 'promoted' then
    raise exception 'FAIL CLOSED: supersession fixture was not promoted';
  end if;
  v_successor := public.supersede_memory(v_superseded, 'supersede corrected', 'system');
  if (select content from public.memories where id = v_superseded) <> 'supersede original'
     or (select status::text from public.memories where id = v_superseded) <> 'superseded' then
    raise exception 'FAIL CLOSED: supersession did not preserve the original promoted memory';
  end if;
  if (select content from public.memories where id = v_successor) <> 'supersede corrected'
     or (select supersedes from public.memories where id = v_successor) <> v_superseded
     or (select status::text from public.memories where id = v_successor) <> 'active' then
    raise exception 'FAIL CLOSED: supersession did not append a successor';
  end if;
  raise notice 'detection.supersession=preserves_original';

  insert into public.wiki_pages(path, title, content, status, owner, visibility, source_agent)
  values ('fixture/promoted-page', 'Fixture', 'active original', 'active', 'shared', 'shared', 'system')
  returning id into v_wiki_old;
  if public.bless_doc('fixture/promoted-page', 'fixture blessing') not like 'blessed:%' then
    raise exception 'FAIL CLOSED: fixture wiki page was not blessed';
  end if;
  select state into v_state from public.verify_doc_integrity('fixture/promoted-page');
  if v_state <> 'match' then
    raise exception 'FAIL CLOSED: freshly blessed wiki page state %', v_state;
  end if;

  insert into public.wiki_pages(path, title, content, status, owner, visibility, source_agent)
  values ('fixture/promoted-page', 'Fixture candidate', 'candidate draft', 'proposed', 'shared', 'shared', 'system');
  update public.wiki_pages
  set content = 'candidate revised'
  where path = 'fixture/promoted-page' and status = 'proposed';
  select content into v_text
  from public.wiki_pages
  where path = 'fixture/promoted-page' and status = 'proposed';
  if v_text <> 'candidate revised' then
    raise exception 'FAIL CLOSED: candidate wiki edit was not allowed';
  end if;
  select state into v_state from public.verify_doc_integrity('fixture/promoted-page');
  if v_state <> 'match' then
    raise exception 'FAIL CLOSED: candidate wiki edit disturbed promoted integrity (%)', v_state;
  end if;
  raise notice 'detection.candidate_wiki_edit=allowed';

  update public.wiki_pages
  set content = 'active silently rewritten'
  where id = v_wiki_old and status = 'active';
  select state into v_state from public.verify_doc_integrity('fixture/promoted-page');
  if v_state = 'match' then
    raise exception 'FAIL CLOSED: silent promoted-record edit reported as match';
  end if;
  if v_state = 'no-blessing' then
    raise exception 'FAIL CLOSED: blessed wiki silent edit reported as no receipt';
  end if;
  if v_state <> 'mismatch' then
    raise exception 'FAIL CLOSED: silent promoted wiki edit not detected (%)', v_state;
  end if;
  raise notice 'detection.promoted_wiki_silent_edit=mismatch';

  insert into public.wiki_pages(path, title, content, status, owner, visibility, source_agent)
  values ('fixture/unblessed-page', 'Unblessed', 'unblessed original', 'active', 'shared', 'shared', 'system');
  select state into v_state from public.verify_doc_integrity('fixture/unblessed-page');
  if v_state in ('match', 'mismatch') or v_state <> 'no-blessing' then
    raise exception 'FAIL CLOSED: missing wiki receipt reported as %', v_state;
  end if;
  update public.wiki_pages
  set content = 'unblessed rewritten'
  where path = 'fixture/unblessed-page' and status = 'active';
  select state into v_state from public.verify_doc_integrity('fixture/unblessed-page');
  if v_state in ('match', 'mismatch') or v_state <> 'no-blessing' then
    raise exception 'FAIL CLOSED: unaudited wiki edit reported as %', v_state;
  end if;
  raise notice 'detection.unblessed_wiki=no-blessing';

  if public.bless_doc('fixture/promoted-page', 'overwrite after silent edit') not like 'blessed:%' then
    raise exception 'FAIL CLOSED: re-bless after silent edit failed';
  end if;
  select state into v_state from public.verify_doc_integrity('fixture/promoted-page');
  select count(*) into v_receipts from public.doc_integrity where path = 'fixture/promoted-page';
  if v_state <> 'match' or v_receipts <> 1 then
    raise exception 'FAIL CLOSED: re-bless did not overwrite a single hash receipt (state=%, receipts=%)', v_state, v_receipts;
  end if;
  -- The new match agrees with the rewritten bytes. It does not authenticate anyone.
  raise notice 'detection.hash_is_not_a_signature=true';

  v_wiki_new := public.supersede_wiki('fixture/unblessed-page', 'wiki successor', 'system');
  if (select content from public.wiki_pages where path = 'fixture/unblessed-page' and status = 'superseded' order by created_at desc limit 1) <> 'unblessed rewritten'
     or (select content from public.wiki_pages where id = v_wiki_new) <> 'wiki successor'
     or (select supersedes from public.wiki_pages where id = v_wiki_new) is null then
    raise exception 'FAIL CLOSED: wiki supersession did not preserve the previous page';
  end if;
  raise notice 'detection.wiki_supersession=preserves_original';

  begin
    update public.memories
    set content = 'unsourced figure $12'
    where id = v_candidate and status = 'proposed';
    raise exception 'FAIL CLOSED: provenance guard accepted an unsourced figure';
  exception
    when others then
      if sqlerrm not like 'FINANCIAL PROVENANCE REQUIRED:%' then
        raise;
      end if;
  end;
  select content, status::text into v_text, v_state
  from public.memories where id = v_candidate;
  if v_text <> 'candidate revised' or v_state <> 'proposed' then
    raise exception 'FAIL CLOSED: provenance rejection altered the candidate (content=%, status=%)', v_text, v_state;
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgname = 'financial_provenance'
      and tgrelid = 'public.memories'::regclass
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgname = 'wiki_financial_provenance'
      and tgrelid = 'public.wiki_pages'::regclass
      and not tgisinternal
  ) then
    raise exception 'FAIL CLOSED: provenance trigger missing';
  end if;
  raise notice 'detection.provenance_guard=intact';
end $$;
