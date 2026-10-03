#!/usr/bin/env bash
# Disposable promoted-record silent-edit check.
# Creates a local throwaway database, applies the migrations already on main
# through the promotion function, runs tests/promoted_record_silent_edit.sql,
# and drops the database. Refuses any non-local host. Does not contact a
# hosted project and is not applied to any deployment.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

refuse() {
  echo "promoted-record silent-edit check: $*" >&2
  exit 1
}

is_local_host() {
  case "$1" in
    ""|localhost|127.0.0.1|::1) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ -n "${SUPABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_HOST:-}" ]]; then
  refuse "hosted project variables are set; this check does not use them"
fi

if [[ -n "${DATABASE_URL:-}" ]]; then
  command -v python3 >/dev/null 2>&1 || refuse "DATABASE_URL is set and its host cannot be checked"
  url_host="$(python3 - <<'PY'
import os
from urllib.parse import urlparse
print(urlparse(os.environ["DATABASE_URL"]).hostname or "")
PY
)"
  is_local_host "$url_host" || refuse "DATABASE_URL host is not local"
fi

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
is_local_host "$PGHOST" || refuse "refusing non-local PGHOST"

command -v psql >/dev/null 2>&1 || refuse "psql is not installed"
command -v createdb >/dev/null 2>&1 || refuse "createdb is not installed"
command -v dropdb >/dev/null 2>&1 || refuse "dropdb is not installed"
command -v pg_isready >/dev/null 2>&1 || refuse "pg_isready is not installed"

pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" >/dev/null 2>&1 || refuse "local database is not ready"

db="smc_silent_edit_$$"
cleanup() {
  dropdb --if-exists "$db" >/dev/null 2>&1 || true
}
trap cleanup EXIT

createdb "$db"

apply_sql() {
  local log
  log="$(mktemp)"
  if ! psql -d "$db" -v ON_ERROR_STOP=1 "$@" >"$log" 2>&1; then
    cat "$log" >&2
    rm -f "$log"
    refuse "schema apply failed"
  fi
  rm -f "$log"
}

apply_sql <<'SQL'
create schema if not exists extensions;
do $$ begin
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role pg_database_owner revoke execute on functions from public;
SQL
apply_sql -f "$root/sql/01_core.sql"
apply_sql -f "$root/sql/03_provenance_guards.sql"
apply_sql -f "$root/sql/07_work_lessons.sql"
apply_sql -f "$root/sql/08_attention_events.sql"

log="$(mktemp)"
psql -d "$db" -v ON_ERROR_STOP=1 -f "$root/tests/promoted_record_silent_edit.sql" >"$log" 2>&1 || {
  cat "$log" >&2
  rm -f "$log"
  refuse "negative check failed"
}

required=(
  "detection.candidate_memory_edit=allowed"
  "detection.promoted_memory_silent_edit=unaudited"
  "detection.operational_due_status=allowed"
  "detection.supersession=preserves_original"
  "detection.candidate_wiki_edit=allowed"
  "detection.promoted_wiki_silent_edit=mismatch"
  "detection.unblessed_wiki=no-blessing"
  "detection.hash_is_not_a_signature=true"
  "detection.wiki_supersession=preserves_original"
  "detection.provenance_guard=intact"
)
for token in "${required[@]}"; do
  if ! grep -F -q "$token" "$log"; then
    cat "$log" >&2
    rm -f "$log"
    refuse "missing detection ${token}"
  fi
done
rm -f "$log"

echo "promoted-record silent-edit check: local throwaway database passed"
