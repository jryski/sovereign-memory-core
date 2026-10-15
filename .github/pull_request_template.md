## Summary

## Issues addressed

## Files changed

## Validation

- [ ] `git diff --check`
- [ ] Markdown/link checks if available
- [ ] SQL validation if SQL changed
- [ ] Python syntax/tests if Python changed
- [ ] Shell syntax if shell changed
- [ ] `bash scripts/public_safety_scan.sh` (changed-file scan; see docs/public-safety.md)

## Public-safety check

The file scan is necessary and not sufficient. Pattern matching cannot establish context or attack value. This pull request, its reviews, release notes, workflow logs, and uploaded artifacts are publication surfaces.

- [ ] No personal, household, employer, client, account, or private-project facts
- [ ] No secrets, credentials, credential references, or rotation details
- [ ] No real deployment identifiers, URLs, hostnames, IP addresses, device names, topology, or local paths
- [ ] No exact private counts, manifests, watermarks, stable digests, custody receipts, or routing records
- [ ] No live schema/RPC inventories, access-control findings, denial paths, or attack-relevant configuration
- [ ] No personal contact or location information
- [ ] No internal coordination transcripts or sequence reconstructions
- [ ] Nothing that materially reduces the effort required to attack a real deployment
- [ ] Automated scan findings are resolved, or any intentional hit is documented

## Supabase / live-state note

- [ ] No live Supabase mutation
- [ ] If live mutation occurred, exact user approval is linked/described

## Conformance impact

- [ ] No conformance claims changed
- [ ] Conformance gap audit updated if normative requirements changed

## Remaining follow-ups
