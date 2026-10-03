-- Disposable synthetic hot-summary profile probe.
-- Refs #70. This file does not replace or migrate the installed functions.
--
-- Main-branch hardened profile coordinates (unchanged by this probe):
--   public.hot_touch
--     sql/10_security_definer_hardening.sql lines 960-986
--   public.supersede_memory
--     sql/10_security_definer_hardening.sql lines 1278-1300
--   public.session_boot
--     sql/10_security_definer_hardening.sql lines 1246-1276
--
-- session_boot exposes the indexed summary at hot_topics[].summary through
-- attention_boot_projection_v2. This probe reads that existing field. It does
-- not add an attestation function.
--
-- Evaluated cases, all with synthetic labels:
--   1. index "Device mode alpha" with an explicit summary
--   2. supersede with explicit summary "Device mode beta"
--   3. repeated hot_touch calls and a second supersede keep the successor summary
--   4. omitted summaries follow the memory content
--   5. a rejected correction leaves the indexed pointer and summary unchanged
--   6. a deliberately stale summary fails the owning assertion

\set ON_ERROR_STOP on

begin;

create function pg_temp.hot_summary_agrees(
  p_topic text,
  p_owner text,
  p_memory uuid,
  p_summary text
) returns void
language plpgsql
as $$
declare
  v_id uuid;
  v_summary text;
  v_boot text;
begin
  select memory_id, summary
    into v_id, v_summary
  from public.memory_hot_index
  where topic_key = p_topic
    and owner = p_owner;
  if v_id is distinct from p_memory or v_summary is distinct from p_summary then
    raise exception
      'hot summary assertion failed for %, indexed %/%, expected %/%',
      p_topic, v_id, v_summary, p_memory, p_summary;
  end if;
  select element->>'summary'
    into v_boot
  from jsonb_array_elements(public.session_boot(p_owner)->'hot_topics') element
  where element->>'topic_key' = p_topic;
  if v_boot is distinct from p_summary then
    raise exception
      'hot summary assertion failed for %, session_boot summary %, expected %',
      p_topic, v_boot, p_summary;
  end if;
end;
$$;

do $$
declare
  v_alpha uuid;
  v_beta uuid;
  v_repeated uuid;
  v_omitted_alpha uuid;
  v_omitted_beta uuid;
  v_touch integer;
  v_status text;
  v_content text;
  v_summary text;
  v_pointer uuid;
  v_boot_first text;
  v_boot_second text;
begin
  v_alpha := public.remember(
    p_content => 'Synthetic predecessor body for device mode alpha',
    p_workstream => 'synthetic-lab',
    p_topic_key => 'synthetic/device-mode',
    p_source_agent => 'example-user-claude',
    p_owner => 'example-user',
    p_summary => 'Device mode alpha',
    p_tags => array['synthetic']::text[],
    p_visibility => 'shared'
  );
  perform pg_temp.hot_summary_agrees(
    'synthetic/device-mode', 'example-user', v_alpha, 'Device mode alpha'
  );
  raise notice 'case 1 indexed Device mode alpha at %', v_alpha;

  v_beta := public.supersede_memory(
    v_alpha,
    'Synthetic successor body for device mode beta',
    'example-user-claude',
    'Device mode beta'
  );
  select status into v_status from public.memories where id = v_alpha;
  if v_status is distinct from 'superseded' then
    raise exception 'predecessor status is %, expected superseded', v_status;
  end if;
  select content into v_content from public.memories where id = v_beta and status = 'active';
  if v_content is distinct from 'Synthetic successor body for device mode beta' then
    raise exception 'successor content did not follow the pointer: %', v_content;
  end if;
  perform pg_temp.hot_summary_agrees(
    'synthetic/device-mode', 'example-user', v_beta, 'Device mode beta'
  );
  if (select summary from public.memory_hot_index
      where topic_key = 'synthetic/device-mode' and owner = 'example-user')
     is distinct from 'Device mode beta' then
    raise exception 'indexed summary did not agree with the successor';
  end if;
  raise notice 'case 2 superseded with Device mode beta at %', v_beta;

  perform public.hot_touch('synthetic/device-mode', v_beta, 'Device mode beta', 'synthetic-lab');
  perform public.hot_touch('synthetic/device-mode', v_beta, 'Device mode beta', 'synthetic-lab');
  perform public.hot_touch('synthetic/device-mode', v_beta, 'Device mode beta', 'synthetic-lab');
  select touch_count into v_touch
  from public.memory_hot_index
  where topic_key = 'synthetic/device-mode' and owner = 'example-user';
  if v_touch is distinct from 4 then
    raise exception 'repeated hot_touch touch_count is %, expected 4', v_touch;
  end if;
  select element->>'summary' into v_boot_first
  from jsonb_array_elements(public.session_boot('example-user')->'hot_topics') element
  where element->>'topic_key' = 'synthetic/device-mode';
  select element->>'summary' into v_boot_second
  from jsonb_array_elements(public.session_boot('example-user')->'hot_topics') element
  where element->>'topic_key' = 'synthetic/device-mode';
  if v_boot_first is distinct from 'Device mode beta'
     or v_boot_second is distinct from 'Device mode beta' then
    raise exception 'repeated session_boot did not keep Device mode beta';
  end if;

  v_repeated := public.supersede_memory(
    v_beta,
    'Synthetic repeated successor for device mode beta',
    'example-user-claude',
    'Device mode beta'
  );
  perform pg_temp.hot_summary_agrees(
    'synthetic/device-mode', 'example-user', v_repeated, 'Device mode beta'
  );
  raise notice 'case 3 repeated calls kept Device mode beta at %', v_repeated;

  v_omitted_alpha := public.remember(
    p_content => 'Device mode alpha',
    p_workstream => 'synthetic-lab',
    p_topic_key => 'synthetic/device-mode-omitted',
    p_source_agent => 'example-user-claude',
    p_owner => 'example-user',
    p_tags => array['synthetic']::text[]
  );
  perform pg_temp.hot_summary_agrees(
    'synthetic/device-mode-omitted', 'example-user', v_omitted_alpha, 'Device mode alpha'
  );
  v_omitted_beta := public.supersede_memory(
    v_omitted_alpha,
    'Device mode beta',
    'example-user-claude'
  );
  perform pg_temp.hot_summary_agrees(
    'synthetic/device-mode-omitted', 'example-user', v_omitted_beta, 'Device mode beta'
  );
  raise notice 'case 4 omitted summaries followed Device mode alpha then Device mode beta';

  select memory_id, summary into v_pointer, v_summary
  from public.memory_hot_index
  where topic_key = 'synthetic/device-mode' and owner = 'example-user';
  begin
    perform public.supersede_memory(
      v_pointer,
      'Device mode rejected',
      'synthetic-untrusted-agent',
      'Device mode rejected'
    );
    raise exception 'rejected correction unexpectedly succeeded';
  exception
    when others then
      if sqlerrm not like '%unknown/inactive source_agent%' then
        raise;
      end if;
  end;
  begin
    perform public.supersede_memory(
      v_alpha,
      'Device mode rejected',
      'example-user-claude',
      'Device mode rejected'
    );
    raise exception 'supersede of inactive predecessor unexpectedly succeeded';
  exception
    when others then
      if sqlerrm not like '%not active%' then
        raise;
      end if;
  end;
  perform pg_temp.hot_summary_agrees(
    'synthetic/device-mode', 'example-user', v_pointer, v_summary
  );
  raise notice 'case 5 rejected corrections left % / % unchanged', v_pointer, v_summary;

  begin
    update public.memory_hot_index
       set summary = 'Device mode alpha'
     where topic_key = 'synthetic/device-mode'
       and owner = 'example-user';
    perform pg_temp.hot_summary_agrees(
      'synthetic/device-mode', 'example-user', v_pointer, 'Device mode beta'
    );
    raise exception 'stale-summary variant unexpectedly passed';
  exception
    when others then
      if sqlerrm not like 'hot summary assertion failed%' then
        raise;
      end if;
  end;
  perform pg_temp.hot_summary_agrees(
    'synthetic/device-mode', 'example-user', v_pointer, 'Device mode beta'
  );
  raise notice 'case 6 stale-summary variant failed its assertion and the successor summary remains';
end;
$$;

select 'hot_summary_profile_ok' as probe;

rollback;
