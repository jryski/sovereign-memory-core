-- Known-broken assertion suite for issue #74.
--
-- This file is intentionally inert. bool_and ignores NULL, and
-- FILTER (WHERE NOT pass) counts zero failures, so the script exits 0.
-- A passing run of this file is not evidence. The checker must reject it.
-- Do not rewrite these aggregates; the fail-closed matrix discriminates
-- this exact shape.

select bool_and(v)::text || '|' || (count(*) filter (where not v))::text as inert
from (values (true), (null::boolean), (true)) as t(v);
