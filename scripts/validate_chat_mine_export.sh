#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="${ROOT_DIR}/fixtures/chat_mine/sample_chat_export.json"
EXPECTED="${ROOT_DIR}/fixtures/chat_mine/expected_source_import_package.json"
GENERATED="$(mktemp)"
SECOND="$(mktemp)"
trap 'rm -f "${GENERATED}" "${SECOND}"' EXIT

python3 "${ROOT_DIR}/scripts/export_chat_mine_package.py" "${FIXTURE}" "${GENERATED}"
python3 "${ROOT_DIR}/scripts/export_chat_mine_package.py" "${FIXTURE}" "${SECOND}"

cmp "${GENERATED}" "${SECOND}"
cmp "${GENERATED}" "${EXPECTED}"
python3 "${ROOT_DIR}/scripts/validate_chat_mine_package.py" "${GENERATED}"
python3 "${ROOT_DIR}/scripts/test_chat_mine_package_negative.py" "${GENERATED}"

if [[ -n "${DATABASE_URL:-}" ]]; then
  PACKAGE_JSON="$(
    python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), separators=(",",":"), sort_keys=True))' \
      "${GENERATED}"
  )"
  psql "${DATABASE_URL}" \
    -v ON_ERROR_STOP=1 \
    -v package_json="${PACKAGE_JSON}" \
    -f "${ROOT_DIR}/sql/validation/load_chat_mine_package.sql"
  echo "PASS: Chat-Mine package loads into the core schema and rolls back"
  python3 "${ROOT_DIR}/scripts/test_chat_mine_loader_negative.py" \
    "${GENERATED}" \
    "${ROOT_DIR}/sql/validation/load_chat_mine_package.sql"
fi

echo "PASS: Chat-Mine package generation is deterministic and matches the fixture"
