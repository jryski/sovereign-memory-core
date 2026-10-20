# Core LEAK-01 history triage

Reviewed: 2026-10-20 12:54:41 UTC. Repository: `jryski/sovereign-memory-core`.

[History scan 39425202351](https://github.com/jryski/sovereign-memory-core/actions/runs/39425202351) returned **findings**, exit 1, rather than an inability result. It scanned **289 commits, 422 metadata objects, 296 paths, and 659 unique blobs**. There were **75 findings and zero private-literal findings** under the configured policy.

| Safe path | Rule / findings | Independent classification | Current main |
| --- | --- | --- | --- |
| `fixtures/chat_mine/expected_source_import_package.json` | generic-api-key / 40 | Historic source/probe key fields equal the synthetic fixture's conversation identifier. | Path remains; reported historic bytes and line values changed. |
| `fixtures/chat_mine/sample_chat_export.json` | generic-api-key / 32 | Same synthetic conversation identifier relationship. | Path remains; reported historic bytes and line values changed. |
| `tests/public_safety/fixtures/fail/secret-private-key.txt` | private-key / 2 | Labelled synthetic, non-real negative fixture; OpenSSL cannot parse/check its PEM block. | Absent. Present only on unmerged PR #100 branch. |
| `tests/public_safety/fixtures/fail/secret-jwt.txt` | jwt / 1 | Labelled synthetic negative fixture; decoded payload is fixture-labelled and signature segment is 12 characters. | Absent. Present only on unmerged PR #100 branch. |

The two JSON groups span eight historic commits. Their values were changed in main by scrub commit `1855435`; historic bytes remain reachable through main ancestry, approximately 60 branch refs, and `v0.3-alpha`. The negative PEM/JWT fixtures remain at PR #100 branch tip `099c6c0e115aa0247deda9d7f367a1ca9b490016`, and have no containing release tags.

Path-to-finding mappings were independently checked by hashing local Git paths and matching the scanner's SHA-256 path identifiers. Exact source blob identifiers and proof booleans are in the companion JSON. No matched values, private policy expressions, or credential material are included.

No actual credential or configured private-identifier exposure was established by these Core findings. **The raw scan remains `findings`.** This classification is not a clean-history certificate or proof that all private data is absent. No policy change, suppression, ref deletion, or history rewrite was performed.

## Activation receipt

Source repair [PR #126](https://github.com/jryski/sovereign-memory-core/pull/126) is merged as `c8fad4252b5d3efeb1c51d487b03cb6a1f92f244`. The independently inspected [trusted push scan 39424737284](https://github.com/jryski/sovereign-memory-core/actions/runs/39424737284) completed successfully on that exact commit.

The operator configured bounded private-identifier policy v1 through protected secret management. Policy contents and protected categories are deliberately absent from this receipt. The operator reported successful encoding/regex validation, intended blocking and benign controls, private source ACL checks, and secret metadata confirmation. This reviewer independently observed the trusted run outcome and the ruleset readbacks below, without copying the private source policy.

An operational scan and a configured policy do not establish complete PII coverage. The subsequent history scan remains `findings`; its synthetic classifications and coverage limits are retained below.

## Repair qualification

[PR #126](https://github.com/jryski/sovereign-memory-core/pull/126), reviewed exact head `f571725e446de8e0af5c0a8ff1b0a27bc7ab2da6`, scopes `GIT_CONFIG_GLOBAL=/dev/null` to the four post-checkout trusted shell steps. Its workflow Git blob is `be29260b0a0fbe0d5a4c5807efdc7dbb2a4fb243`. Scanner, policy, secret isolation, and privileges are unchanged.

Independent qualification used checksum-verified **actionlint 1.7.12** and **Gitleaks 8.30.1**: **81 tests passed, zero failures, errors, or skips**. Both leak workflows passed actionlint. Nineteen materialized source files were checked against upstream Git blob identifiers before applying the sole reviewed workflow patch.

## Required-check readback

Independent GitHub API reads at the review time confirmed:

| Public repository | Ruleset | LEAK-01 required | Publisher integration | Strict up to date | Existing checks |
| --- | --- | --- | --- | --- | --- |
| Core | 24057304 | Yes | 15368 | Yes | C1 PostgreSQL 15 and 16 retained |
| Household-OS | 24057309 | Yes | 15368 | Yes | No prior required status checks |
| Supabase_user_MCP | 24057302 | Yes | 15368 | Yes | Build and test; M2 acceptance retained |

All three rulesets are active and include the default branch. Integration 15368 identifies GitHub Actions, not one immutable trusted workflow source; independent review of the actual trusted scan remains necessary. Private-repository required rules are unavailable under the current plan, with manual review of the exact head retained as the stated fallback.

## Non-destructive next steps

Retain this triage beside the raw result. If PR #100 resumes, generate credential-shaped negative fixtures inside disposable test directories rather than committing static credential-shaped text. Do not rewrite history, move release tags, delete refs, or weaken policy merely to make the historical scan green. Any later history rewrite needs explicit owner authorization, preservation, and consumer coordination.

The configured private-identifier policy is bounded. This receipt does not certify complete PII coverage, repository logs/releases, external data, unreachable Git objects, or uncommitted files.
