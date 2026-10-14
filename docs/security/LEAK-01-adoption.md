# Adopt LEAK-01 in another repository

LEAK-01 is a reusable repository leak guard. A business, household or other
project can adopt the same scanner, workflow and tests with its own protected
policy inputs. It does not require the memory runtime, a database migration,
Supabase or a particular model.

Read the [operator guide](LEAK-01.md) for the trust boundary, detection limits,
qualification, required-status enforcement and rollback. This guide explains
what to transfer and what the receiving project must establish independently.

## Implementation status and supported environment

The initial package is merged in Core at
`ae88f6bd8bf45badf486f82b384f380a37aced3a`. That workflow contains an invalid
`cancelled()` expression in a step environment variable. Its jobs cannot start.
The correction, full-workflow semantic validation and unprivileged regression
CI are proposed in
[PR #123](https://github.com/jryski/sovereign-memory-core/pull/123), at candidate
source head `d7ef1edab7e69e56e45333b164521d3eb253c659`. This guide does not
certify that draft or claim an operational gate. Select the final independently
reviewed repair commit before adoption; record that exact commit in the
receiving project's receipt.

The supplied workflow supports GitHub.com repositories whose default branch is
`main`, using `ubuntu-24.04` runners. Its installers support Linux x86_64.
The workflow uses the runner's system `python3` on `ubuntu-24.04`; the reported
local qualification used Python 3.13.5. Record and qualify the Python version
used in the receiving environment.
GitHub Enterprise, another default branch or another architecture requires an explicit
adapter change and its own review and acceptance. The current workflow refuses
unsupported event revisions.

## Shared files and receiving-project inputs

Transfer one consistent reviewed source revision, preserving license and SPDX
notices. Do not combine files from unreviewed branches or replace the pinned
scanner with an unverified binary. Include the semantic validator once the
repair is approved.

| Transfer | Paths | Receiving-project responsibility |
| --- | --- | --- |
| Workflows | `.github/workflows/leak-gate.yml`, `.github/workflows/leak-ci.yml` | Review its event handling, trusted source and status permissions under the receiving repository's Actions policy. |
| Credential and artifact controls | `.gitleaks.toml`, `scripts/leak/classify_literals.py`, `scripts/leak/gate.py` | Preserve the detection and fail-closed boundary. |
| Scanner installation | `scripts/leak/scanner-pin.json`, `scripts/leak/install_gitleaks.py` | Retain the reviewed release, digest, archive size and executable validation. |
| Semantic validation from the repair | `scripts/leak/actionlint-pin.json`, `scripts/leak/install_actionlint.py`, `tests/leak/test_actions_semantics.py` | Validate the complete workflow, including legal expression contexts. |
| Policy and exceptions | `.leak-policy.json`, `.leak-allowlist` | Set the actual repository privacy classification. Independently review each narrow exception. Public repositories have no private-literal path exemptions. |
| Synthetic qualification | `tests/leak/test_gate.py`, `tests/leak/test_gate.sh`, `tests/leak/test_install_gitleaks.py`, `tests/leak/test_workflow.py`, `tests/leak/test_ci_workflow.py`, `tests/leak/fixtures/README.md` | Run on the exact receiving revision, with both verified native tools available. |
| Operator documentation | `docs/security/LEAK-01.md` | Link it from the receiving repository's README and security documentation. |

The protected `LEAK_PRIVATE_PATTERNS` Actions secret is a separate input. Its
strict base64-encoded UTF-8 text contains one regular expression per line, as
the operator guide specifies. The receiving operator supplies patterns for
that project's own private content. Missing, empty or malformed patterns block
the scan, including in a public repository.

Do not copy another deployment's pattern secret, private exceptions, customer
records, credentials, database grants, identity mappings or operating evidence.
Use fabricated fixtures to demonstrate the controls. Keep real pattern values
and coverage evidence in the receiving project's protected records. Configure
secrets and branch rules only through its authorized operator.

## Local qualification

Run these commands from the root of the **reviewed repair source** on Linux
x86_64. The commands install tools into a temporary directory and run local
synthetic tests; they do not configure GitHub or contact a database.

```bash
set -euo pipefail
leak_tools_dir="$(mktemp -d)"
trap 'rm -rf -- "$leak_tools_dir"' EXIT

python3 scripts/leak/install_gitleaks.py \
  --pin scripts/leak/scanner-pin.json \
  --output "$leak_tools_dir/gitleaks"
python3 scripts/leak/install_actionlint.py \
  --pin scripts/leak/actionlint-pin.json \
  --output "$leak_tools_dir/actionlint"

export LEAK_TEST_GITLEAKS="$leak_tools_dir/gitleaks"
export LEAK_ACTIONLINT="$leak_tools_dir/actionlint"
test -x "$LEAK_TEST_GITLEAKS"
test -x "$LEAK_ACTIONLINT"
python3 --version
bash tests/leak/test_gate.sh
```

Both installers download their pinned official release archives and verify
them before execution. For approved offline qualification, supply each
installer's `--archive` option with the corresponding retained archive. The
same digest, size and executable checks apply.

Retain the tool versions, exact source commit, exit codes, executed test count
and skipped test count. The command fails if either tool is nonexecutable, no
tests run, any test fails or any test is skipped. A run without
`LEAK_TEST_GITLEAKS` skips native scanner cases; it is not equivalent qualification. The semantic validator checks
Actions syntax and expression contexts. It does not prove that GitHub permits
the action, that the token can publish statuses or that real patterns are
complete. Those need receiving-repository acceptance.

The candidate includes an unprivileged pull-request check that runs
full-workflow semantic validation and the complete synthetic suite without
private patterns or deployment secrets. Its `test_gate.sh` wrapper checks both
workflows and fails for missing tools, failed or skipped tests, or empty test
discovery. Core's [candidate regression run](https://github.com/jryski/sovereign-memory-core/actions/runs/38511294040)
executed 78 tests with zero failures, errors or skips. This establishes that
candidate's regression execution, not merge, an operational repository scan or
required-status enforcement. The receiving repository must qualify its own
source, Actions policy and protected inputs independently.

## Result contract

The gate writes JSON and returns one of three exit codes:

| Exit | JSON status | Meaning |
| --- | --- | --- |
| `0` | `clear` | No finding within the declared scan, configured rules and limits. |
| `1` | `findings` | At least one credential, private-literal or artifact finding. |
| `2` | `unable` | Required inputs, history, supported objects or tool execution could not be evaluated. |

A clear result names the exact head and scan mode with scan counters. Findings
contain hashes rather than raw paths and matches. An inability result has a
fixed error code; an empty findings array in that result does not mean clear.
See the operator guide for metadata coverage and unsupported objects.

GitHub receives the fixed `LEAK-01` commit-status context on the prepared target
head. A pending, failed, missing or stale status is not a passing gate. The
repaired final publisher is skipped if cancellation occurs before that step
executes; an already-posted pending status remains blocking. Cancellation after
a result is published does not retract it. If preparation never posted a
status, absence must also block.

## Receiving-repository acceptance receipt

After authorized merge and configuration, the receiving operator retains this
evidence in that project's protected repository or evidence store:

| Evidence | Required content |
| --- | --- |
| Source binding | Origin revision, receiving revision, workflow and policy hashes, reviewed differences and independent review handle. |
| Local qualification | Both verified tools, command results, executed cases and explicit skips. |
| Regression checks | Unprivileged CI running the semantic validator and complete synthetic suite against the exact candidate; distinguish local execution from CI execution. |
| Actions execution | Manual run on `main`; run and job IDs showing `prepare`, `leak-gate` and `publish-result` scheduled, plus the actual status on the exact target head. |
| Negative and positive controls | Disposable clean, seeded credential, private literal and raw artifact, missing patterns, attempted policy bypass and cancellation cases. Record actual outcomes, not expected outcomes alone. |
| History coverage | Full-history run outcome, fetched-ref scope, limits or unsupported objects, and disposition of existing findings. |
| Enforcement | Required `LEAK-01` context, exact-head and freshness behavior, authorized publisher/source restrictions, Actions policy compatibility and any plan limitations. |
| Ownership | Receiving operator, approver, receipt time, rollback owner and protected pattern-coverage reference without pattern values. |

Follow the operator guide's activation order and review any old findings before
certifying history. If source restrictions or required branch rules are
unavailable, record that limitation and retain independent human merge review.
Do not claim automatic enforcement from a workflow file or successful unit tests
alone. A scheduled run that fails because patterns are missing establishes
scheduling only, not a clear scan or an active merge boundary.

## Reuse boundary

Fix shared defects in the common implementation, then carry the reviewed
revision to each receiving repository. Record deployment-specific differences
as small reviewed adapters or policy inputs. Keep each project's data, runtime
identities, permissions and acceptance evidence under that project's authority.

Future shared components need the same handoff: an identifiable source version,
supported environment, input and output contracts, failure behavior, permissions,
synthetic examples, executed validation and stated limits. Deployment approvals
and tests apply only to their named target; another adopter must establish its
own evidence before relying on them.
