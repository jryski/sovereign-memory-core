#!/usr/bin/env bash
# Scan files for likely public-readiness risks.
#
# Dependency-light: bash, grep, and git. Read-only. No network and no database.
# Pattern matches are triage signals. They do not establish context or attack
# value. Human review is still required. See docs/public-safety.md.
#
# Exit 0: no findings, or zero files scanned (that is not a clean verdict).
# Exit 1: one or more findings.
# Exit 2: usage or git error.
set -euo pipefail

LC_ALL=C
export LC_ALL

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WORK=""
findings=0
mode=""
base=""
paths=()

cleanup() {
  if [[ -n "${WORK:-}" && -d "$WORK" ]]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

die() {
  echo "public-safety: $*" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage: scripts/public_safety_scan.sh [--changed] [--base REF] [--all] [--paths FILE...]

Scan text for likely public-readiness risks. Default mode is --changed.

Local default (GitHub Actions is not set):
  Diff HEAD against the merge-base with origin/main, or with main when
  origin/main is absent. Also scan staged, unstaged, and untracked files.
  If no base can be resolved, exit 2. Pass --base REF to choose one.

GitHub Actions:
  Pass --base. A pull request should use the base SHA. A push should use the
  previous SHA. Forty zero digits means there is no previous commit; the scan
  then reads all tracked files. Untracked files are not added in GitHub Actions.

--all
  Scan tracked files except tests/public_safety/fixtures/fail/. That directory
  holds synthetic positive controls. The exclusion is not clearance.
  scripts/test_public_safety_scan.sh scans those paths with --paths and expects
  findings.

--paths FILE...
  Scan exactly those files. The positive-control exclusion is not applied.

Findings name the rule, class, and location. Matched text is not printed.

Exit 0  no findings, or zero files. Zero files is not a clean verdict.
Exit 1  one or more findings.
Exit 2  usage or git error.
EOF
}

# rule: secret-private-key class=secret
# rule: secret-aws-access-key class=secret
# rule: secret-github-token class=secret
# rule: secret-slack-token class=secret
# rule: secret-vendor-token class=secret
# rule: secret-jwt class=secret
# rule: secret-assignment class=secret
# rule: contact-email class=contact
# rule: contact-phone class=contact
# rule: local-home-path class=deployment
# rule: deployment-ip class=deployment
# rule: deployment-hostname class=deployment
# rule: deployment-supabase-host class=deployment
# rule: deployment-connection-string class=deployment
# rule: operational-receipt class=operational
# rule: live-schema-inventory class=inventory
# rule: coordination-transcript class=transcript

report() {
  local rule="$1" class="$2" file="$3" line_no="$4" key
  key="${rule}|${file}|${line_no}"
  if [[ -f "$WORK/seen" ]] && grep -F -x -q -e "$key" "$WORK/seen"; then
    return 0
  fi
  printf '%s\n' "$key" >>"$WORK/seen"
  printf 'public-safety: FINDING rule=%s class=%s %s:%s\n' "$rule" "$class" "$file" "$line_no"
  findings=$((findings + 1))
}

collect_grep() {
  local file="$1" re="$2" ignore_case="${3:-}"
  if [[ "$ignore_case" == "i" ]]; then
    GREP_HITS=$(grep -n -E -i -I -e "$re" -- "$file" || true)
  else
    GREP_HITS=$(grep -n -E -I -e "$re" -- "$file" || true)
  fi
}

each_hit() {
  local line_no content
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    line_no=${line%%:*}
    content=${line#*:}
    HIT_LINE=$line_no
    HIT_CONTENT=$content
    hit_callback
  done <<PUBLIC_SAFETY_END
$GREP_HITS
PUBLIC_SAFETY_END
}

is_placeholder_value() {
  local value="$1"
  value=${value%\"}
  value=${value%\'}
  case "$value" in
    REDACTED | redacted | *REDACTED* | *placeholder* | *example* | *changeme* | your-* | '<'* | postgres | password | x | none | n/a | NA)
      return 0
      ;;
  esac
  return 1
}

allowed_email_domain() {
  local domain="$1"
  domain=$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')
  domain=${domain%.}
  case "$domain" in
    example.com | example.org | example.net | example.invalid | example.local | localhost) return 0 ;;
    *.example.com | *.example.org | *.example.net | *.example.invalid) return 0 ;;
  esac
  return 1
}

allowed_phone_match() {
  local match="$1" exchange subscriber
  if [[ "$match" =~ ([2-9][0-9]{2})[^0-9]+([2-9][0-9]{2})[^0-9]+([0-9]{4}) ]]; then
    exchange=${BASH_REMATCH[2]}
    subscriber=${BASH_REMATCH[3]}
    if [[ "$exchange" == "555" && "$subscriber" =~ ^01[0-9][0-9]$ ]]; then
      return 0
    fi
  fi
  return 1
}

valid_ipv4() {
  local ip="$1" octet
  [[ "$ip" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  for octet in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
    if ((10#$octet > 255)); then
      return 1
    fi
  done
  return 0
}

allowed_ipv4() {
  local ip="$1"
  case "$ip" in
    127.0.0.1 | 0.0.0.0 | 255.255.255.255) return 0 ;;
  esac
  [[ "$ip" =~ ^192\.0\.2\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]] && return 0
  [[ "$ip" =~ ^198\.51\.100\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]] && return 0
  [[ "$ip" =~ ^203\.0\.113\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]] && return 0
  return 1
}

allowed_db_host() {
  case "$1" in
    localhost | 127.0.0.1 | 0.0.0.0 | ::1) return 0 ;;
  esac
  return 1
}

publication_excluded() {
  case "$1" in
    tests/public_safety/fixtures/fail/*) return 0 ;;
  esac
  return 1
}

scan_private_key() {
  local file="$1" pem_re
  pem_re=$(printf '%s%s' '-----BEGIN (RSA |OPENSSH |EC |DSA |PGP |ENCRYPTED )?' 'PRIVATE KEY-----')
  collect_grep "$file" "$pem_re"
  hit_callback() { report secret-private-key secret "$file" "$HIT_LINE"; }
  each_hit
}

scan_aws() {
  local file="$1"
  collect_grep "$file" '(AKIA|ASIA)[0-9A-Z]{16}'
  hit_callback() { report secret-aws-access-key secret "$file" "$HIT_LINE"; }
  each_hit
}

scan_github_token() {
  local file="$1"
  collect_grep "$file" 'gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}'
  hit_callback() { report secret-github-token secret "$file" "$HIT_LINE"; }
  each_hit
}

scan_slack() {
  local file="$1"
  collect_grep "$file" 'xox[baprs]-[A-Za-z0-9-]{10,}'
  hit_callback() { report secret-slack-token secret "$file" "$HIT_LINE"; }
  each_hit
}

scan_vendor_token() {
  local file="$1"
  collect_grep "$file" 'sk-[A-Za-z0-9]{20,}|sbp_[A-Za-z0-9]{20,}'
  hit_callback() { report secret-vendor-token secret "$file" "$HIT_LINE"; }
  each_hit
}

scan_jwt() {
  local file="$1"
  collect_grep "$file" 'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'
  hit_callback() { report secret-jwt secret "$file" "$HIT_LINE"; }
  each_hit
}

scan_assignment() {
  local file="$1" assign_re
  assign_re='(^|[^A-Za-z0-9])(api[_-]?key|api[_-]?secret|secret[_-]?access[_-]?key|secret[_-]?key|access[_-]?token|refresh[_-]?token|private[_-]?key|service[_-]?role[_-]?key|rotated[_-]?key|old[_-]?password|new[_-]?password|password|passwd|secret)[[:space:]]*[:=][[:space:]]*["'\'']?([A-Za-z0-9+/_.=-]{16,})'
  collect_grep "$file" "$assign_re" i
  hit_callback() {
    local value prev=0
    shopt -q nocasematch && prev=1
    shopt -s nocasematch
    if [[ "$HIT_CONTENT" =~ $assign_re ]]; then
      value=${BASH_REMATCH[3]}
      if ! is_placeholder_value "$value"; then
        report secret-assignment secret "$file" "$HIT_LINE"
      fi
    fi
    if [[ "$prev" -eq 0 ]]; then
      shopt -u nocasematch
    fi
  }
  each_hit
}

scan_email() {
  local file="$1" email_re
  email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
  collect_grep "$file" "$email_re"
  hit_callback() {
    local match domain flagged=0
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      domain=${match##*@}
      domain=${domain%%[!A-Za-z0-9.-]*}
      if ! allowed_email_domain "$domain"; then
        flagged=1
      fi
    done <<PUBLIC_SAFETY_END
$(printf '%s\n' "$HIT_CONTENT" | grep -o -E -e "$email_re" || true)
PUBLIC_SAFETY_END
    if [[ "$flagged" -eq 1 ]]; then
      report contact-email contact "$file" "$HIT_LINE"
    fi
  }
  each_hit
}

scan_phone() {
  local file="$1" phone_re
  phone_re='(\+1[-. ]?)?\(?[2-9][0-9]{2}\)?[-. ][2-9][0-9]{2}[-. ][0-9]{4}'
  collect_grep "$file" "$phone_re"
  hit_callback() {
    local match flagged=0
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      if ! allowed_phone_match "$match"; then
        flagged=1
      fi
    done <<PUBLIC_SAFETY_END
$(printf '%s\n' "$HIT_CONTENT" | grep -o -E -e "$phone_re" || true)
PUBLIC_SAFETY_END
    if [[ "$flagged" -eq 1 ]]; then
      report contact-phone contact "$file" "$HIT_LINE"
    fi
  }
  each_hit
}

scan_home_path() {
  local file="$1" path_re
  path_re='(^|[^A-Za-z0-9])/(Users|home)/[A-Za-z0-9._-]+|[A-Za-z]:\\Users\\[A-Za-z0-9._-]+'
  collect_grep "$file" "$path_re"
  hit_callback() { report local-home-path deployment "$file" "$HIT_LINE"; }
  each_hit
}

scan_ip() {
  local file="$1" ip_re
  ip_re='(^|[^0-9])[0-9]{1,3}(\.[0-9]{1,3}){3}([^0-9]|$)'
  collect_grep "$file" "$ip_re"
  hit_callback() {
    local match ip flagged=0
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      ip=$(printf '%s' "$match" | grep -o -E -e '[0-9]{1,3}(\.[0-9]{1,3}){3}' || true)
      [[ -n "$ip" ]] || continue
      valid_ipv4 "$ip" || continue
      if ! allowed_ipv4 "$ip"; then
        flagged=1
      fi
    done <<PUBLIC_SAFETY_END
$(printf '%s\n' "$HIT_CONTENT" | grep -o -E -e '[0-9]{1,3}(\.[0-9]{1,3}){3}' || true)
PUBLIC_SAFETY_END
    if [[ "$flagged" -eq 1 ]]; then
      report deployment-ip deployment "$file" "$HIT_LINE"
    fi
  }
  each_hit
}

scan_hostname() {
  local file="$1" host_re
  # The character after the suffix must end the name. Underscore continues an
  # identifier, so excluded.internal_execute_roles is not a hostname.
  host_re='(^|[^A-Za-z0-9-])[A-Za-z0-9][A-Za-z0-9-]{0,62}\.(internal|local)([^A-Za-z0-9_-]|$)'
  collect_grep "$file" "$host_re"
  hit_callback() {
    local match host flagged=0
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      host=$match
      case "$host" in
        *.internal | *.local) ;;
        *.internal? | *.local?) host=${host%?} ;;
      esac
      if [[ "$host" != "example.local" ]]; then
        flagged=1
      fi
    done <<PUBLIC_SAFETY_END
$(printf '%s\n' "$HIT_CONTENT" | grep -o -E -e '[A-Za-z0-9][A-Za-z0-9-]{0,62}\.(internal|local)([^A-Za-z0-9_-]|$)' || true)
PUBLIC_SAFETY_END
    if [[ "$flagged" -eq 1 ]]; then
      report deployment-hostname deployment "$file" "$HIT_LINE"
    fi
  }
  each_hit
}

scan_supabase() {
  local file="$1" host_re ref_re
  host_re='https://[a-z]{20}\.supabase\.co|db\.[a-z]{20}\.supabase\.co|(^|[^A-Za-z0-9-])[a-z0-9][a-z0-9-]*\.pooler\.supabase\.com'
  ref_re='project_ref[[:space:]]*[:=][[:space:]]*["'\'']?[a-z]{20}([^a-z]|$)'
  collect_grep "$file" "$host_re"
  hit_callback() { report deployment-supabase-host deployment "$file" "$HIT_LINE"; }
  each_hit
  collect_grep "$file" "$ref_re"
  hit_callback() { report deployment-supabase-host deployment "$file" "$HIT_LINE"; }
  each_hit
}

scan_connection_string() {
  local file="$1" dsn_re
  dsn_re=$(printf '%s%s' 'postgres(ql)?://' '[^[:space:]'\''"<>]+')
  collect_grep "$file" "$dsn_re"
  hit_callback() {
    local match rest host flagged=0
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      rest=${match#*://}
      if [[ "$rest" == *@* ]]; then
        rest=${rest#*@}
      fi
      if [[ "$rest" == \[* ]]; then
        host=${rest#\[}
        host=${host%%\]*}
      else
        host=${rest%%[:/?#]*}
      fi
      if ! allowed_db_host "$host"; then
        flagged=1
      fi
    done <<PUBLIC_SAFETY_END
$(printf '%s\n' "$HIT_CONTENT" | grep -o -E -e "$dsn_re" || true)
PUBLIC_SAFETY_END
    if [[ "$flagged" -eq 1 ]]; then
      report deployment-connection-string deployment "$file" "$HIT_LINE"
    fi
  }
  each_hit
}

scan_operational() {
  local file="$1" op_re
  op_re='(custody_receipt|routing_record|exact_private_count|stable_watermark)[[:space:]]*[:=][[:space:]]*["'\'']?([^[:space:]"'\''#]+)'
  collect_grep "$file" "$op_re"
  hit_callback() {
    local value
    if [[ "$HIT_CONTENT" =~ $op_re ]]; then
      value=${BASH_REMATCH[2]}
      if ! is_placeholder_value "$value"; then
        report operational-receipt operational "$file" "$HIT_LINE"
      fi
    fi
  }
  each_hit
}

scan_inventory() {
  local file="$1" inv_re
  inv_re=$(printf '%s%s' 'Argument data ' 'types')
  collect_grep "$file" "$inv_re"
  hit_callback() { report live-schema-inventory inventory "$file" "$HIT_LINE"; }
  each_hit
}

scan_transcript() {
  local file="$1"
  collect_grep "$file" '^[[:space:]]*From:[[:space:]]+[^[:space:]]+@[^[:space:]]+'
  hit_callback() { report coordination-transcript transcript "$file" "$HIT_LINE"; }
  each_hit
}

scan_file() {
  local file="$1"
  scan_private_key "$file"
  scan_aws "$file"
  scan_github_token "$file"
  scan_slack "$file"
  scan_vendor_token "$file"
  scan_jwt "$file"
  scan_assignment "$file"
  scan_email "$file"
  scan_phone "$file"
  scan_home_path "$file"
  scan_ip "$file"
  scan_hostname "$file"
  scan_supabase "$file"
  scan_connection_string "$file"
  scan_operational "$file"
  scan_inventory "$file"
  scan_transcript "$file"
}

normalize_path() {
  local file="$1"
  file=${file#./}
  case "$file" in
    "$ROOT_DIR"/*) file=${file#"$ROOT_DIR"/} ;;
    /*) die "path is outside the repository: $file" ;;
  esac
  printf '%s\n' "$file"
}

resolve_base() {
  if [[ -n "$base" ]]; then
    printf '%s\n' "$base"
    return 0
  fi
  if [[ -n "${PUBLIC_SAFETY_BASE:-}" ]]; then
    printf '%s\n' "$PUBLIC_SAFETY_BASE"
    return 0
  fi
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" && -n "${GITHUB_BASE_REF:-}" ]]; then
      printf 'origin/%s\n' "$GITHUB_BASE_REF"
      return 0
    fi
    if [[ -n "${GITHUB_EVENT_BEFORE:-}" ]]; then
      printf '%s\n' "$GITHUB_EVENT_BEFORE"
      return 0
    fi
    die "GitHub Actions is set but no base ref was provided. Pass --base REF."
  fi
  if git rev-parse --verify --quiet origin/main >/dev/null; then
    git merge-base HEAD origin/main
    return 0
  fi
  if git rev-parse --verify --quiet main >/dev/null; then
    git merge-base HEAD main
    return 0
  fi
  die "cannot resolve a base ref. Pass --base REF."
}

append_diff_names() {
  local spec="$1" status=0
  # git diff exits 0 by default. Treat only real failures (exit > 1) as errors
  # so an optional diff.exitCode setting cannot turn a non-empty diff into a crash.
  set +e
  # shellcheck disable=SC2086
  git diff --name-only --diff-filter=ACMR $spec >>"$WORK/raw"
  status=$?
  set -e
  if [[ "$status" -gt 1 ]]; then
    die "git diff failed for ${spec:-working tree} (exit ${status})"
  fi
}

collect_changed_files() {
  local resolved
  resolved=$(resolve_base)
  if [[ "$resolved" =~ ^0{40}$ ]]; then
    echo "public-safety: previous SHA is unset; scanning all tracked files instead of an empty diff."
    mode=all
    collect_all_files
    return 0
  fi
  git rev-parse --verify --quiet "${resolved}^{commit}" >/dev/null || die "base ref not found: ${resolved}"
  base=$resolved
  : >"$WORK/raw"
  append_diff_names "${resolved}...HEAD"
  if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
    append_diff_names ""
    append_diff_names "--cached"
    git ls-files --others --exclude-standard >>"$WORK/raw"
  fi
}

collect_all_files() {
  git ls-files >"$WORK/raw"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --changed)
      [[ -z "$mode" || "$mode" == "changed" ]] || die "choose only one of --changed, --all, or --paths"
      mode=changed
      shift
      ;;
    --all)
      [[ -z "$mode" || "$mode" == "all" ]] || die "choose only one of --changed, --all, or --paths"
      mode=all
      shift
      ;;
    --base)
      [[ $# -ge 2 ]] || die "--base requires a ref"
      base=$2
      shift 2
      ;;
    --paths)
      [[ -z "$mode" || "$mode" == "paths" ]] || die "choose only one of --changed, --all, or --paths"
      mode=paths
      shift
      [[ $# -gt 0 ]] || die "--paths requires at least one file"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --*) break ;;
        esac
        paths+=("$1")
        shift
      done
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$mode" ]] || mode=changed
if [[ "$mode" != "changed" && -n "$base" ]]; then
  die "--base is only valid with --changed"
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository"

WORK=$(mktemp -d)
: >"$WORK/seen"
: >"$WORK/raw"
: >"$WORK/files"

case "$mode" in
  changed) collect_changed_files ;;
  all) collect_all_files ;;
  paths)
    for path in "${paths[@]}"; do
      normalize_path "$path" >>"$WORK/raw"
    done
    ;;
esac

if [[ -s "$WORK/raw" ]]; then
  sort -u "$WORK/raw" >"$WORK/files"
fi

file_count=0
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  file=${file#./}
  case "$file" in
    *" => "*) file=${file##* => } ;;
  esac
  if [[ "$mode" != "paths" ]] && publication_excluded "$file"; then
    continue
  fi
  if [[ "$mode" == "paths" && ! -f "$file" ]]; then
    die "not a file: $file"
  fi
  [[ -f "$file" ]] || continue
  file_count=$((file_count + 1))
  scan_file "$file"
done <"$WORK/files"

if [[ "$mode" == "changed" ]]; then
  printf 'public-safety: mode=changed base=%s files=%s\n' "${base:-unresolved}" "$file_count"
else
  printf 'public-safety: mode=%s files=%s\n' "$mode" "$file_count"
fi

if [[ "$file_count" -eq 0 ]]; then
  echo "public-safety: 0 files scanned. This is not a clean verdict."
  exit 0
fi

if [[ "$findings" -eq 0 ]]; then
  printf 'public-safety: no pattern findings in %s file(s). Human review is still required.\n' "$file_count"
  exit 0
fi

printf 'public-safety: %s finding(s). Pattern matches are triage signals, not proof of a leak or of safety.\n' "$findings"
exit 1
