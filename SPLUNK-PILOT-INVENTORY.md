# Splunk pilot inventory

**Blank read-only template. Not a filled inventory. Not an accepted inventory. Phase 1 is not done.**

This file is an empty template for Phase 1 of the Splunk pilot named in issue #62: deployment inventory and read-only access. It holds no deployment facts. Every value below is a synthetic placeholder (`TBD`, `_not filled_`, or `«fill later»`). Placeholders are not observations.

Primary Users keep any filled inventory outside this blank copy until a later, separate revision says otherwise. This revision does not grant access, change configuration, or accept Phase 1.

Related to #62. This template does not close that issue. Phases after Phase 1 are not started here.

## Reading rules

- A placeholder means the field has not been filled.
- Do not treat this file as evidence that a deployment was inspected.
- Do not put credentials, tokens, live endpoints, or search results in this copy.
- No Splunk configuration change is authorized by this template.

## 1. Deployment type / version

| Field | Value |
|---|---|
| Deployment type | TBD |
| Exact version | _not filled_ |
| Topology | «fill later» |
| License constraints relevant to read-only search | _not filled_ |

## 2. API reachability

| Field | Value |
|---|---|
| API endpoint | TBD |
| TLS posture | _not filled_ |
| Reachability observed | «fill later» |
| Bounded REST search or export proven without admin access | _not filled_ |

No live Splunk access was used to produce this template.

## 3. Authentication class

| Field | Value |
|---|---|
| Authentication class | TBD |
| Read-only search identity identified | _not filled_ |
| Identity scope (indexes and capabilities) | «fill later» |
| Admin or write authority on that identity | _not filled_ |
| Credential material in this file | none |

Record the class only. Do not record secrets.

## 4. Indexes / sourcetypes

| Index | Sourcetype | In approved read-only scope | Notes |
|---|---|---|---|
| TBD | _not filled_ | «fill later» | _not filled_ |

## 5. Retention

| Field | Value |
|---|---|
| Retention per in-scope index | TBD |
| Earliest searchable time observed | _not filled_ |
| Volume | «fill later» |

## 6. Field quality

| Field | Value |
|---|---|
| Stable extracted fields versus search-time only | TBD |
| Known missing or unstable fields | _not filled_ |
| Normalization overlap left unclassified | «fill later» |

Field-level mapping to protocol concepts is outside this Phase 1 template.

## 7. Sensitive-data classification

| Field | Value |
|---|---|
| Classification scheme | TBD |
| Indexes or sourcetypes that may hold sensitive data | _not filled_ |
| Fields that must stay out of canonical memory copies | «fill later» |
| Raw payload handling | _not filled_ |

## 8. Candidate test searches

Slots only. These searches have not been written or run.

| Id | Intent | Index and sourcetype bounds | Time bounds | Search text | Non-sensitive result shape | Run status |
|---|---|---|---|---|---|---|
| TBD | _not filled_ | «fill later» | _not filled_ | «fill later» | _not filled_ | not run |

## Non-claims

- This is a blank read-only template.
- This is not a filled inventory.
- This is not an accepted inventory.
- Phase 1 is not done.
- No read-only identity was created or proven by this file.
- No Splunk configuration was changed.
- Later pilot phases are not started.
