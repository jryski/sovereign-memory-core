-- ============================================================================
-- SOVEREIGN MEMORY :: PROVENANCE GUARDS (optional; run after 01_core.sql)
-- "Facts need sources," enforced by the database, not by agent discipline.
--
-- These triggers detect financial figures in Tier 1 content (memories and
-- wiki_pages) and REJECT the write unless it carries a real provenance basis
-- and a specific citation, OR is honestly labeled as an unverified estimate
-- with capped confidence. No model can quietly launder a number into your
-- source of truth.
--
-- Accepted bases:  human_direct, decision_record, imported_artifact, source_document
-- Rejected always: agent_summary, agent_inference, unset, placeholder citations
-- ============================================================================

-- memories: provenance lives in metadata jsonb
create or replace function enforce_financial_provenance()
returns trigger language plpgsql set search_path to 'public'
as $fn$
declare
  has_figure boolean;
  v_basis text; v_citation text; v_unverified boolean;
  v_placeholder text[] := array['none','unknown','memory','estimate','web','supplier','source','tbd','n/a','na',''];
begin
  has_figure := new.content ~ '\$[0-9]'
    or new.content ~* '[0-9][0-9,\.]*\s*(/\s*kg|per\s*kg|/\s*lb|/\s*g\b|usd|eur|gbp|/month|/yr|/year|/unit)'
    or new.content ~* '(margin|cogs|moq|revenue|gross\s*margin)\D*[0-9]';
  if not has_figure then return new; end if;

  v_basis      := new.metadata->>'basis';
  v_citation   := lower(trim(coalesce(new.metadata->>'source_citation','')));
  v_unverified := coalesce((new.metadata->>'financial_unverified')::boolean, false);

  -- honest unverified estimate: allowed, but cannot masquerade as high-confidence fact
  if v_unverified then
    if new.confidence is not null and new.confidence > 0.60 and v_basis is distinct from 'human_direct' then
      raise exception 'UNVERIFIED FINANCIAL: financial_unverified=true requires confidence <= 0.60 (or basis=human_direct). Got confidence=%.', new.confidence;
    end if;
    return new;
  end if;

  if v_basis in ('human_direct','decision_record','imported_artifact','source_document')
     and v_citation <> '' and not (v_citation = any(v_placeholder)) then
    return new;
  end if;

  raise exception
    'FINANCIAL PROVENANCE REQUIRED: figure needs metadata.basis in (human_direct,decision_record,imported_artifact,source_document) + a SPECIFIC metadata.source_citation (not a placeholder like %), OR metadata.financial_unverified=true with confidence<=0.60. (basis=%, citation=%)',
    array_to_string(v_placeholder,','), coalesce(v_basis,'null'), coalesce(new.metadata->>'source_citation','null');
end; $fn$;

drop trigger if exists financial_provenance on memories;
create trigger financial_provenance
  before insert or update of content, metadata on memories
  for each row execute function enforce_financial_provenance();

-- wiki_pages: identical logic, but reads FRONTMATTER (wiki has no metadata col).
-- Lesson learned the hard way: a shared function reading the wrong column
-- hard-errors on every write. Keep the two functions separate and explicit.
create or replace function enforce_wiki_financial_provenance()
returns trigger language plpgsql set search_path to 'public'
as $fn$
declare
  has_figure boolean;
  v_basis text; v_citation text; v_unverified boolean;
  v_placeholder text[] := array['none','unknown','memory','estimate','web','supplier','source','tbd','n/a','na',''];
begin
  has_figure := new.content ~ '\$[0-9]'
    or new.content ~* '[0-9][0-9,\.]*\s*(/\s*kg|per\s*kg|/\s*lb|/\s*g\b|usd|eur|gbp|/month|/yr|/year|/unit)'
    or new.content ~* '(margin|cogs|moq|revenue|gross\s*margin)\D*[0-9]';
  if not has_figure then return new; end if;

  v_basis      := new.frontmatter->>'basis';
  v_citation   := lower(trim(coalesce(new.frontmatter->>'source_citation','')));
  v_unverified := coalesce((new.frontmatter->>'financial_unverified')::boolean, false);

  if v_unverified then
    if new.confidence is not null and new.confidence > 0.60 and v_basis is distinct from 'human_direct' then
      raise exception 'UNVERIFIED FINANCIAL (wiki): financial_unverified=true requires confidence <= 0.60 (or basis=human_direct). Got confidence=%.', new.confidence;
    end if;
    return new;
  end if;

  if v_basis in ('human_direct','decision_record','imported_artifact','source_document')
     and v_citation <> '' and not (v_citation = any(v_placeholder)) then
    return new;
  end if;

  raise exception
    'FINANCIAL PROVENANCE REQUIRED (wiki): figure needs frontmatter.basis in (human_direct,decision_record,imported_artifact,source_document) + a SPECIFIC frontmatter.source_citation (not a placeholder like %), OR frontmatter.financial_unverified=true with confidence<=0.60. (basis=%, citation=%)',
    array_to_string(v_placeholder,','), coalesce(v_basis,'null'), coalesce(new.frontmatter->>'source_citation','null');
end; $fn$;

drop trigger if exists wiki_financial_provenance on wiki_pages;
create trigger wiki_financial_provenance
  before insert or update of content, frontmatter on wiki_pages
  for each row execute function enforce_wiki_financial_provenance();

-- Re-close the perimeter (new functions were created above; Supabase may have
-- auto-granted). ALWAYS end migrations that create objects with this pair.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;
select assert_perimeter_closed();
