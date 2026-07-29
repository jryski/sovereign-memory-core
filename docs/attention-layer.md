# Attention Event and Context Projection Protocol

## Source-semantic event capture

`memory_created` exists only when the actual eligible memory INSERT trigger records it.

`memory_activated` exists only when the actual `proposed -> active` status transition trigger records it.

The compatibility replay functions are existence-only lookups. Calling them for an older eligible memory with no event returns `NULL`. They never backfill or fabricate an event and never claim a trigger observation that did not occur.

## Identity and revision keys

Every producer follows one canonical rule:

```text
identity_key = hash(contract identity components)
revision_key = hash(identity_key, persisted source_revision)
```

Native events persist:

```text
source_revision = native-revision:1
```

The exact persisted value is the value hashed. Consumers can independently recompute every new producer path from stored fields.

Historical rows from an older protocol may retain their original immutable keys. Upgrade SQL changes producers without rewriting history.

## Revision observation and concurrency

`append_attention_event_revision()`:

1. computes the requested key;
2. takes a transaction-scoped advisory lock for the stable identity;
3. rechecks whether another caller already wrote that revision;
4. locks the current lineage tip;
5. appends exactly one successor;
6. returns the winner to concurrent identical callers.

A changed revision records the current observer context from the runtime envelope. It never copies the predecessor’s actor, credential, or runtime attribution. When a deployment has only a shared runtime credential, metadata labels the attribution as `shared-runtime-assertion`, not proof of a distinct human identity.

## Append-only custody

Events and assignments reject update, delete, and truncate. Runtime roles have SELECT and bounded SECURITY DEFINER APIs only. Trigger writer functions are not executable by runtime roles.

## Character-budget contract

The database guarantees serialized PostgreSQL characters:

```text
char_length(payload::text) <= effective_char_budget
reported rendered_chars = char_length(payload::text)
```

It does not guarantee UTF-8 bytes or model tokens.

The self-reported decimal count is solved as a fixed point:

```text
total = base_serialized_chars + decimal_digits(total)
```

The implementation is bounded and asserts stability. Tests cover digit-width transitions, escaped content, multibyte content, and budgets where one extra digit matters.

## Perimeter

The final assertion proves, for the protected attention and work-memory surface:

- runtime and untrusted roles cannot CREATE in SECURITY DEFINER search-path schemas;
- protected tables have RLS and FORCE RLS;
- table and function owners are expected;
- stale grantees are absent;
- runtime roles have no direct mutation privileges or inherited broad write role;
- trigger-only writers are not executable by runtime roles;
- checked SECURITY DEFINER functions have explicit safe search paths.
