#!/usr/bin/env bash
# Disposable-lab runner for scripts/validate_install_profile.py.
# Starts a throwaway local Postgres cluster (initdb in a temp dir), runs one
# positive plus static/apply negatives, then tears everything down. Never touches remotes.
set -euo pipefail
# Inherited libpq variables (PGHOSTADDR, PGSERVICE, PGSERVICEFILE, and every
# other PG* name) must not steer createdb, dropdb, or psql. Drop them before
# any client tool runs, then pin host and port on each invocation.
scrub_libpq() {
  local name
  while IFS= read -r name; do
    if [[ "$name" == PG* ]]; then
      unset "$name"
    fi
  done < <(compgen -e)
}
scrub_libpq
client() { scrub_libpq; "$@"; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
if [[ -n "${OUT_DIR:-}" ]]; then OUT="$OUT_DIR"; mkdir -p "$OUT"; OUT_TMP=""; else OUT="$(mktemp -d)"; OUT_TMP="$OUT"; fi
LAB="$(mktemp -d)"; PORT="${LAB_PORT:-55432}"
cleanup(){ "$PGBIN/pg_ctl" -D "$LAB/data" -m fast stop >/dev/null 2>&1 || true; rm -rf "$LAB"; if [[ -n "$OUT_TMP" && "${KEEP_OUT:-0}" != 1 ]]; then rm -rf "$OUT_TMP"; fi; }
trap cleanup EXIT
"$PGBIN/initdb" -D "$LAB/data" -U postgres -A trust >/dev/null
NONCE="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
"$PGBIN/pg_ctl" -D "$LAB/data" -o "-p $PORT -k $LAB -c listen_addresses='' -c e02.invocation=$NONCE" -l "$LAB/log" -w start >/dev/null
echo "$LAB" > "$OUT/lab_dir.txt"
head -1 "$LAB/data/postmaster.pid" > "$OUT/postmaster.pid"
unset E02_LAB_PROOF
base="postgresql://postgres@/%s?host=$LAB&port=$PORT"
mkdb(){ client "$PGBIN/createdb" -h "$LAB" -p "$PORT" -U postgres "$1"; }
bind_proof(){ # dbname — record this invocation's lab before any validator SQL
  python3 - "$ROOT" "$LAB" "$PORT" "$$" "$1" "$NONCE" <<'PY'
import importlib.util, sys
root, lab, port, creator, db, nonce = sys.argv[1:7]
spec = importlib.util.spec_from_file_location("validate_install_profile", f"{root}/scripts/validate_install_profile.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.write_invocation_proof(f"{lab}/invocation.json", f"{lab}/data", lab, int(port), db, int(creator), nonce)
PY
  export E02_LAB_PROOF="$LAB/invocation.json"
}
dropdb_(){ client "$PGBIN/dropdb" -h "$LAB" -p "$PORT" -U postgres --if-exists "$1"; }
fail=0

echo "==> POSITIVE: apply minimal_portable to disposable DB"
mkdb e02_pos
bind_proof e02_pos
DATABASE_URL="$(printf "$base" e02_pos)" python3 "$ROOT/scripts/validate_install_profile.py" --root "$ROOT" --apply --receipt "$OUT/receipt.json" > "$OUT/positive.json" && echo "PASS positive" || { echo "FAIL positive"; fail=1; }
dropdb_ e02_pos

echo "==> NEGATIVE 1: omitted dependency (sql/08 removed in temp tree copy)"
T="$(mktemp -d)"; cp -r "$ROOT/sql" "$ROOT/fixtures" "$T/"; rm "$T/sql/08_attention_events.sql"
if python3 "$ROOT/scripts/validate_install_profile.py" --root "$T" --receipt "$OUT/neg1-receipt.json" > "$OUT/neg-omitted.json"; then echo "FAIL neg1 (accepted)"; fail=1
elif grep -q MISSING_DEPENDENCY "$OUT/neg-omitted.json" && [[ ! -e "$OUT/neg1-receipt.json" ]]; then echo "PASS neg1 MISSING_DEPENDENCY, no receipt"; else echo "FAIL neg1 wrong code"; fail=1; fi
echo "==> NEGATIVE 1b: profile drops 08 from list (arbitrary list not sufficient)"
python3 - "$T" <<'PY'
import json,sys; p=f"{sys.argv[1]}/fixtures/install_profiles/minimal_portable.json"
m=json.load(open(p)); m["migrations"]=[x for x in m["migrations"] if "08_" not in x["path"]]; json.dump(m,open(p,"w"))
PY
cp "$ROOT/sql/08_attention_events.sql" "$T/sql/"
if python3 "$ROOT/scripts/validate_install_profile.py" --root "$T" > "$OUT/neg-unlisted.json"; then echo "FAIL neg1b"; fail=1
elif grep -q MANIFEST_UNLISTED_MIGRATION "$OUT/neg-unlisted.json" && grep -q MISSING_DEPENDENCY "$OUT/neg-unlisted.json"; then echo "PASS neg1b MANIFEST_UNLISTED_MIGRATION+MISSING_DEPENDENCY"; else echo "FAIL neg1b wrong code"; fail=1; fi
rm -rf "$T"


# Static negatives: each mutates a temp copy of the profile (and optionally the tree)
# and must exit non-zero with the expected code, valid JSON, no traceback, no receipt.
statneg(){ # name code python-mutation [shell-setup]
  local name="$1" code="$2" mut="$3" setup="${4:-}" T; T="$(mktemp -d)"; cp -r "$ROOT/sql" "$ROOT/fixtures" "$T/"
  if [[ -n "$setup" ]]; then (cd "$T" && eval "$setup"); fi
  python3 -c 'import json,sys; p=sys.argv[1]+"/fixtures/install_profiles/minimal_portable.json"; m=json.load(open(p)); exec(sys.argv[2]); json.dump(m,open(p,"w"))' "$T" "$mut"
  local o="$OUT/neg-$name.json" e="$OUT/neg-$name.stderr"
  if python3 "$ROOT/scripts/validate_install_profile.py" --root "$T" --receipt "$T/r.json" >"$o" 2>"$e"; then echo "FAIL $name (accepted)"; fail=1
  elif python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if not d["ok"] and any(x["code"]==sys.argv[2] for x in d["errors"]) else 1)' "$o" "$code" && ! grep -q Traceback "$e" && [[ ! -e "$T/r.json" ]]; then echo "PASS $name $code"
  else echo "FAIL $name (expected $code)"; fail=1; fi
  [[ -s "$e" ]] || rm -f "$e"
  rm -rf "$T"
}
echo "==> STATIC NEGATIVES"
statneg sha-removed PROFILE_INVALID 'for x in m["migrations"]: x.pop("sha256")'
statneg sha-short PROFILE_INVALID 'm["migrations"][2]["sha256"]="abc123"'
statneg sha-nonhex PROFILE_INVALID 'm["migrations"][2]["sha256"]="z"*64'
statneg sha-empty PROFILE_INVALID 'm["migrations"][2]["sha256"]=""'
statneg req11-excluded REQUIRED_MIGRATION_EXCLUDED 'm["migrations"]=m["migrations"][:-1]; m["excluded_optional"].append("sql/11_perimeter_evaluability.sql"); m["order_constraints"]=[c for c in m["order_constraints"] if "last" not in c]'
statneg new12-excluded REQUIRED_MIGRATION_EXCLUDED 'm["excluded_optional"].append("sql/12_extra.sql")' 'echo "select 1;" > sql/12_extra.sql'
statneg new12-unlisted MANIFEST_UNLISTED_MIGRATION 'm["excluded_optional"].append("sql/12_extra.sql")' 'echo "select 1;" > sql/12_extra.sql'
statneg upper-SQL MANIFEST_UNLISTED_MIGRATION 'pass' 'echo "select 1;" > sql/12_Extra.SQL'
statneg abs-path PATH_INVALID 'm["migrations"][1]["path"]="/etc/hostname"'
statneg traversal PATH_INVALID 'm["migrations"][1]["path"]="sql/../fixtures/install_profiles/minimal_portable.json"'
statneg nondict-entry PROFILE_INVALID 'm["migrations"][1]="sql/07_work_lessons.sql"'
statneg path-int PROFILE_INVALID 'm["migrations"][1]["path"]=7'
statneg profile-list PROFILE_INVALID 'm=[m]'
statneg bad-postcheck-ident PROFILE_INVALID 'm["post_checks"]["tables"].append("x%c);drop table y;--" % 39)'
statneg order ORDER_VIOLATION 'm["migrations"][3],m["migrations"][4]=m["migrations"][4],m["migrations"][3]'
statneg digest-mismatch DIGEST_MISMATCH 'pass' 'echo "-- tamper" >> sql/10_security_definer_hardening.sql'

echo "==> NEGATIVE 2: rollback on forced failure mid-profile (sql/09)"
T="$(mktemp -d)"; cp -r "$ROOT/sql" "$ROOT/fixtures" "$T/"
printf "\ndo \$\$ begin raise exception 'E02 forced failure'; end \$\$;\n" >> "$T/sql/09_perimeter_refresh.sql"
python3 - "$T" <<'PY'
import json,sys; p=f"{sys.argv[1]}/fixtures/install_profiles/minimal_portable.json"
m=json.load(open(p))
import hashlib
for x in m["migrations"]:
    if "09_" in x["path"]: x["sha256"]=hashlib.sha256(open(f"{sys.argv[1]}/sql/09_perimeter_refresh.sql","rb").read()).hexdigest()
json.dump(m,open(p,"w"))
PY
mkdb e02_rb
bind_proof e02_rb
DSN="$(printf "$base" e02_rb)"
if DATABASE_URL="$DSN" python3 "$ROOT/scripts/validate_install_profile.py" --root "$T" --apply --receipt "$OUT/neg2-receipt.json" > "$OUT/neg-rollback.json"; then echo "FAIL neg2 (accepted)"; fail=1
else
  r=$(client "$PGBIN/psql" -X -tA -h "$LAB" -p "$PORT" -U postgres -d e02_rb -c "select to_regclass('public.perimeter_acl_policy') is null and to_regclass('public.attention_events') is not null")
  if grep -q APPLY_FAILED "$OUT/neg-rollback.json" && [[ "$r" == t ]] && [[ ! -e "$OUT/neg2-receipt.json" ]]; then echo "PASS neg2 APPLY_FAILED, 09 rolled back, no receipt"; else echo "FAIL neg2 r=$r"; fail=1; fi
fi
dropdb_ e02_rb; rm -rf "$T"
left=$(client "$PGBIN/psql" -X -tA -h "$LAB" -p "$PORT" -U postgres -d postgres -c "select count(*) from pg_database where datname like 'e02_%'")
echo "==> disposable DBs remaining: $left"; [[ "$left" == 0 ]] || fail=1
echo "==> outputs in $OUT${OUT_TMP:+ (temp; removed on exit unless KEEP_OUT=1)}"; exit $fail
