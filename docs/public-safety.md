# Public-safety gates

This repository publishes portable doctrine, neutral contracts, synthetic
fixtures, generic conformance tests, and reusable tooling. Real deployment
operations, migrations, evidence, and security findings belong only in approved
private systems.

Two gates sit in front of publication:

1. A dependency-light scan of changed files, `scripts/public_safety_scan.sh`.
2. A human checklist for text the scan cannot read.

A green scan is not clearance. Pattern matching cannot establish context or
attack value. A check that fires on ordinary doctrine or on public fixtures is
not finished: each rule below has a synthetic input that must fail and a
near-miss that must pass.

This scan does not connect to a database or to Supabase, does not rewrite git
history, and does not publish a release. It does not close live-acceptance work.

## Run it locally

From the repository root:

```bash
# Changed files versus the merge-base with main, plus staged, unstaged, and untracked files.
bash scripts/public_safety_scan.sh

# The same diff against an explicit base.
bash scripts/public_safety_scan.sh --changed --base origin/main

# Every tracked file except the synthetic positive controls.
bash scripts/public_safety_scan.sh --all

# Positive controls, near-misses, existing public fixtures, and git-mode checks.
bash scripts/test_public_safety_scan.sh

bash -n scripts/public_safety_scan.sh
bash -n scripts/test_public_safety_scan.sh
```

Local default, when `GITHUB_ACTIONS` is unset:

- Diff `HEAD` against the merge-base with `origin/main`, or with `main` if
  `origin/main` is absent.
- Also scan staged changes, unstaged changes, and untracked files.
- If neither ref exists, the command exits 2. Pass `--base REF`.

`GITHUB_ACTIONS` does not add untracked files. Pass `--base`. A pull request
should use the base commit. A push should use the previous commit. Forty zero
digits means there is no previous commit; the scan reads all tracked files
instead of calling that empty range clean.

| Exit | Meaning |
|---|---|
| 0 | No findings, or zero files. Zero files prints `This is not a clean verdict.` |
| 1 | One or more findings. |
| 2 | Usage or git error. |

Findings name the rule, the class, and the location. Matched text is not
printed, so a workflow log does not become a second copy of a secret.

## What the file scan flags

| Rule | Class | Finding |
|---|---|---|
| `secret-private-key` | secret | PEM private-key block |
| `secret-aws-access-key` | secret | AWS access-key id shape |
| `secret-github-token` | secret | GitHub token shape |
| `secret-slack-token` | secret | Slack token shape |
| `secret-vendor-token` | secret | `sk-` or `sbp_` token shape |
| `secret-jwt` | secret | Three-segment JWT shape |
| `secret-assignment` | secret | Long secret, token, or password assignment that is not a placeholder |
| `contact-email` | contact | Email outside the documentation domains below |
| `contact-phone` | contact | Phone number outside the reserved fictional range below |
| `local-home-path` | deployment | Home-directory or drive-letter user path |
| `deployment-ip` | deployment | IPv4 address outside loopback and the documentation ranges below |
| `deployment-hostname` | deployment | Name under `.internal`, or under `.local` other than `example.local` |
| `deployment-supabase-host` | deployment | Hosted project URL, pooler host, or 20-letter `project_ref` |
| `deployment-connection-string` | deployment | Postgres URL whose host is not local |
| `operational-receipt` | operational | Concrete `custody_receipt`, `routing_record`, `exact_private_count`, or `stable_watermark` |
| `live-schema-inventory` | inventory | Pasted psql function-list header |
| `coordination-transcript` | transcript | A leading `From:` mail header with an address |

These are the high-confidence shapes. They are not the whole risk list.

### Allowed placeholders

The near-miss fixtures and the scanner agree on these:

- Email domains `example.com`, `example.org`, `example.net`, `example.invalid`,
  `example.local`, `localhost`, and subdomains of the `example.*` names.
  `you@example.com` is the usual contact placeholder.
- Phone numbers whose exchange is `555` and whose last four digits are
  `0100` through `0199`, such as `+1-212-555-0100`. Any other phone-shaped
  number is a finding. The checker cannot know that it was meant to be fake.
- IPv4 `127.0.0.1`, `0.0.0.0`, `255.255.255.255`, and the documentation ranges
  `192.0.2.0/24`, `198.51.100.0/24`, and `203.0.113.0/24`.
- The hostname `example.local`. A suffix that continues an identifier with an underscore is not a hostname.
- Postgres URLs whose host is `localhost`, `127.0.0.1`, `0.0.0.0`, or `::1`,
  including `postgres://postgres:postgres@localhost:5432/postgres`.
- Assignment values that are `REDACTED`, contain `example` or `placeholder`,
  or are shorter than 16 characters (`password: postgres`).
- Operational keys whose value is `REDACTED`, an example, or a `<placeholder>`.
- Hosted-project examples that are not a 20-letter ref, such as
  `https://<project-ref>.supabase.co`.

Other contributor placeholders are in [CONTRIBUTING.md](../CONTRIBUTING.md).

### What the file scan does not decide

- Issue titles, issue bodies, issue comments, pull-request text, reviews,
  release notes, workflow logs, and uploaded artifacts. Those are publication
  surfaces. Use the checklist below.
- Git history. The scan reads the current contents of the selected files. It
  does not search older commits, and it does not rewrite them.
- Whether a count, manifest, watermark, stable digest, custody receipt, or
  routing record is private. Generic checksums are not flagged: public package
  checksums and the release schema fingerprint use the same shape. The
  operational rule flags only the four concrete keys above. Stable digests stay
  on the human checklist.
- Whether a schema or RPC note is reference doctrine or a live inventory. The
  reviewed SECURITY DEFINER inventory in this repository is doctrine. A pasted
  psql function-list header is the automated signal. Inventories that do not use
  that header are a human-review item, including access-control findings,
  denial paths, and other attack-relevant configuration.
- IPv6 addresses, except a bracketed `::1` database host.
- Attack value. A match is a triage signal. Silence is not proof.

`tests/public_safety/fixtures/fail/` is excluded from `--changed` and `--all`
because those files are the positive controls. `--paths` does not apply that
exclusion. The regression script scans them and expects findings. Do not put
real evidence in that directory.

## Human checklist

Confirm the publication surface contains none of the following, or replace them
with synthetic placeholders:

- [ ] No personal, household, employer, client, account, or private-project facts
- [ ] No secrets, credentials, credential references, or rotation details
- [ ] No real deployment identifiers, URLs, hostnames, IP addresses, device names, topology, or local paths
- [ ] No exact private counts, manifests, watermarks, stable digests, custody receipts, or routing records
- [ ] No live schema/RPC inventories, access-control findings, denial paths, or attack-relevant configuration
- [ ] No personal contact or location information
- [ ] No internal coordination transcripts or sequence reconstructions
- [ ] Nothing that materially reduces the effort required to attack a real deployment

The same list is in the issue templates and in
[.github/pull_request_template.md](../.github/pull_request_template.md). Keep
those copies aligned. The regression script checks that the templates still
carry the private-count line.

## Publication surfaces

Treat all of the following as publication, not as private scratch space:

- issue titles, bodies, and comments
- pull-request titles, bodies, review comments, and inline suggestions
- release notes and tag messages
- workflow logs
- uploaded artifacts

Before opening or updating an issue or pull request, run the changed-file scan
and complete the checklist for the text you are about to publish. Review
comments are part of that surface even when they are not in the diff.

Before a release, run `bash scripts/public_safety_scan.sh --all` and apply the
checklist to the release notes, the tag message, and anything the workflow will
upload. Do not upload private exports, live schema or RPC inventories, or
credential-bearing logs. The scan does not inspect an artifact after upload.

Workflow logs should not echo secrets. This scanner prints rule, class, and
location only. Do not add a step that prints the matched line, and do not enable
shell tracing around credential material.

## CI

[.github/workflows/public-safety.yml](../.github/workflows/public-safety.yml)
is read-only (`contents: read`). On a pull request it scans the diff against
the base commit. On a push to `main` it scans the pushed range. A manual run
scans tracked files. Every run also executes
`scripts/test_public_safety_scan.sh`, which includes the full tracked-file scan
and the synthetic controls.

## Regression fixtures

See [tests/public_safety/README.md](../tests/public_safety/README.md).

- `tests/public_safety/fixtures/fail/` must fail for the named rule.
- `tests/public_safety/fixtures/pass/` must not fire, including ordinary words
  and a public checksum shape.
- The existing Chat-Mine and v2 upgrade fixtures must pass. There are no
  intentional hits.
