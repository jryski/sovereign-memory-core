#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DATABASE_URL:?DATABASE_URL is required}"

memory_id="$(psql "$DB_URL" -XAtqv ON_ERROR_STOP=1 -c "
  insert into public.memories(
    content,workstream,owner,visibility,source_agent,source_kind,status
  ) values(
    'concurrency fixture','concurrency','example-user','private',
    'example-user-chatgpt','agent','active'
  ) returning id;
")"

event_id="$(psql "$DB_URL" -XAtqv ON_ERROR_STOP=1 -c "
  select id from public.attention_events
  where memory_id='${memory_id}'::uuid and source_event_type='memory_created';
")"

call_sql="select public.append_attention_event_revision(
  '${event_id}'::uuid,
  'concurrent-revision:2',
  clock_timestamp(),
  'other:test:concurrent',
  'concurrency-test',
  '{\"fixture\":true}'::jsonb
);"

tmp1="$(mktemp)"
tmp2="$(mktemp)"
trap 'rm -f "$tmp1" "$tmp2"' EXIT

psql "$DB_URL" -XAtqv ON_ERROR_STOP=1 -c "$call_sql" >"$tmp1" &
pid1=$!
psql "$DB_URL" -XAtqv ON_ERROR_STOP=1 -c "$call_sql" >"$tmp2" &
pid2=$!
wait "$pid1"
wait "$pid2"

id1="$(tail -n1 "$tmp1" | tr -d '[:space:]')"
id2="$(tail -n1 "$tmp2" | tr -d '[:space:]')"
test -n "$id1"
test "$id1" = "$id2"

count="$(psql "$DB_URL" -XAtqv ON_ERROR_STOP=1 -c "
  select count(*) from public.attention_events
  where identity_key=(select identity_key from public.attention_events where id='${event_id}'::uuid)
    and source_revision='concurrent-revision:2';
")"
test "$count" = "1"

echo "concurrent identical replay returned one winner: $id1"
