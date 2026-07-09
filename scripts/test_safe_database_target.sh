#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/safe_database_target.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_allowed() {
  local name=$1
  local url=$2
  if ! (unset PGHOST PGHOSTADDR PGSERVICE PGSERVICEFILE SMC_ALLOW_NONLOCAL_DATABASE; require_safe_database_url "$url") >/dev/null 2>&1; then
    fail "${name} should be allowed"
  fi
  echo "PASS: ${name} allowed"
}

assert_refused() {
  local name=$1
  shift
  if (unset PGHOST PGHOSTADDR PGSERVICE PGSERVICEFILE SMC_ALLOW_NONLOCAL_DATABASE; "$@") >/dev/null 2>&1; then
    fail "${name} should be refused"
  fi
  echo "PASS: ${name} refused"
}

assert_allowed "localhost" "postgresql://user:pass@localhost:5432/db"
assert_allowed "loopback" "postgresql://user:pass@127.0.0.1:5432/db"
assert_allowed "docker postgres" "postgresql://user:pass@postgres:5432/db"
assert_allowed "local socket" "postgresql:///db"

assert_refused "Supabase-style host" bash -c '
  source "$1"
  require_safe_database_url "postgresql://user:pass@something.supabase.co:5432/db"
' bash "${ROOT_DIR}/scripts/lib/safe_database_target.sh"
assert_refused "public IP host" bash -c '
  source "$1"
  require_safe_database_url "postgresql://user:pass@1.2.3.4:5432/db"
' bash "${ROOT_DIR}/scripts/lib/safe_database_target.sh"
assert_refused "remote PGHOST" bash -c '
  source "$1"
  PGHOST=something.supabase.co require_safe_database_url "postgresql:///db"
' bash "${ROOT_DIR}/scripts/lib/safe_database_target.sh"
assert_refused "public PGHOSTADDR" bash -c '
  source "$1"
  PGHOSTADDR=1.2.3.4 require_safe_database_url "postgresql:///db"
' bash "${ROOT_DIR}/scripts/lib/safe_database_target.sh"
assert_refused "PGSERVICE" bash -c '
  source "$1"
  PGSERVICE=prod require_safe_database_url "postgresql:///db"
' bash "${ROOT_DIR}/scripts/lib/safe_database_target.sh"
assert_refused "PGSERVICEFILE" bash -c '
  source "$1"
  PGSERVICEFILE=/tmp/pg_service.conf require_safe_database_url "postgresql:///db"
' bash "${ROOT_DIR}/scripts/lib/safe_database_target.sh"

override_output=$(mktemp)
trap 'rm -f "${override_output}"' EXIT
if ! (PGHOST=something.supabase.co SMC_ALLOW_NONLOCAL_DATABASE=1 require_safe_database_url "postgresql:///db") >"${override_output}" 2>&1; then
  fail "explicit override should be allowed"
fi
grep -q 'WARNING: SMC_ALLOW_NONLOCAL_DATABASE=1' "${override_output}" || fail "override warning missing"
echo "PASS: explicit override allowed with warning"
