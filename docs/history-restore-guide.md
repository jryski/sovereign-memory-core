# History and restore guide (v0.3-alpha, synthetic)

This is the authoritative public procedure for reproducing the Core history and
restore evidence. It runs the provider-exit rehearsal from the exact alpha
source on two new, disposable PostgreSQL 16 clusters. It then validates the
exported bundle against its checksum and removes everything it created.

**What this is:** synthetic restore evidence. It shows that the reviewed alpha
migrations, fabricated principals and fixture records survive export, restore
into an independent cluster and validation. They keep their access controls,
history and perimeter state.

**What this is not:** it does not export or restore private data, rebuild a
hosted provider's control plane, prove signed actor attribution, or recreate the
2026-08-15 release archive byte for byte. See [Limits](#limits).

## Pin

| Item | Value |
| --- | --- |
| Source repository | `https://github.com/jryski/sovereign-memory-core` |
| Source revision | tag `v0.3-alpha`, commit `c96b9da749b2d95661973485b2a026897329c8cd`, tree `b4373e379f79afe68cf2b21c3483c66ecfd9601a` |
| Recipe | [`history-restore/core-restore.ps1`](history-restore/core-restore.ps1), SHA-256 `ebf7359fdb230a141bed4d71942b2e82f89c1b3e096dfc977ab1733df8cfd5aa` |
| Same recipe, alternate copy | `https://wirespeedcomputing.com/examples/core-restore.ps1` (same bytes and checksum) |
| Runtime built by the recipe | `postgres:16-bookworm` with Debian's `python3` added |

Later `main` commits are outside the reviewed coordinate. Do not substitute
`main` for the source checkout; the recipe refuses to run on any other commit.

## Prerequisites

- PowerShell 7 (`pwsh`).
- Git.
- Docker with Linux containers: Docker Desktop on Windows or macOS, or Docker
  Engine on Linux.
- Network access to pull `postgres:16-bookworm` and the Debian `python3`
  package during the image build.
- No credentials, provider account or private data. The only password is
  `synthetic-local-only`, and it exists only inside the disposable clusters,
  which publish no host ports.

## Exact steps

Run these from an empty working directory. The recipe is kept outside the
checkout so that the source tree stays pristine.

```powershell
git clone https://github.com/jryski/sovereign-memory-core.git core-alpha
Set-Location core-alpha
git checkout --detach c96b9da749b2d95661973485b2a026897329c8cd
git rev-parse HEAD 'HEAD^{tree}'
# expect c96b9da749b2d95661973485b2a026897329c8cd
#        b4373e379f79afe68cf2b21c3483c66ecfd9601a

Invoke-WebRequest -Uri https://raw.githubusercontent.com/jryski/sovereign-memory-core/main/docs/history-restore/core-restore.ps1 -OutFile ../core-restore.ps1
if ((Get-FileHash -Algorithm SHA256 ../core-restore.ps1).Hash.ToLowerInvariant() -ne 'ebf7359fdb230a141bed4d71942b2e82f89c1b3e096dfc977ab1733df8cfd5aa') { throw 'Recipe checksum mismatch' }

pwsh -File ../core-restore.ps1
```

On Linux or macOS, `sha256sum ../core-restore.ps1` (or `shasum -a 256`) gives
the same value.

## What the recipe does

1. **Refuses** to run unless `HEAD` is exactly the alpha commit, tracked and
   staged files are clean, and `core-proof/` does not exist yet.
2. Generates a random 12-character run id. Every resource the recipe creates
   carries that id: image `wirespeed-core-proof:<id>`, internal network
   `wirespeed-core-proof-<id>`, and containers `wirespeed-core-source-<id>` and
   `wirespeed-core-target-<id>`.
3. Builds the image, then creates an `--internal` network (no external route)
   and the two clusters. No ports are published to the host.
4. Runs `python3 -m scripts.c2_provider_exit_rehearsal` from a read-only mount of
   the checkout. The rehearsal:
   - bootstraps both clusters;
   - applies migrations 01, 07, 08, 09, 10 and 11 to the source;
   - seeds the synthetic fixture;
   - exports twice and requires byte-identical bundles;
   - restores into the empty target;
   - verifies the target;
   - re-fingerprints the source.
5. Runs `scripts/validate_sovereignty_bundle.py` with no network access, passing
   `--expected-sha256` set to the archive's computed SHA-256.
6. Prints the image's Python and `psql` versions.
7. In a `finally` block that runs on success or failure, removes the created
   containers with their volumes, then the network, then the image.

## Expected results

### Allowed (must succeed)

| Check | Where it is recorded |
| --- | --- |
| Rehearsal passes | stdout JSON with `"code": "C2_PROVIDER_EXIT_PASS"` |
| Independent clusters | `source.system_identifier` differs from `destination.system_identifier` in `core-proof/receipt.json` |
| Target clean before restore | `destination.clean_before_restore: true`, `destination.preflight_public_table_count: 0` |
| Deterministic export | `bundle.byte_deterministic_repeat_export: true` |
| Source unchanged by export | `source.unchanged: true`; `before_fingerprint` equals `after_fingerprint` |
| Owner can read own records after restore | `verification.positive_control_readable` and `verification.reciprocal_positive_readable` |
| History survives | `verification.attention_revision_lineage: true`, `verification.work_lesson_boot_fragment` present |
| Perimeter clean | `verification.perimeter_report` has `evaluation_status` `evaluated`, `perimeter_state` `clean` and `violation_count` 0; `verification.assert_perimeter_closed` is `perimeter OK: perimeter-report/1 evaluated clean with zero findings` |
| Bundle validator | prints `{"archive_sha256": "<this run's checksum>", "code": "OK"}` |
| Final line | `PASS: synthetic C2 rehearsal and bundle validation. Inspect core-proof/receipt.json.` |

### Denied (must be refused)

| Control | Expected |
| --- | --- |
| Another principal's private record after restore | `verification.paired_private_denial` and `verification.reciprocal_private_denial` record that the denial held; the rehearsal fails if either record becomes visible |
| `service_role` direct `SELECT` on memories | `verification.service_role_direct_memories_select: false`; the rehearsal fails if access appears |
| Run from any other commit (try from a `main` checkout) | throws `Check out the exact Core alpha source before running.` before any Docker resource is created |
| Rerun in the same checkout | throws `Use a fresh checkout: core-proof already exists.` before any Docker resource is created |
| Non-empty destination | the rehearsal raises `destination was not clean before rehearsal`. This guard is in the source, but this recipe does not exercise it, because each run creates a new target |

The bundle checksum differs between runs: the fixture uses random identifiers
and timestamps. The validator checks each run's archive against that run's own
checksum. The reference receipt below is the value from one run, not an
expected constant.

Any failure stops the recipe (`$ErrorActionPreference = 'Stop'` plus explicit
exit-code checks). Treat a missing final `PASS` line as a failed run.

## Cleanup

The recipe owns and removes only the resources named with its run id. After it
exits, whether it passed or failed, verify that nothing it owned remains:

```powershell
docker ps -a --filter name=wirespeed-core- --format '{{.Names}}'          # expect no output
docker network ls --filter name=wirespeed-core-proof- --format '{{.Name}}' # expect no output
docker image ls wirespeed-core-proof --format '{{.Tag}}'                  # expect no output
```

Two things are deliberately not removed:

- `core-proof/` in the checkout. It is the run's evidence: the receipt, the
  bundle archive, the archive checksum and the generated Dockerfile. Keep it or
  delete it with `Remove-Item -Recurse core-proof`.
- The pulled base image `postgres:16-bookworm`. Docker shares it with anything
  else on the machine that uses it, so the recipe does not remove it. Run
  `docker image rm postgres:16-bookworm` only if nothing else uses it.

When you are finished, delete the `core-alpha` checkout and `../core-restore.ps1`.

## Reference receipt

This is a sanitized operating observation, recorded on 2026-10-15 by running
this exact recipe. It was not rerun to write this guide.

```json
{
  "verification_date": "2026-10-15",
  "repository": "https://github.com/jryski/sovereign-memory-core",
  "source_revision": "c96b9da749b2d95661973485b2a026897329c8cd",
  "profile": "full-synthetic-v1",
  "runtime": {
    "postgresql": "16.15 (Debian 16.15-1.pgdg12+2)",
    "python": "3.11.2",
    "isolation": "Two new Docker clusters on an internal network, no host-published ports",
    "powershell": "7.6.6"
  },
  "checks": {
    "c2_rehearsal": "pass",
    "bundle_validator": "OK",
    "clean_target": true,
    "independent_clusters": true,
    "source_unchanged": true,
    "byte_deterministic_repeat_export": true,
    "positive_control_readable": true,
    "paired_private_denial": true,
    "reciprocal_positive_readable": true,
    "reciprocal_private_denial": true,
    "service_role_direct_memories_select": false,
    "attention_revision_lineage": true,
    "perimeter_state": "clean",
    "perimeter_violation_count": 0
  },
  "cleanup": "Both runs: new containers, volumes and internal network removed; final recipe removes its unique helper image too",
  "data": "Fabricated example principals and fixture records only",
  "recipe": {
    "file": "core-restore.ps1",
    "sha256": "ebf7359fdb230a141bed4d71942b2e82f89c1b3e096dfc977ab1733df8cfd5aa",
    "host": "PowerShell 7.6.6; Docker Linux containers",
    "exact_recipe_execution": "pass"
  },
  "bundle_sha256": "727ed2ad739a153a761735a27edb98cf6490ac4fcf5921ea7a5099ff9e4b6a47"
}
```

To publish your own receipt, use the same fields. Do not include host names,
user names, absolute paths, container ids or anything outside `core-proof/`.

## Limits

- Not acceptance on live private data. The fixture is fabricated.
- Not reconstruction of a provider's control plane: auth service, storage,
  functions, scheduling and similar services
  ([known limitations](../release/v0.3-alpha-known-limitations.md)).
- Not signed actor attribution. Attribution in the alpha is assertion-grade.
- PostgreSQL 16 only in this recipe. The alpha declares provider-exit support
  for PostgreSQL 15 and 16, but this receipt does not include a PostgreSQL 15
  rerun.
- Not full independent source-fingerprint binding.
- Not a new signed release, and not a byte-for-byte recreation of the
  2026-08-15 release archive. Checksums are not signatures.

## Related

- Continuous evidence for the same rehearsal: [c2-provider-exit.yml](../.github/workflows/c2-provider-exit.yml).
- [Security model](02-security-model.md).
- [Security policy](../SECURITY.md).
