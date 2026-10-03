# Public-safety regression fixtures

These files are synthetic. They are not copies of a deployment, an export, a
transcript, or an incident.

## fail/

Positive controls. Each file names the rule it must trip in `expected-rule` and
the minimum number of findings in `min-findings`.

`scripts/public_safety_scan.sh --changed` and `--all` skip this directory so the
positive controls do not fail the publication scan. That skip is not an
allowlist for real evidence. `scripts/test_public_safety_scan.sh` scans these
paths with `--paths` and fails if the expected rule is missing.

## pass/

Near-miss controls. The text is structurally similar to a positive control and
must not fire. Placeholders match [CONTRIBUTING.md](../../CONTRIBUTING.md):
`example.local`, `you@example.com`, `REDACTED`, loopback and documentation-range
addresses, and local Postgres URLs.

`adversarial-noise.txt` adds ordinary words (`test`, `main`) and a public
checksum shape. Those must not become findings.

## Existing public fixtures

The regression script also scans:

- `fixtures/chat_mine/sample_chat_export.json`
- `fixtures/chat_mine/expected_source_import_package.json`
- `tests/fixtures/v2_upgrade_seed.sql`
- `tests/fixtures/v2_upgrade_verify.sql`

## Intentional hits

None. Those existing fixtures are expected to pass with no documented exception.
If a future public fixture must contain a pattern the scanner flags, record the
path, rule, and reason here and teach the regression script to allow only that
pair. Do not copy private evidence in to justify a hit.
