# SECURITY DEFINER and authority-adjacent function inventory

Migration `sql/10_security_definer_hardening.sql` is the reviewed fix-forward
inventory for issue #57. The inventory is exact for the package installed by
`sql/01_core.sql`, `sql/07_work_lessons.sql`, `sql/08_attention_events.sql`, and
`sql/09_perimeter_refresh.sql`: 28 `SECURITY DEFINER` routines and 20 helpers
entered by those routines or by their trigger/write authority chain.

Every listed routine has `SET search_path TO 'pg_catalog', 'pg_temp'`.
`pg_temp` is explicit, occurs once, and is last. Protected application
relations, views, `%ROWTYPE` types, and cross-function calls are schema-qualified
with `public.`; extension calls are qualified with `extensions.`. PostgreSQL
built-ins, operators, and catalog objects resolve through the trusted
`pg_catalog` path. No routine retains an unqualified application object.

## SECURITY DEFINER routines (28)

| Function identity | Search path | Qualification disposition |
|---|---|---|
| `public.accept_work_lesson(p_id uuid, p_accepted_by text, p_authority_ref text)` | `pg_catalog, pg_temp` | Application relations/type and helper boundary qualified. |
| `public.append_attention_event_revision(p_predecessor_event_id uuid, p_source_revision text, p_occurred_at timestamp with time zone, p_source_evidence_ref text, p_observation_method text, p_metadata jsonb)` | `pg_catalog, pg_temp` | Application relations/types and helper boundary qualified. |
| `public.append_work_lesson_evidence(p_lesson_id uuid, p_evidence_kind text, p_locator text, p_source_authority text, p_actor text, p_resolution_state text, p_integrity_hash text)` | `pg_catalog, pg_temp` | Application relations and helper boundary qualified. |
| `public.assert_perimeter_closed()` | `pg_catalog, pg_temp` | Control relations, catalog relations, information-schema relation, and helper boundaries qualified; audits the complete installed public definer set. |
| `public.attention_boot_projection_v2(p_viewer text, p_char_budget integer, p_summary_chars integer)` | `pg_catalog, pg_temp` | Application view and helper boundaries qualified. |
| `public.attention_budget_conformance_v2(p_viewer text, p_char_budget integer, p_summary_chars integer)` | `pg_catalog, pg_temp` | Projection helper boundary qualified. |
| `public.bless_doc(p_path text, p_note text)` | `pg_catalog, pg_temp` | Application relation and helper boundary qualified. |
| `public.capture_memory_activation_after_update()` | `pg_catalog, pg_temp` | Application relations and helper boundaries qualified. |
| `public.capture_memory_attention_after_insert()` | `pg_catalog, pg_temp` | Application relations and helper boundaries qualified. |
| `public.channel_complete(p_seq bigint, p_status text)` | `pg_catalog, pg_temp` | Application relation qualified. |
| `public.channel_send(p_from_agent text, p_to_principal text, p_kind text, p_subject text, p_body text, p_due_at timestamp with time zone, p_add_to_calendar boolean, p_re_seq bigint)` | `pg_catalog, pg_temp` | Application relations qualified. |
| `public.correct_work_lesson_evidence(p_evidence_id uuid, p_evidence_kind text, p_locator text, p_source_authority text, p_actor text, p_correction_reason text, p_resolution_state text, p_integrity_hash text)` | `pg_catalog, pg_temp` | Application relations/type and helper boundary qualified. |
| `public.current_doc_hash(p_path text)` | `pg_catalog, pg_temp` | Application relation and extension digest boundary qualified. |
| `public.hot_touch(p_topic_key text, p_memory_id uuid, p_summary text, p_workstream text)` | `pg_catalog, pg_temp` | All durable target/source relations qualified. |
| `public.promote_memory(p_id uuid, p_note text)` | `pg_catalog, pg_temp` | Overload call qualified. |
| `public.promote_memory(p_id uuid, p_note text, p_actor text)` | `pg_catalog, pg_temp` | Application relation qualified. |
| `public.propose_lesson_supersession(p_predecessor_id uuid, p_claim text, p_detail text, p_evidence_kind text, p_evidence_locator text, p_source_authority text, p_created_by text, p_resolution_state text, p_integrity_hash text)` | `pg_catalog, pg_temp` | Application relations/type and helper boundary qualified. |
| `public.propose_work_lesson(p_kind text, p_claim text, p_detail text, p_evidence_kind text, p_evidence_locator text, p_source_authority text, p_created_by text, p_resolution_state text, p_integrity_hash text)` | `pg_catalog, pg_temp` | Application relations and helper boundary qualified. |
| `public.record_native_memory_activation(p_memory_id uuid, p_actor text)` | `pg_catalog, pg_temp` | Application relation qualified. |
| `public.record_native_memory_attention(p_memory_id uuid)` | `pg_catalog, pg_temp` | Application relation qualified. |
| `public.reject_work_lesson(p_id uuid, p_actor text, p_authority_ref text)` | `pg_catalog, pg_temp` | Application relations qualified. |
| `public.remediate_perimeter_acl()` | `pg_catalog, pg_temp` | Control/helper boundaries and catalog relations qualified; dynamic SQL emits schema-qualified application identities. |
| `public.remember(p_content text, p_workstream text, p_topic_key text, p_source_agent text, p_owner text, p_summary text, p_tags text[], p_visibility text, p_due_date timestamp with time zone)` | `pg_catalog, pg_temp` | Application relations and helper boundary qualified. |
| `public.session_boot(p_viewer text)` | `pg_catalog, pg_temp` | Application relations/views and helper boundaries qualified. |
| `public.supersede_memory(p_old_id uuid, p_new_content text, p_source_agent text, p_summary text, p_tags text[], p_due_date timestamp with time zone)` | `pg_catalog, pg_temp` | Application relations/type qualified. |
| `public.supersede_wiki(p_path text, p_new_content text, p_source_agent text, p_title text, p_frontmatter jsonb)` | `pg_catalog, pg_temp` | Application relations/type qualified. |
| `public.verify_doc_integrity(p_path text)` | `pg_catalog, pg_temp` | Application relation and helper boundary qualified. |
| `public.work_lessons_boot_fragment()` | `pg_catalog, pg_temp` | Application relations/views qualified. |

## Authority-adjacent helpers (20)

| Function identity | Search path | Qualification disposition |
|---|---|---|
| `public.attention_fixed_point_chars(p_base_chars integer)` | `pg_catalog, pg_temp` | Built-ins only; trusted path is closed. |
| `public.attention_hash_parts(VARIADIC p_parts text[])` | `pg_catalog, pg_temp` | Extension digest boundary qualified; built-ins trusted. |
| `public.attention_set_rendered_chars(p_payload jsonb)` | `pg_catalog, pg_temp` | Helper call qualified; built-ins trusted. |
| `public.attention_summary_at_word_boundary(p_text text, p_max_chars integer)` | `pg_catalog, pg_temp` | Built-ins only; trusted path is closed. |
| `public.attention_workstream_key(p_workstream text)` | `pg_catalog, pg_temp` | Built-ins only; trusted path is closed. |
| `public.audit_status_changes()` | `pg_catalog, pg_temp` | Durable audit target qualified. |
| `public.guard_attention_append_only()` | `pg_catalog, pg_temp` | No application lookup; trusted path is closed. |
| `public.guard_attention_truncate()` | `pg_catalog, pg_temp` | No application lookup; trusted path is closed. |
| `public.guard_hard_delete()` | `pg_catalog, pg_temp` | Durable audit target qualified. |
| `public.guard_work_lesson_custody_write_path()` | `pg_catalog, pg_temp` | No application lookup; trusted path is closed. |
| `public.guard_work_lesson_truncate()` | `pg_catalog, pg_temp` | No application lookup; trusted path is closed. |
| `public.guard_work_lessons_write_path()` | `pg_catalog, pg_temp` | No application lookup; trusted path is closed. |
| `public.is_canonical_work_lesson_locator(p_kind text, p_locator text)` | `pg_catalog, pg_temp` | Built-ins only; trusted path is closed. |
| `public.perimeter_acl_violations()` | `pg_catalog, pg_temp` | Control relations, catalog relations, and helper boundaries qualified. |
| `public.perimeter_authority_functions()` | `pg_catalog, pg_temp` | Registry and catalog relations qualified. |
| `public.perimeter_policy_roles(p_kind text)` | `pg_catalog, pg_temp` | Durable policy relation qualified. |
| `public.perimeter_protected_schemas()` | `pg_catalog, pg_temp` | Registry and catalog relations qualified. |
| `public.perimeter_setting_roles(p_setting text)` | `pg_catalog, pg_temp` | Durable policy relation qualified. |
| `public.set_updated_at()` | `pg_catalog, pg_temp` | Built-ins only; trusted path is closed. |
| `public.validate_attention_event_revision_lineage()` | `pg_catalog, pg_temp` | Application relation/type qualified. |

## Enforcement

`tests/10_security_definer_temp_shadow.sql` compares the installed 28-routine
`SECURITY DEFINER` identity set exactly, requires the canonical path on every
member, and proves that omitted, misordered, and untrusted paths fail the
perimeter assertion. Behavioral probes then demonstrate that temporary shadow
copies of perimeter control tables cannot hide real ACL drift and temporary
copies of the `hot_touch` relation chain cannot redirect a privileged durable
write.
