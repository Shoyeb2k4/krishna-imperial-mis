-- Phase 8 Slice 2 — D-186 probe (D-313 measurement contract).
--
-- Defines pg_temp.d186_probe(label, principal, query, runs), a TEMPORARY function: it
-- lives in this session's temp schema, is created inside the batch's transaction, and
-- disappears with the ROLLBACK that ends every batch. It is not a schema change and it
-- is invisible to every other session. The batch is:
--
--   begin;
--   set local track_functions = 'all';                  -- this transaction only
--   <this file>
--   select pg_temp.d186_probe('<id>', '<uuid or empty>', '<sql>', 5);   -- per workload
--   select current_setting('bench.out')::jsonb;
--   rollback;
--
-- Each call appends one object to `bench.out`. Nothing is written to any table and no
-- server-wide setting is touched: `set local` and `set_config(.., true)` end with the
-- transaction.
--
-- The principal is emulated exactly as PostgREST does it: `set local role authenticated`
-- plus a `request.jwt.claims` carrying the user id, which is what `auth.uid()` reads.
-- RLS and every SECURITY DEFINER predicate therefore run as they do for that person.
--
-- Per workload it records:
--   * one discarded warm-up, then `bench.runs` EXPLAIN (ANALYZE, BUFFERS) executions;
--   * the execution and planning time of each measured run;
--   * the last run's plan, flattened to one entry per node;
--   * one further plain execution, timed with clock_timestamp(), and the exact number of
--     calls it made to each tracked function (pg_stat_xact_user_functions, before/after).
create function pg_temp.d186_probe(p_label text, p_principal text, p_query text, p_runs int)
returns void language plpgsql as $probe$
declare
  q        text := p_query;
  runs     int  := p_runs;
  who      text := coalesce(p_principal, '');
  plan     json;
  ex       numeric[] := '{}';
  top      jsonb;
  nodes    jsonb;
  c0       jsonb;
  c1       jsonb;
  t0       timestamptz;
  plain_ms numeric;
  i        int;
  result   jsonb;
begin
  if who = '' then
    execute 'set local role none';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', who, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;

  execute 'explain (analyze, buffers, format json) ' || q into plan;   -- warm-up, discarded
  for i in 1 .. runs loop
    execute 'explain (analyze, buffers, format json) ' || q into plan;
    ex := ex || (plan -> 0 ->> 'Execution Time')::numeric;
  end loop;

  top := (plan -> 0 -> 'Plan')::jsonb;
  with recursive n(node, depth) as (
    select top, 0
    union all
    select c, n.depth + 1 from n, jsonb_array_elements(n.node -> 'Plans') c
  )
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'd',     depth,
           'type',  node ->> 'Node Type',
           'rel',   node ->> 'Relation Name',
           'index', node ->> 'Index Name',
           'sub',   node ->> 'Subplan Name',
           'rows',  node -> 'Actual Rows',
           'loops', node -> 'Actual Loops',
           'ms',    node -> 'Actual Total Time',
           'hit',   node -> 'Shared Hit Blocks',
           'read',  node -> 'Shared Read Blocks',
           'cond',  coalesce(node ->> 'Index Cond', node ->> 'Hash Cond'),
           'filter', node ->> 'Filter',
           'removed', node -> 'Rows Removed by Filter')))
    into nodes from n;

  select coalesce(jsonb_object_agg(funcname, calls), '{}') into c0
    from pg_stat_xact_user_functions;
  t0 := clock_timestamp();
  execute q;
  plain_ms := round((extract(epoch from clock_timestamp() - t0) * 1000)::numeric, 3);
  select coalesce(jsonb_object_agg(f.funcname,
           f.calls - coalesce((c0 ->> f.funcname)::bigint, 0)), '{}') into c1
    from pg_stat_xact_user_functions f
   where f.calls - coalesce((c0 ->> f.funcname)::bigint, 0) > 0;

  result := jsonb_build_object(
    'label',       p_label,
    'principal',   nullif(who, ''),
    'runs',        runs,
    'exec_ms',     to_jsonb(ex),
    'median_ms',   (select percentile_cont(0.5) within group (order by x) from unnest(ex) x),
    'min_ms',      (select min(x) from unnest(ex) x),
    'max_ms',      (select max(x) from unnest(ex) x),
    'planning_ms', (plan -> 0 ->> 'Planning Time')::numeric,
    'plain_ms',    plain_ms,
    'rows',        top -> 'Actual Rows',
    'shared_hit',  top -> 'Shared Hit Blocks',
    'shared_read', top -> 'Shared Read Blocks',
    'calls',       c1,
    'plan',        nodes);

  perform set_config('bench.out',
    (coalesce(nullif(current_setting('bench.out', true), ''), '[]')::jsonb
       || jsonb_build_array(result))::text, true);

  -- Back to the session role, so the next workload starts from the same place.
  execute 'set local role none';
end
$probe$;
