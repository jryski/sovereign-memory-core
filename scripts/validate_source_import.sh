#!/usr/bin/env bash
set -euo pipefail

# Validate the Sovereign Memory source-import/cutover reference layer locally.
#
# Usage:
#   DATABASE_URL="postgres://postgres:postgres@localhost:5432/postgres" \
#     bash scripts/validate_source_import.sh
#
# Notes:
# - This is intended for a disposable local database.
# - The script creates the Supabase-compatible `extensions` schema and shim roles
#   (`anon`, `authenticated`, `service_role`) if they do not already exist.
# - If sql/05_candidate_locators.sql exists, the script applies it before validation.
# - The validation fixture rolls back its own staged data.

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is required" >&2
  echo "Example: DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres bash scripts/validate_source_import.sh" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PSQL=(psql "${DATABASE_URL}" -v ON_ERROR_STOP=1)

echo "==> Preparing local Postgres compatibility shims"
"${PSQL[@]}" <<'SQL'
create schema if not exists extensions;

do $$
begin
  if not exists (select 1 from pg_roles where rolname='anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then
    create role service_role nologin;
  end if;
end $$;
SQL

echo "==> Applying Tier 1 core"
"${PSQL[@]}" -f "${ROOT_DIR}/sql/01_core.sql"

echo "==> Applying source import/cutover layer"
"${PSQL[@]}" -f "${ROOT_DIR}/sql/04_source_import.sql"

if [[ -f "${ROOT_DIR}/sql/05_candidate_locators.sql" ]]; then
  echo "==> Applying candidate locator/quote-hash layer"
  "${PSQL[@]}" -f "${ROOT_DIR}/sql/05_candidate_locators.sql"
fi

echo "==> Running source import validation bundle"
"${PSQL[@]}" -f "${ROOT_DIR}/sql/validation/source_import_readiness.sql"

echo "==> Done"
