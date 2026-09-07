-- Phase 5 Slice 4 · D-172 corrective — a revenue row's reporting generation never moved.
--
-- `change_seq` is the project's one observable mutation generation: a single sequence,
-- `app.global_change_seq`, stamped onto every synced row so a client can ask "what changed
-- since?" (ARCHITECTURE §5.2). Seventeen tables in `public` carry the column and stamp it
-- on UPDATE through `app.touch_row`. Two carried the column and stamped nothing:
-- `revenue_entries` and `revenue_attachments`, both added in Phase 4.
--
-- The column's `default nextval('app.global_change_seq')` fires on INSERT, so the value
-- looked right and was frozen for ever afterwards. Proven against this database through the
-- real RPCs, one transaction each:
--
--     after create           change_seq 12945   row_version 1   2026-06-15   voided false
--     after amount edit      change_seq 12945   row_version 2   2026-06-15   voided false
--     after date correction  change_seq 12945   row_version 3   2026-07-10   voided false
--     after void             change_seq 12945   row_version 4   2026-07-10   voided TRUE
--
-- An edit, a correction that moved the entry from June to July, and a void — all invisible
-- to any `change_seq > watermark` delta. `row_version` advanced throughout, because
-- `revenue_update` and `revenue_void` bump it by hand; that manual bump is what hid the
-- missing trigger for a whole phase.
--
-- The expense side was audited the same way and is sound: every reporting-relevant mutation
-- advances `expenses.change_seq`, including an accrual movement that changes no header
-- field (13004 -> 13009) and a void (13009 -> 13014).
--
-- ── Why not simply attach `app.touch_row` ────────────────────────────────────
--
-- Because it also does `new.row_version := old.row_version + 1`, and the revenue RPCs
-- already do that themselves. Attaching it would double-increment the optimistic-concurrency
-- token on every revenue mutation, so every client holding a version would be refused
-- KM003 on its next correction. The narrowest fix is a trigger that stamps the generation
-- and touches nothing else: no row_version, no updated_at, no behaviour a client can see.

create or replace function app.stamp_change_seq()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.change_seq := nextval('app.global_change_seq');
  return new;
end;
$$;

comment on function app.stamp_change_seq() is
  'Advances only the observable mutation generation. For tables whose RPCs own row_version '
  'and updated_at themselves, where app.touch_row would double-increment the concurrency '
  'token (D-021). Every table carrying change_seq must stamp it on UPDATE somehow, and an '
  'invariant below asserts that over the catalogue rather than over a remembered list.';

revoke all on function app.stamp_change_seq() from public, anon, authenticated;

drop trigger if exists revenue_entries_change_seq on public.revenue_entries;
create trigger revenue_entries_change_seq
  before update on public.revenue_entries
  for each row execute function app.stamp_change_seq();

-- Same omission, same one-line fix. Attachments are outside the reporting path today
-- (attaching is not editing — D-150), and a column whose value is meaningless is a trap for
-- whoever first tries to synchronise them.
drop trigger if exists revenue_attachments_change_seq on public.revenue_attachments;
create trigger revenue_attachments_change_seq
  before update on public.revenue_attachments
  for each row execute function app.stamp_change_seq();

-- ── The invariant, stated generally ──────────────────────────────────────────
-- Every table in `public` carrying `change_seq` advances it on UPDATE. Searched over the
-- catalogue with no exemption list, so the next table to carry the column cannot be added
-- without one — which is exactly how these two were (D-068, D-071, D-077).
do $inv$
declare v_bad text;
begin
  with carrying as (
    select c.oid, c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join information_schema.columns col
        on col.table_schema = 'public'
       and col.table_name = c.relname
       and col.column_name = 'change_seq'
     where n.nspname = 'public' and c.relkind = 'r'
  )
  select string_agg(t.relname, ', ' order by t.relname) into v_bad
    from carrying t
   where not exists (
     select 1 from pg_trigger tg
      where tg.tgrelid = t.oid
        and not tg.tgisinternal
        and (tg.tgtype & 2) <> 0     -- BEFORE
        and (tg.tgtype & 16) <> 0    -- UPDATE
        and pg_get_functiondef(tg.tgfoid) like '%global_change_seq%');
  if v_bad is not null then
    raise exception
      'these tables carry change_seq and never advance it on UPDATE, so every mutation '
      'after the insert is invisible to a delta pull: %', v_bad;
  end if;
end $inv$;

-- And the fix must not have reintroduced the double-increment it exists to avoid.
do $inv$
declare v_bad text;
begin
  select string_agg(c.relname, ', ') into v_bad
    from pg_trigger tg
    join pg_class c on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and not tg.tgisinternal
     and c.relname in ('revenue_entries', 'revenue_attachments')
     and tg.tgfoid = 'app.touch_row'::regproc;
  if v_bad is not null then
    raise exception
      'app.touch_row is attached to %, whose RPCs bump row_version themselves; every '
      'correction would now be refused as a version conflict', v_bad;
  end if;
end $inv$;

-- Prove it moves, rather than asserting that a trigger exists. A trigger that stamped the
-- wrong column, or stamped nothing, would satisfy every check above.
do $inv$
declare
  v_id uuid;
  v_before bigint;
  v_after bigint;
begin
  select id, change_seq into v_id, v_before
    from public.revenue_entries order by created_at desc limit 1;
  if v_id is null then
    raise notice 'no revenue row to probe; the invariant is asserted by the live suite';
    return;
  end if;
  -- A no-op update: nothing about the document changes, and the generation must still move,
  -- because "this document changed" is exactly what a delta needs to observe.
  update public.revenue_entries set notes = notes where id = v_id;
  select change_seq into v_after from public.revenue_entries where id = v_id;
  if v_after <= v_before then
    raise exception
      'revenue_entries.change_seq did not advance on update: % -> %', v_before, v_after;
  end if;
  raise notice 'revenue generation advances: % -> %', v_before, v_after;
end $inv$;