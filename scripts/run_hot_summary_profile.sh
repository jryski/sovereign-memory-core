#!/usr/bin/env bash
# Apply the reference schema to a disposable database and run the synthetic
# hot-summary probe. This script does not read a private instruction corpus.
# DATABASE_URL must name a local disposable database. The script does not
# choose a hosted target.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is required and must name a disposable local database" >&2
  exit 1
fi

db_name="${DATABASE_URL##*/}"
db_name="${db_name%%\?*}"
if [[ ! "$db_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "DATABASE_URL database name must be a plain identifier" >&2
  exit 1
fi

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
create schema if not exists extensions;
do \$\$ begin
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end \$\$;
alter database "${db_name}" set sovereign_memory.perimeter_profile to 'supabase';
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role pg_database_owner revoke execute on functions from public;
SQL

for file in \
  sql/01_core.sql \
  sql/07_work_lessons.sql \
  sql/08_attention_events.sql \
  sql/09_perimeter_refresh.sql \
  sql/10_security_definer_hardening.sql \
  sql/11_perimeter_evaluability.sql
do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/$file"
done

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/tests/12_hot_summary_profile.sql"
