-- ============================================================================
-- SOVEREIGN MEMORY :: TOPOLOGY / SEARCH-SCOPE CORRECTNESS V1
-- Issue #72. Target: PostgreSQL 15+. Run after 10_security_definer_hardening.sql.
--
-- Topology rows are non-secret deployment-configuration evidence. They are not
-- routing authority and contain no endpoints or credentials. The public seams
-- filter rows by viewer, bound input/output, and retain local read-only boot when
-- topology or contract attestation is incomplete.
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.session_boot(text)') IS NULL
     OR to_regclass('public.perimeter_authority_function_registry') IS NULL THEN
    RAISE EXCEPTION 'topology/scope migration requires migrations 01 and 07 through 10';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.store_topology_profile (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  schema_name text NOT NULL DEFAULT 'sovereign-memory/topology-profile'
    CHECK (schema_name='sovereign-memory/topology-profile'),
  schema_version text NOT NULL DEFAULT '1' CHECK (schema_version='1'),
  topology_state text NOT NULL DEFAULT 'not_configured'
    CHECK (topology_state IN ('configured','unknown','not_configured')),
  contract_version text NOT NULL DEFAULT 'topology-scope/1'
    CHECK (contract_version ~ '[^[:space:]]' AND char_length(contract_version)<=64),
  contract_digest text NOT NULL DEFAULT '938976903383ef5cf43af48ffe5e03a3f1be212cff5d1ea947caef2debec82fd'
    CHECK (contract_digest ~ '^[0-9a-f]{64}$'),
  observed_contract_version text
    CHECK (observed_contract_version IS NULL OR (observed_contract_version ~ '[^[:space:]]' AND char_length(observed_contract_version)<=64)),
  observed_contract_digest text
    CHECK (observed_contract_digest IS NULL OR observed_contract_digest ~ '^[0-9a-f]{64}$'),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.known_memory_stores (
  store_id text PRIMARY KEY,
  store_profile text NOT NULL,
  relationship text NOT NULL CHECK (relationship IN ('local','peer')),
  search_scope text NOT NULL,
  owner text NOT NULL DEFAULT 'shared',
  visibility text NOT NULL DEFAULT 'shared' CHECK (visibility IN ('shared','private')),
  enabled boolean NOT NULL DEFAULT true,
  advertised boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (visibility<>'private' OR owner<>'shared')
);
ALTER TABLE public.store_topology_profile
  DROP COLUMN IF EXISTS local_store_id,
  DROP COLUMN IF EXISTS local_store_profile;
ALTER TABLE public.known_memory_stores
  DROP CONSTRAINT IF EXISTS known_memory_stores_identifier_contract,
  ADD CONSTRAINT known_memory_stores_identifier_contract CHECK (
    store_id ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    AND store_profile ~ '^[a-z0-9][a-z0-9._-]{0,63}$'
    AND search_scope ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    AND owner ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
  ),
  DROP CONSTRAINT IF EXISTS known_memory_stores_local_public,
  ADD CONSTRAINT known_memory_stores_local_public CHECK (
    relationship<>'local' OR
    (visibility='shared' AND owner='shared' AND enabled AND advertised)
  );
CREATE UNIQUE INDEX IF NOT EXISTS known_memory_stores_one_local
  ON public.known_memory_stores (relationship) WHERE relationship='local';

INSERT INTO public.store_topology_profile(singleton)
VALUES (true) ON CONFLICT (singleton) DO NOTHING;
INSERT INTO public.known_memory_stores(store_id,store_profile,relationship,search_scope,owner,visibility)
VALUES ('local-store','portable','local','default','shared','shared')
ON CONFLICT (store_id) DO NOTHING;

COMMENT ON TABLE public.store_topology_profile IS
  'Non-secret deployment configuration evidence for issue #72; not routing or search authority.';
COMMENT ON TABLE public.known_memory_stores IS
  'Viewer-scoped advertised-store metadata; no endpoints, credentials, or authoritative search claims.';

ALTER TABLE public.store_topology_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_topology_profile FORCE ROW LEVEL SECURITY;
ALTER TABLE public.known_memory_stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.known_memory_stores FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.store_topology_profile,public.known_memory_stores FROM PUBLIC;

DO $$
DECLARE v_owner text:=current_user;
BEGIN
  DROP POLICY IF EXISTS store_topology_profile_owner_all ON public.store_topology_profile;
  DROP POLICY IF EXISTS known_memory_stores_owner_all ON public.known_memory_stores;
  EXECUTE format('CREATE POLICY store_topology_profile_owner_all ON public.store_topology_profile FOR ALL TO %I USING (true) WITH CHECK (true)',v_owner);
  EXECUTE format('CREATE POLICY known_memory_stores_owner_all ON public.known_memory_stores FOR ALL TO %I USING (true) WITH CHECK (true)',v_owner);
END $$;

CREATE OR REPLACE FUNCTION public.topology_profile_boot(p_viewer text)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','pg_temp'
AS $function$
WITH raw_profile AS (
  SELECT singleton,schema_name,schema_version,topology_state,
         contract_version,contract_digest,observed_contract_version,
         observed_contract_digest,updated_at
  FROM public.store_topology_profile WHERE singleton
  UNION ALL
  SELECT true,'sovereign-memory/topology-profile','1','unknown',
         'topology-scope/1',
         '938976903383ef5cf43af48ffe5e03a3f1be212cff5d1ea947caef2debec82fd',
         NULL::text,NULL::text,statement_timestamp()
  WHERE NOT EXISTS(SELECT 1 FROM public.store_topology_profile WHERE singleton)
), profile AS (
  SELECT r.*,
         CASE
           WHEN r.topology_state='configured' AND NOT EXISTS(
             SELECT 1 FROM public.known_memory_stores s
             WHERE s.relationship='local' AND s.advertised AND s.enabled
               AND s.visibility='shared'
           ) THEN 'unknown'
           ELSE r.topology_state
         END effective_topology_state
  FROM raw_profile r
), visible AS (
  SELECT s.*
  FROM public.known_memory_stores s
  -- p_viewer is logical filtering, not authentication under a shared runtime
  -- credential. Public topology is therefore sanitized to shared rows only.
  WHERE s.advertised AND s.visibility='shared'
), counted AS (
  SELECT count(*)::integer total_visible FROM visible
), bounded AS (
  SELECT * FROM visible
  ORDER BY CASE relationship WHEN 'local' THEN 0 ELSE 1 END,store_id
  LIMIT 32
), represented AS (
  SELECT count(*)::integer represented FROM bounded
), stores AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'store_id',b.store_id,
    'profile',b.store_profile,
    'relationship',b.relationship,
    'search_scope',b.search_scope,
    'configuration_state',CASE
      WHEN p.effective_topology_state='unknown' THEN 'unknown'
      WHEN p.effective_topology_state='not_configured' THEN 'not_configured'
      WHEN NOT b.enabled THEN 'disabled'
      ELSE 'configured'
    END,
    'coverage_state',CASE
      WHEN p.effective_topology_state='unknown' THEN 'unknown'
      WHEN p.effective_topology_state='not_configured' OR NOT b.enabled THEN 'not_applicable'
      ELSE 'not_queried'
    END
  ) ORDER BY CASE b.relationship WHEN 'local' THEN 0 ELSE 1 END,b.store_id),'[]'::jsonb) payload
  FROM bounded b CROSS JOIN profile p
), attestation AS (
  SELECT CASE
    WHEN observed_contract_version IS NULL OR observed_contract_digest IS NULL THEN 'unknown'
    WHEN observed_contract_version=contract_version AND observed_contract_digest=contract_digest THEN 'match'
    ELSE 'mismatch'
  END status
  FROM profile
)
SELECT jsonb_build_object(
  'schema',p.schema_name,
  'version',p.schema_version,
  'state',p.effective_topology_state,
  'local_store',coalesce((SELECT jsonb_build_object('store_id',v.store_id,'profile',v.store_profile)
                          FROM visible v WHERE v.relationship='local' LIMIT 1),
                         jsonb_build_object('store_id','unknown','profile','unknown')),
  'visible_known_stores',s.payload,
  'coverage',jsonb_build_object(
    'total_visible',c.total_visible,
    'represented',r.represented,
    'omitted',c.total_visible-r.represented,
    'limit',32,
    'status',CASE WHEN c.total_visible=r.represented THEN 'complete' ELSE 'bounded' END
  ),
  'attestation',jsonb_build_object(
    'contract_version',p.contract_version,
    'contract_digest',p.contract_digest,
    'observed_version',p.observed_contract_version,
    'observed_digest',p.observed_contract_digest,
    'status',a.status,
    'authority','deployment-metadata-evidence'
  ),
  'read_only_local_available',true
)
FROM profile p CROSS JOIN counted c CROSS JOIN represented r CROSS JOIN stores s CROSS JOIN attestation a;
$function$;

CREATE OR REPLACE FUNCTION public.search_coverage_receipt(p_viewer text,p_attempts jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','pg_temp'
AS $function$
DECLARE
  v_attempt jsonb;
  v_attempts jsonb;
  v_index integer:=0;
  v_store_id text;
  v_scope text;
  v_status text;
  v_count_text text;
  v_hit_count integer;
  v_seen text[]:=ARRAY[]::text[];
  v_local_id text;
  v_topology_state text;
  v_visible_enabled integer;
  v_local_hits integer:=0;
  v_remote_hits integer:=0;
  v_queried integer:=0;
  v_unreachable integer:=0;
  v_classification text;
  v_attempt_rows jsonb:='[]'::jsonb;
BEGIN
  -- Stable precedence: envelope/version, bound, object/keys, scalar types, status,
  -- duplicate, visible-store identity/scope, then count range/semantics.
  IF p_attempts IS NULL OR jsonb_typeof(p_attempts)<>'object' THEN
    RAISE EXCEPTION 'search coverage receipt must be a JSON object';
  END IF;
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_attempts) key)
     IS DISTINCT FROM ARRAY['attempts','schema_version']::text[] THEN
    RAISE EXCEPTION 'search coverage receipt must contain exactly attempts, schema_version';
  END IF;
  IF jsonb_typeof(p_attempts->'schema_version')<>'string'
     OR p_attempts->>'schema_version'<>'1' THEN
    RAISE EXCEPTION 'unsupported search coverage schema_version';
  END IF;
  v_attempts:=p_attempts->'attempts';
  IF jsonb_typeof(v_attempts)<>'array' THEN
    RAISE EXCEPTION 'search coverage attempts must be a JSON array';
  END IF;
  IF jsonb_array_length(v_attempts)>32 THEN
    RAISE EXCEPTION 'search coverage attempts exceed maximum 32';
  END IF;

  SELECT l.store_id,
         CASE
           WHEN p.topology_state='configured' AND l.store_id IS NULL THEN 'unknown'
           ELSE p.topology_state
         END
  INTO v_local_id,v_topology_state
  FROM public.store_topology_profile p
  LEFT JOIN LATERAL (
    SELECT s.store_id FROM public.known_memory_stores s
    WHERE s.relationship='local' AND s.advertised AND s.enabled
      AND s.visibility='shared'
    LIMIT 1
  ) l ON true
  WHERE p.singleton;

  FOR v_attempt IN
    SELECT value FROM jsonb_array_elements(v_attempts)
    ORDER BY value->>'store_id',value::text
  LOOP
    v_index:=v_index+1;
    IF jsonb_typeof(v_attempt)<>'object' THEN
      RAISE EXCEPTION 'search coverage attempt % must be an object',v_index;
    END IF;
    IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_attempt) key)
       IS DISTINCT FROM ARRAY['hit_count','scope','status','store_id']::text[] THEN
      RAISE EXCEPTION 'search coverage attempt % must contain exactly hit_count, scope, status, store_id',v_index;
    END IF;
    IF jsonb_typeof(v_attempt->'store_id')<>'string'
       OR jsonb_typeof(v_attempt->'scope')<>'string'
       OR jsonb_typeof(v_attempt->'status')<>'string'
       OR jsonb_typeof(v_attempt->'hit_count')<>'number' THEN
      RAISE EXCEPTION 'search coverage attempt % has invalid JSON types',v_index;
    END IF;
    v_store_id:=v_attempt->>'store_id';
    v_scope:=v_attempt->>'scope';
    v_status:=v_attempt->>'status';
    v_count_text:=v_attempt->>'hit_count';
    IF v_store_id !~ '^[a-z0-9][a-z0-9._-]{0,127}$'
       OR v_scope !~ '^[a-z0-9][a-z0-9._-]{0,127}$' THEN
      RAISE EXCEPTION 'search coverage attempt % has noncanonical identity/scope',v_index;
    END IF;
    IF v_status NOT IN ('queried','unreachable') THEN
      RAISE EXCEPTION 'search coverage attempt % has invalid status',v_index;
    END IF;
    IF v_store_id=ANY(v_seen) THEN
      RAISE EXCEPTION 'search coverage attempt % duplicates store_id %',v_index,v_store_id;
    END IF;
    v_seen:=array_append(v_seen,v_store_id);
    IF NOT EXISTS(
      SELECT 1 FROM public.known_memory_stores s
      WHERE s.store_id=v_store_id AND s.advertised AND s.enabled
        AND s.visibility='shared'
    ) THEN
      RAISE EXCEPTION 'search coverage attempt % has unknown visible store_id',v_index;
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM public.known_memory_stores s
      WHERE s.store_id=v_store_id AND s.search_scope=v_scope
        AND s.advertised AND s.enabled
        AND s.visibility='shared'
    ) THEN
      RAISE EXCEPTION 'search coverage attempt % scope does not match visible store',v_index;
    END IF;
    IF v_count_text !~ '^(0|[1-9][0-9]*)$' THEN
      RAISE EXCEPTION 'search coverage attempt % hit_count must be an integer',v_index;
    END IF;
    BEGIN
      v_hit_count:=v_count_text::integer;
    EXCEPTION WHEN numeric_value_out_of_range THEN
      RAISE EXCEPTION 'search coverage attempt % hit_count exceeds maximum 1000000',v_index;
    END;
    IF v_hit_count>1000000 THEN
      RAISE EXCEPTION 'search coverage attempt % hit_count exceeds maximum 1000000',v_index;
    END IF;
    IF v_status='unreachable' AND v_hit_count<>0 THEN
      RAISE EXCEPTION 'search coverage attempt % unreachable hit_count must be zero',v_index;
    END IF;

    IF v_status='queried' THEN
      v_queried:=v_queried+1;
      IF v_store_id=v_local_id THEN v_local_hits:=v_local_hits+v_hit_count;
      ELSE v_remote_hits:=v_remote_hits+v_hit_count; END IF;
    ELSE
      v_unreachable:=v_unreachable+1;
    END IF;
    v_attempt_rows:=v_attempt_rows||jsonb_build_array(jsonb_build_object(
      'store_id',v_store_id,'scope',v_scope,'coverage_state',v_status,'hit_count',v_hit_count
    ));
  END LOOP;

  SELECT count(*)::integer INTO v_visible_enabled
  FROM public.known_memory_stores s
  WHERE s.advertised AND s.enabled AND s.visibility='shared';

  SELECT coalesce(jsonb_agg(value ORDER BY value->>'store_id'),'[]'::jsonb)
  INTO v_attempt_rows FROM jsonb_array_elements(v_attempt_rows);

  v_classification:=CASE
    WHEN v_topology_state<>'configured' OR v_local_id IS NULL OR v_visible_enabled>32 THEN 'unknown_topology'
    WHEN v_local_hits>0 THEN 'local_hit'
    WHEN v_remote_hits>0 THEN 'remote_hit'
    WHEN v_unreachable>0 THEN 'unreachable_peer'
    WHEN v_queried<v_visible_enabled THEN 'partial_miss'
    ELSE 'complete_miss'
  END;

  RETURN jsonb_build_object(
    'schema','sovereign-memory/search-coverage-receipt',
    'version','1',
    'coverage_source','client-reported',
    'authority','client-reported-coverage-not-search-authority',
    'viewer',p_viewer,
    'classification',v_classification,
    'coverage_complete',(v_topology_state='configured' AND v_visible_enabled<=32
                         AND v_local_id IS NOT NULL
                         AND v_queried=v_visible_enabled AND v_unreachable=0),
    'global_absence_supported',(v_classification='complete_miss'
                                AND v_topology_state='configured'
                                AND v_local_id IS NOT NULL
                                AND v_visible_enabled<=32
                                AND v_queried=v_visible_enabled
                                AND v_unreachable=0),
    'visible_advertised_stores',v_visible_enabled,
    'queried_stores',v_queried,
    'unreachable_stores',v_unreachable,
    'advertised_unqueried_stores',greatest(v_visible_enabled-v_queried-v_unreachable,0),
    'total_hits',v_local_hits+v_remote_hits,
    'attempts',v_attempt_rows
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.session_boot(p_viewer text DEFAULT 'shared'::text)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','pg_temp'
AS $function$
WITH attention AS (
  SELECT public.attention_boot_projection_v2(p_viewer,12000,240) payload
), inbox_total AS (
  SELECT count(*)::integer total
  FROM public.household_channel
  WHERE status='open' AND to_principal IN (p_viewer,'shared')
), inbox_rows AS (
  SELECT jsonb_build_object(
    'seq',seq,'from',from_agent,'kind',kind,'subject',subject,
    'due_at',due_at,'add_to_calendar',add_to_calendar,'created_at',created_at,
    'age_seconds',greatest(0,floor(extract(epoch FROM (now()-created_at)))::bigint),
    'blocking',(kind IN ('task','todo') AND (due_at IS NULL OR due_at<=now())),
    'stale',(created_at<=now()-interval '7 days')
  ) item
  FROM public.household_channel
  WHERE status='open' AND to_principal IN (p_viewer,'shared')
  ORDER BY due_at ASC NULLS LAST,created_at ASC,seq ASC
  LIMIT 25
), inbox AS (
  SELECT coalesce(jsonb_agg(item),'[]'::jsonb) payload,count(*)::integer represented
  FROM inbox_rows
)
SELECT jsonb_build_object(
  'viewer',p_viewer,
  'topology',public.topology_profile_boot(p_viewer),
  'hot_topics',(SELECT payload->'topics' FROM attention),
  'attention_coverage',(SELECT payload->'coverage' FROM attention),
  'work_lessons',public.work_lessons_boot_fragment(),
  'deadlines',(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'content',left(content,100),'owner',owner,'due_date',due_date,'overdue',overdue,'days_until',days_until
  ) ORDER BY due_date),'[]'::jsonb) FROM public.deadlines_upcoming WHERE visibility='shared' OR owner=p_viewer),
  'channel_inbox',i.payload,
  'channel_inbox_coverage',jsonb_build_object(
    'total_visible',t.total,'represented',i.represented,'omitted',t.total-i.represented,
    'limit',25,'status',CASE WHEN t.total=i.represented THEN 'complete' ELSE 'bounded' END
  ),
  'instruction_integrity',(SELECT state FROM public.verify_doc_integrity('_system/ai-instructions')),
  'health',jsonb_build_object(
    'memories_visible',(SELECT count(*) FROM public.memories WHERE status='active' AND (visibility='shared' OR owner=p_viewer)),
    'hot_touch_pending',(SELECT count(*) FROM public.hot_touch_pending WHERE owner=p_viewer OR owner='shared'),
    'attention_events',(SELECT count(*) FROM public.attention_events),
    'attention_events_unassigned',(SELECT count(*) FROM public.attention_events e WHERE NOT EXISTS(SELECT 1 FROM public.attention_event_assignments a WHERE a.event_id=e.id)),
    'proposed_for_review',(SELECT count(*) FROM public.memories WHERE status='proposed' AND (visibility='shared' OR owner=p_viewer))
  ),
  'booted_at',now()
)
FROM inbox_total t CROSS JOIN inbox i;
$function$;

REVOKE ALL ON FUNCTION public.topology_profile_boot(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.search_coverage_receipt(text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.session_boot(text) FROM PUBLIC;

DO $$
DECLARE r text;v_allowed text[];
BEGIN
  FOR r IN SELECT rolname FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role') LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.store_topology_profile,public.known_memory_stores FROM %I',r);
    EXECUTE format('REVOKE ALL ON FUNCTION public.topology_profile_boot(text) FROM %I',r);
    EXECUTE format('REVOKE ALL ON FUNCTION public.search_coverage_receipt(text,jsonb) FROM %I',r);
  END LOOP;
  SELECT function_execute_roles INTO v_allowed
  FROM public.perimeter_acl_policy WHERE singleton;
  IF 'service_role'=ANY(coalesce(v_allowed,ARRAY[]::text[])) THEN
    GRANT EXECUTE ON FUNCTION public.topology_profile_boot(text) TO service_role;
    GRANT EXECUTE ON FUNCTION public.search_coverage_receipt(text,jsonb) TO service_role;
    GRANT EXECUTE ON FUNCTION public.session_boot(text) TO service_role;
  ELSIF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    REVOKE ALL ON FUNCTION public.session_boot(text) FROM service_role;
  END IF;
END $$;

INSERT INTO public.perimeter_authority_function_registry(function_identity,is_internal) VALUES
  ('public.topology_profile_boot(text)',false),
  ('public.search_coverage_receipt(text,jsonb)',false)
ON CONFLICT(function_identity) DO UPDATE SET is_internal=excluded.is_internal;

SELECT public.assert_perimeter_closed();
