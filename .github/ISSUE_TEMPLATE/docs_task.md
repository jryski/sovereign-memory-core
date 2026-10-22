---
name: Docs task
about: Improve durable documentation or repo narrative
title: ''
labels: type:docs
assignees: ''
---

## Goal

What should the docs clarify?

## Scope

Files or sections likely involved:

## Non-goals

What should this task avoid changing?

## Acceptance

- [ ] Documentation is accurate for current main
- [ ] No private identifiers or sensitive examples
- [ ] Links are valid
- [ ] Validation commands are documented if applicable

## Public-safety review

Issue titles, bodies, and comments are publication surfaces. The changed-file scan does not read them. Pattern matching cannot establish context or attack value. Confirm this issue contains none of the following, or replace them with synthetic placeholders (`example-user`, `example.local`, `you@example.com`, `REDACTED`):

- [ ] No personal, household, employer, client, account, or private-project facts
- [ ] No secrets, credentials, credential references, or rotation details
- [ ] No real deployment identifiers, URLs, hostnames, IP addresses, device names, topology, or local paths
- [ ] No exact private counts, manifests, watermarks, stable digests, custody receipts, or routing records
- [ ] No live schema/RPC inventories, access-control findings, denial paths, or attack-relevant configuration
- [ ] No personal contact or location information
- [ ] No internal coordination transcripts or sequence reconstructions
- [ ] Nothing that materially reduces the effort required to attack a real deployment

## Related

Issues, PRs, docs, or ADRs:
