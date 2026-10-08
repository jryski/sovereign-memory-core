#!/usr/bin/env bash
set -euo pipefail

# Validate the human approval contract on a disposable local database.
#
# Usage:
#   DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/postgres" \
#     bash scripts/validate_human_approval.sh
#
# The script creates and drops database human_approval_validation on the same
# server. It does not connect to a hosted project.

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is required" >&2
  echo "Example: DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/postgres bash scripts/validate_human_approval.sh" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PGOPTIONS="${PGOPTIONS:--c client_min_messages=warning}"
ADMIN_URL="${DATABASE_URL%/*}/postgres"
TARGET_DB="human_approval_validation"
TARGET_URL="${DATABASE_URL%/*}/${TARGET_DB}"
PSQL=(psql "${TARGET_URL}" -v ON_ERROR_STOP=1)

cleanup() {
  psql "${ADMIN_URL}" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${TARGET_DB} WITH (FORCE);" >/dev/null
}
trap cleanup EXIT

echo "==> Creating disposable database ${TARGET_DB}"
psql "${ADMIN_URL}" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${TARGET_DB} WITH (FORCE);" >/dev/null
psql "${ADMIN_URL}" -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${TARGET_DB};" >/dev/null

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
"${PSQL[@]}" -f "${ROOT_DIR}/sql/01_core.sql" >/dev/null

echo "==> Applying human approval requests"
"${PSQL[@]}" -f "${ROOT_DIR}/sql/13_human_approval_requests.sql" >/dev/null

echo "==> Reapplying human approval requests"
"${PSQL[@]}" -f "${ROOT_DIR}/sql/13_human_approval_requests.sql" >/dev/null

echo "==> Running human approval validation"
"${PSQL[@]}" -f "${ROOT_DIR}/sql/validation/human_approval_requests.sql"

echo "==> Proving concurrent double approval fails closed"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -c "insert into public.memories(content, workstream, owner, visibility, source_agent, source_kind, status) values ('human-approval-concurrency', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed');" >/dev/null
memory_id="$("${PSQL[@]}" -v ON_ERROR_STOP=1 -At -c "select id::text from public.memories where content = 'human-approval-concurrency';")"

"${PSQL[@]}" -v ON_ERROR_STOP=1 >/dev/null <<SQL
set session authorization human_approval_agent;
select human_approval.request_memory_promotion(
  '${memory_id}'::uuid,
  'concurrent proposal',
  '[{"ref":"fixture:concurrency"}]'::jsonb,
  clock_timestamp() + interval '1 hour',
  'forged-human'
);
SQL
request_id="$("${PSQL[@]}" -v ON_ERROR_STOP=1 -At -c "select id::text from human_approval.requests where target_id = '${memory_id}'::uuid;")"

review_row="$("${PSQL[@]}" -v ON_ERROR_STOP=1 -At -F '|' -c "select expected_version || '|' || decision_nonce from human_approval.requests where id = '${request_id}'::uuid;")"
expected_version="${review_row%%|*}"
decision_nonce="${review_row#*|}"

tmp_a="$(mktemp)"
tmp_b="$(mktemp)"

set +e
"${PSQL[@]}" >"${tmp_a}" 2>&1 <<SQL &
set statement_timeout = '15s';
set session authorization human_approval_reviewer;
select human_approval.open_human_approval_session();
select human_approval.approve_human_approval_request(
  '${request_id}'::uuid,
  '${expected_version}',
  '${decision_nonce}',
  'concurrent decision'
);
SQL
pid_a=$!
"${PSQL[@]}" >"${tmp_b}" 2>&1 <<SQL &
set statement_timeout = '15s';
set session authorization human_approval_reviewer;
select human_approval.open_human_approval_session();
select human_approval.approve_human_approval_request(
  '${request_id}'::uuid,
  '${expected_version}',
  '${decision_nonce}',
  'concurrent decision'
);
SQL
pid_b=$!
wait "${pid_a}"
code_a=$?
wait "${pid_b}"
code_b=$?
set -e

success=0
if [[ "${code_a}" -eq 0 ]]; then success=$((success + 1)); fi
if [[ "${code_b}" -eq 0 ]]; then success=$((success + 1)); fi
if [[ "${success}" -ne 1 ]] || ! grep -q 'human_approval: already resolved' "${tmp_a}" "${tmp_b}"; then
  echo "concurrent double approval did not fail closed" >&2
  echo "exit codes ${code_a} ${code_b}" >&2
  cat "${tmp_a}" "${tmp_b}" >&2
  rm -f "${tmp_a}" "${tmp_b}"
  exit 1
fi
rm -f "${tmp_a}" "${tmp_b}"

"${PSQL[@]}" -v ON_ERROR_STOP=1 <<SQL
do \$\$
declare
  v_receipts integer;
  v_status text;
  v_promoted_by text;
begin
  select count(*) into v_receipts
  from human_approval.receipts
  where request_id = '${request_id}'::uuid;
  select status::text, metadata->>'promoted_by'
    into v_status, v_promoted_by
  from public.memories
  where id = '${memory_id}'::uuid;
  if v_receipts <> 1 or v_status <> 'active' or v_promoted_by <> 'example-user' then
    raise exception 'concurrent approval residue: receipts % status % promoted_by %',
      v_receipts, v_status, v_promoted_by;
  end if;
  if (select count(*) from human_approval.requests where id = '${request_id}'::uuid and status = 'approved') <> 1 then
    raise exception 'concurrent approval did not resolve the request once';
  end if;
end \$\$;
SQL

echo "==> Done"
