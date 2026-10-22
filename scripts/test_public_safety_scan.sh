#!/usr/bin/env bash
# Positive and negative controls for scripts/public_safety_scan.sh.
# Synthetic fixtures only. No network and no database.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCAN="${ROOT_DIR}/scripts/public_safety_scan.sh"
FAIL_DIR="${ROOT_DIR}/tests/public_safety/fixtures/fail"
PASS_DIR="${ROOT_DIR}/tests/public_safety/fixtures/pass"
failures=0
checks=0

cleanup() {
  local dir
  for dir in "${tmpdirs[@]+"${tmpdirs[@]}"}"; do
    rm -rf "$dir"
  done
}
tmpdirs=()
trap cleanup EXIT

pass() {
  checks=$((checks + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

run_scan() {
  set +e
  SCAN_OUT=$(bash "$SCAN" "$@" 2>&1)
  SCAN_STATUS=$?
  set -e
}

assert_lines_are_scanner_output() {
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      public-safety:*) ;;
      *)
        fail "unexpected scanner output: ${line}"
        return 1
        ;;
    esac
  done <<PUBLIC_SAFETY_END
$SCAN_OUT
PUBLIC_SAFETY_END
}

assert_output_hides_fixture_body() {
  local file="$1" body
  body=$(mktemp)
  grep -v '^#' "$file" | grep -v '^$' >"$body" || true
  if [[ -s "$body" ]] && printf '%s\n' "$SCAN_OUT" | grep -F -q -f "$body"; then
    rm -f "$body"
    fail "$(basename "$file") repeated a fixture line in scanner output"
    return 1
  fi
  rm -f "$body"
}

bash -n "$SCAN"
bash -n "${ROOT_DIR}/scripts/test_public_safety_scan.sh"
pass "shell syntax"

run_scan --help
if [[ "$SCAN_STATUS" -eq 0 ]] && printf '%s\n' "$SCAN_OUT" | grep -q -- '--changed'; then
  pass "--help"
else
  fail "--help status=${SCAN_STATUS}"
fi

run_scan --not-a-mode
if [[ "$SCAN_STATUS" -eq 2 ]]; then
  pass "unknown argument exits 2"
else
  fail "unknown argument status=${SCAN_STATUS}"
fi

rules=$(grep '^# rule: ' "$SCAN" | awk '{print $3}')
if [[ -z "$rules" ]]; then
  fail "scanner declares no rules"
fi

for rule in $rules; do
  if ! grep -R -l --include='*.txt' -e "# expected-rule: ${rule}" "$FAIL_DIR" >/dev/null; then
    fail "no positive control for ${rule}"
  fi
  if ! grep -R -l --include='*.txt' -e "# covers-rule: ${rule}" "$PASS_DIR" >/dev/null; then
    fail "no negative control for ${rule}"
  fi
  if ! grep -q -F -e "$rule" "${ROOT_DIR}/docs/public-safety.md"; then
    fail "docs/public-safety.md does not mention ${rule}"
  fi
done
if [[ "$failures" -eq 0 ]]; then
  pass "every declared rule has a fail fixture, a pass fixture, and a doc row"
fi

shopt -s nullglob
fail_files=("$FAIL_DIR"/*.txt)
pass_files=("$PASS_DIR"/*.txt)
shopt -u nullglob

if [[ "${#fail_files[@]}" -eq 0 || "${#pass_files[@]}" -eq 0 ]]; then
  fail "fixture directories are empty"
fi

for file in "${fail_files[@]}"; do
  rel=${file#"$ROOT_DIR"/}
  expected=$(grep '^# expected-rule: ' "$file" | awk '{print $3}')
  min=$(sed -n 's/^# min-findings: //p' "$file" | head -n 1)
  [[ -n "$min" ]] || min=1
  if [[ -z "$expected" ]]; then
    fail "${rel} has no expected-rule"
    continue
  fi
  run_scan --paths "$rel"
  count=$(printf '%s\n' "$SCAN_OUT" | grep -c "rule=${expected} class=" || true)
  if [[ "$SCAN_STATUS" -ne 1 ]]; then
    fail "${rel} expected exit 1 for ${expected}, got ${SCAN_STATUS}"
    printf '%s\n' "$SCAN_OUT" >&2
    continue
  fi
  if [[ "$count" -lt "$min" ]]; then
    fail "${rel} expected at least ${min} ${expected} finding(s), got ${count}"
    printf '%s\n' "$SCAN_OUT" >&2
    continue
  fi
  assert_lines_are_scanner_output || true
  assert_output_hides_fixture_body "$file" || true
  pass "${rel} fails for ${expected} (${count})"
done

for file in "${pass_files[@]}"; do
  rel=${file#"$ROOT_DIR"/}
  run_scan --paths "$rel"
  if [[ "$SCAN_STATUS" -ne 0 ]] || ! printf '%s\n' "$SCAN_OUT" | grep -q 'no pattern findings'; then
    fail "${rel} was expected to pass"
    printf '%s\n' "$SCAN_OUT" >&2
    continue
  fi
  if printf '%s\n' "$SCAN_OUT" | grep -q 'FINDING'; then
    fail "${rel} passed with a finding line"
    continue
  fi
  pass "${rel} does not fire"
done

existing=(
  fixtures/chat_mine/sample_chat_export.json
  fixtures/chat_mine/expected_source_import_package.json
  tests/fixtures/v2_upgrade_seed.sql
  tests/fixtures/v2_upgrade_verify.sql
)
run_scan --paths "${existing[@]}"
if [[ "$SCAN_STATUS" -eq 0 ]] && printf '%s\n' "$SCAN_OUT" | grep -q 'no pattern findings'; then
  pass "existing public fixtures have no findings"
else
  fail "existing public fixtures produced findings"
  printf '%s\n' "$SCAN_OUT" >&2
fi

sentinel='No exact private counts, manifests, watermarks, stable digests, custody receipts, or routing records'
for template in \
  .github/pull_request_template.md \
  .github/ISSUE_TEMPLATE/bug_report.md \
  .github/ISSUE_TEMPLATE/feature_request.md \
  .github/ISSUE_TEMPLATE/docs_task.md \
  .github/ISSUE_TEMPLATE/conformance_gap.md \
  .github/ISSUE_TEMPLATE/research_task.md \
  docs/public-safety.md
do
  if grep -F -q "$sentinel" "$template"; then
    pass "checklist present in ${template}"
  else
    fail "checklist missing from ${template}"
  fi
done

for phrase in "release notes" "workflow logs" "uploaded artifacts"; do
  if grep -F -q "$phrase" CONTRIBUTING.md && grep -F -q "$phrase" docs/public-safety.md; then
    pass "publication surface '${phrase}' is documented"
  else
    fail "publication surface '${phrase}' is missing from contribution guidance"
  fi
done

new_repo() {
  local dir
  dir=$(mktemp -d)
  tmpdirs+=("$dir")
  mkdir -p "$dir/scripts"
  cp "$SCAN" "$dir/scripts/public_safety_scan.sh"
  git -C "$dir" init -q
  git -C "$dir" config user.email "public-safety-test@example.invalid"
  git -C "$dir" config user.name "Public Safety Test"
  git -C "$dir" config commit.gpgsign false
  printf '%s\n' 'synthetic placeholder example.local' >"$dir/README.md"
  git -C "$dir" add README.md scripts/public_safety_scan.sh
  git -C "$dir" commit -q -m 'init'
  printf '%s\n' "$dir"
}

scan_repo() {
  local repo_dir="$1"
  shift
  set +e
  SCAN_OUT=$(
    unset GITHUB_ACTIONS GITHUB_EVENT_NAME GITHUB_BASE_REF GITHUB_EVENT_BEFORE PUBLIC_SAFETY_BASE
    bash "$repo_dir/scripts/public_safety_scan.sh" "$@" 2>&1
  )
  SCAN_STATUS=$?
  set -e
}

scan_repo_ci() {
  local repo_dir="$1"
  shift
  set +e
  SCAN_OUT=$(
    unset PUBLIC_SAFETY_BASE
    export GITHUB_ACTIONS=true
    export GITHUB_EVENT_NAME=push
    bash "$repo_dir/scripts/public_safety_scan.sh" "$@" 2>&1
  )
  SCAN_STATUS=$?
  set -e
}

repo=$(new_repo)
scan_repo "$repo" --changed --base HEAD
if [[ "$SCAN_STATUS" -eq 0 ]] \
  && printf '%s\n' "$SCAN_OUT" | grep -q '0 files scanned' \
  && printf '%s\n' "$SCAN_OUT" | grep -q 'not a clean verdict' \
  && ! printf '%s\n' "$SCAN_OUT" | grep -q 'no pattern findings'; then
  pass "zero-file changed scan is not a clean verdict"
else
  fail "zero-file changed scan"
  printf '%s\n' "$SCAN_OUT" >&2
fi

cp "${FAIL_DIR}/secret-github-token.txt" "$repo/leak.txt"
scan_repo "$repo" --changed --base HEAD
if [[ "$SCAN_STATUS" -eq 1 ]] && printf '%s\n' "$SCAN_OUT" | grep -q 'rule=secret-github-token class='; then
  pass "local changed mode sees an unstaged synthetic token"
else
  fail "local changed mode missed an unstaged synthetic token"
  printf '%s\n' "$SCAN_OUT" >&2
fi

scan_repo_ci "$repo" --changed --base HEAD
if [[ "$SCAN_STATUS" -eq 0 ]] \
  && printf '%s\n' "$SCAN_OUT" | grep -q '0 files scanned' \
  && ! printf '%s\n' "$SCAN_OUT" | grep -q 'FINDING'; then
  pass "GitHub Actions changed mode ignores unstaged files"
else
  fail "GitHub Actions changed mode scanned unstaged files"
  printf '%s\n' "$SCAN_OUT" >&2
fi

git -C "$repo" add leak.txt
git -C "$repo" commit -q -m 'add synthetic leak'
scan_repo_ci "$repo" --changed --base HEAD~1
if [[ "$SCAN_STATUS" -eq 1 ]] && printf '%s\n' "$SCAN_OUT" | grep -q 'leak.txt:'; then
  pass "committed synthetic token fails the changed-file scan"
else
  fail "committed synthetic token did not fail the changed-file scan"
  printf '%s\n' "$SCAN_OUT" >&2
fi

bare=$(new_repo)
scan_repo "$bare" --changed --base does-not-exist
if [[ "$SCAN_STATUS" -eq 2 ]]; then
  pass "missing base exits 2"
else
  fail "missing base status=${SCAN_STATUS}"
fi

git -C "$bare" branch -M main
scan_repo "$bare" --changed
if [[ "$SCAN_STATUS" -eq 0 ]] && printf '%s\n' "$SCAN_OUT" | grep -q 'not a clean verdict'; then
  pass "local default resolves main and does not call an empty diff clean"
else
  fail "local default base resolution"
  printf '%s\n' "$SCAN_OUT" >&2
fi

isolated=$(mktemp -d)
tmpdirs+=("$isolated")
mkdir -p "$isolated/scripts"
cp "$SCAN" "$isolated/scripts/public_safety_scan.sh"
git -C "$isolated" init -q
git -C "$isolated" config user.email "public-safety-test@example.invalid"
git -C "$isolated" config user.name "Public Safety Test"
git -C "$isolated" config commit.gpgsign false
scan_repo "$isolated" --changed
if [[ "$SCAN_STATUS" -eq 2 ]]; then
  pass "changed mode without a base exits 2"
else
  fail "changed mode without a base status=${SCAN_STATUS}"
  printf '%s\n' "$SCAN_OUT" >&2
fi

run_scan --all
if [[ "$SCAN_STATUS" -eq 0 ]] && printf '%s\n' "$SCAN_OUT" | grep -q 'no pattern findings'; then
  pass "tracked tree has no findings outside synthetic positive controls"
else
  fail "tracked tree scan"
  printf '%s\n' "$SCAN_OUT" >&2
fi

if printf '%s\n' "$SCAN_OUT" | grep -q 'fixtures/fail/'; then
  fail "full-tree scan reported a positive-control path"
else
  pass "full-tree scan skips synthetic positive controls"
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'public-safety tests: %s check(s) passed, %s failed\n' "$checks" "$failures" >&2
  exit 1
fi

printf 'public-safety tests: %s check(s) passed\n' "$checks"
exit 0
