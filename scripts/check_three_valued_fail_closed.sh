#!/usr/bin/env bash
# Local NULL fail-closed checker for issue #74.
#
# Proves three consumers on a disposable database:
#   1. corrected SQL aggregates, predicates, and CHECK pairing reject NULL
#   2. a blank result is a failure
#   3. a known-broken suite that exits 0 is not accepted as evidence
#
# The discrimination count is stated here, before psql runs. The SQL file
# has the same census and raises if it drifts.
#
# Usage:
#   DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/postgres" \
#     bash scripts/check_three_valued_fail_closed.sh
#
# Refuses any host other than localhost, 127.0.0.1, or ::1.
# Does not print DATABASE_URL. Does not pipe psql into grep or another filter.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_SQL="${ROOT_DIR}/tests/12_three_valued_fail_closed.sql"
KNOWN_BROKEN_SQL="${ROOT_DIR}/tests/fixtures/three_valued_known_broken.sql"

# Precommitted before the database runs. Update the SQL census in the same change.
EXPECTED_VERDICT="three_valued_fail_closed: pass discriminated=8 cases=l1_bool_and_ignores_null,l1_empty_aggregate_is_not_false,l1_filter_not_ignores_null,l1_not_null_skips_guard,l2_not_predicate_skips_guard,l2_strict_reintroduces_null,l3_check_accepts_null,l3_presence_is_not_pairing"
INERT_MARKER="true|0"

PSQL_OUTPUT=""

database_url_host() {
  local url="$1"
  local rest host
  if [[ "$url" != *"://"* ]]; then
    printf '%s\n' ""
    return 0
  fi
  rest="${url#*://}"
  if [[ "$rest" == *"@"* ]]; then
    rest="${rest#*@}"
  fi
  if [[ "$rest" == \[* ]]; then
    host="${rest#[}"
    host="${host%%]*}"
  else
    host="${rest%%[:/]*}"
  fi
  printf '%s\n' "$host"
}

database_url_is_local() {
  local host
  host="$(database_url_host "$1")"
  case "$host" in
    localhost | 127.0.0.1 | ::1) return 0 ;;
    *) return 1 ;;
  esac
}

expect_local() {
  if ! database_url_is_local "$1"; then
    echo "local database URL was refused" >&2
    exit 1
  fi
}

expect_remote() {
  if database_url_is_local "$1"; then
    echo "non-local database URL was accepted" >&2
    exit 1
  fi
}

prove_host_parser() {
  expect_local "postgres://postgres:postgres@localhost:5432/sovereign_tvl"
  expect_local "postgresql://postgres@127.0.0.1/sovereign_tvl"
  expect_local "postgresql://postgres@[::1]:5432/sovereign_tvl"
  expect_remote "postgresql://postgres:redacted@db.example.com:5432/postgres"
  expect_remote "postgresql://db.example.com/postgres"
  expect_remote ""
  expect_remote "not-a-url"
}

# A pipeline whose last command succeeds hides the producer's failure unless
# pipefail is on. This checker turns pipefail on and does not consult a
# downstream filter for the psql result.
prove_pipefail_surfaces_producer() {
  local masked=0
  set +o pipefail
  if false | true; then
    masked=1
  fi
  set -o pipefail
  if [[ "$masked" -ne 1 ]]; then
    echo "expected a pipeline without pipefail to mask the producer" >&2
    exit 1
  fi
  if false | true; then
    echo "pipefail did not surface the producer failure" >&2
    exit 1
  fi
}

require_local_database_url() {
  if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "DATABASE_URL is required" >&2
    exit 2
  fi
  if ! database_url_is_local "$DATABASE_URL"; then
    echo "refusing non-local DATABASE_URL host" >&2
    exit 2
  fi
}

run_psql() {
  local status
  set +e
  PSQL_OUTPUT="$(psql "$DATABASE_URL" -X -q -t -A -v ON_ERROR_STOP=1 "$@" 2>&1)"
  status=$?
  set -e
  return "$status"
}

# Print the only non-blank line. Return 1 when every line is blank.
# Return 2 when more than one non-blank line is present.
single_result_line() {
  local output="$1"
  local line=""
  local found=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "${line//[[:space:]]/}" ]]; then
      continue
    fi
    if [[ -n "$found" ]]; then
      return 2
    fi
    found="$line"
  done <<<"$output"
  if [[ -z "$found" ]]; then
    return 1
  fi
  printf '%s\n' "$found"
}

main() {
  local matrix_line broken_line blank_status

  prove_host_parser
  prove_pipefail_surfaces_producer
  require_local_database_url

  if ! run_psql -f "$MATRIX_SQL"; then
    echo "fail-closed matrix failed" >&2
    printf '%s\n' "$PSQL_OUTPUT" >&2
    exit 1
  fi
  if ! matrix_line="$(single_result_line "$PSQL_OUTPUT")"; then
    echo "matrix result was blank or had more than one line" >&2
    printf '%s\n' "$PSQL_OUTPUT" >&2
    exit 1
  fi
  if [[ "$matrix_line" != "$EXPECTED_VERDICT" ]]; then
    echo "matrix verdict did not match the precommitted census" >&2
    printf '%s\n' "$matrix_line" >&2
    exit 1
  fi

  if ! run_psql -f "$KNOWN_BROKEN_SQL"; then
    echo "known-broken fixture raised; it must stay inert and exit 0" >&2
    printf '%s\n' "$PSQL_OUTPUT" >&2
    exit 1
  fi
  if ! broken_line="$(single_result_line "$PSQL_OUTPUT")"; then
    echo "known-broken fixture did not return a single inert marker" >&2
    printf '%s\n' "$PSQL_OUTPUT" >&2
    exit 1
  fi
  if [[ "$broken_line" != "$INERT_MARKER" ]]; then
    echo "known-broken fixture no longer reports the inert success marker" >&2
    printf '%s\n' "$broken_line" >&2
    exit 1
  fi
  if [[ "$broken_line" == "$EXPECTED_VERDICT" ]]; then
    echo "known-broken fixture minted the matrix verdict" >&2
    exit 1
  fi

  if ! run_psql -c "select null::boolean;"; then
    echo "blank-boolean probe failed to execute" >&2
    printf '%s\n' "$PSQL_OUTPUT" >&2
    exit 1
  fi
  blank_status=0
  single_result_line "$PSQL_OUTPUT" >/dev/null || blank_status=$?
  if [[ "$blank_status" -ne 1 ]]; then
    echo "blank boolean probe was not a blank result" >&2
    printf '%s\n' "$PSQL_OUTPUT" >&2
    exit 1
  fi

  printf '%s\n' "three_valued_fail_closed: checker pass"
}

main "$@"
