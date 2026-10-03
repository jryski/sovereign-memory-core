#!/usr/bin/env bash
set -euo pipefail

# Run the local criterion-shape conformance suite and its unit tests.
# No database and no live Supabase target are required.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Criterion-shape conformance"
python3 "${ROOT_DIR}/scripts/conformance_criteria.py" \
  "${ROOT_DIR}/fixtures/conformance/criterion_shape_suite.json"

echo "==> Criterion-shape unit tests"
cd "${ROOT_DIR}"
python3 -m unittest discover -s tests/conformance -p 'test_*.py' -v
