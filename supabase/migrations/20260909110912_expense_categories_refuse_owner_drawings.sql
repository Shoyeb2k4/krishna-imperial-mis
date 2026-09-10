-- Server migration ledger: 20260909110912  expense_categories_refuse_owner_drawings
--
-- Phase 5 OA-1 section 25 · a structural guard against owner movements being booked as
-- operating expenses.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- What the audit found, stated precisely so this is not mistaken for a defect fix
-- ═════════════════════════════════════════════════════════════════════════════
--
-- An expense document carries **no transaction-type discriminator**, and
-- `expense_categories.nature` — four values, CHECK-constrained, defaulting to
-- `operating` — is **read by nothing**: no policy, no view, no RPC, no reporting query.
-- It is a label.
--
-- So nothing today structurally prevents an administrator creating an expense category
-- called "Owner Withdrawal" and an operator booking Rs 50,000 into it, which would flow
-- straight through `expense_period_contributions` and reduce Operating Profit.
--
-- **No such category exists**, on this project or in the seed, and no expense has ever
-- been misclassified this way. This is a guard against a reachable mistake, not a fix for
-- one that has happened — and calling the absence of a newly discovered feature an old
-- defect would be wrong.
--
-- ═════════════════════════════════════════════════════════════════════════════
-- Why this shape, and what was rejected
-- ═════════════════════════════════════════════════════════════════════════════
--
-- **Rejected: a fifth `nature` value.** Adding `owner_drawings` to the CHECK would create
-- a fifth instance of the family this log keeps recording (D-068, D-071, D-077, D-103,
-- D-116) unless something evaluated it — and if something did, it would mean the expense
-- engine had acquired a concept of owner movements, which is exactly what OA-1 says it
-- must not. Owner movements belong to the Owner Ledger.
--
-- **Rejected: documentation.** A rule that exists only in prose is what section 25 calls
-- "not a control", and it is right.
--
-- **Chosen: a trigger that refuses the category at the point of creation or rename.** It
-- evaluates on every write, it fires before anything is booked, and it names the Owner
-- Ledger in the refusal so the person meets the right workflow rather than a wall.
--
-- The largest part of the guard is not this trigger at all: it is that the correct place
-- to record a withdrawal now exists and is easier to reach than the wrong one. This closes
-- the accidental case that remains.
--
-- ── On false positives ───────────────────────────────────────────────────────
--
-- The name test is deliberately narrow. "Drawings" alone is **not** refused — a hotel's
-- building expenses may legitimately involve architectural drawings — so the pattern
-- requires an owner, partner or proprietor qualifier. What is refused is a name that
-- could only mean an owner movement.

create or replace function app.refuse_owner_drawings_expense_category()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_name text;
  v_code text;
begin
  -- Normalise to single-spaced lower-case words, padded, so a word test is a word test:
  -- "Owner's Drawings", "OWNER-DRAWINGS" and "owner drawings" are one name.
  v_name := ' ' || trim(regexp_replace(lower(coalesce(new.name, '')),
                                       '[^a-z0-9]+', ' ', 'g')) || ' ';
  v_code := upper(trim(coalesce(new.code, '')));

  if v_code in ('OWNER_WITHDRAWAL', 'OWNER_WITHDRAWALS', 'OWNER_DRAWINGS',
                'OWNER_DRAWING', 'PARTNER_DRAWINGS', 'PROPRIETOR_DRAWINGS',
                'OWNER_NC', 'OWNER_SETTLEMENT')
     -- an owner / partner / proprietor, and then a drawing or a withdrawal
     or v_name ~ '(owner|owners|partner|partners|proprietor|proprietors)[a-z0-9 ]{0,20}(withdrawal|withdrawals|drawing|drawings)'
     -- the same, and then a settlement
     or v_name ~ '(owner|owners|partner|partners|proprietor|proprietors)[a-z0-9 ]{0,20}(settlement|settlements)'
     -- an owner and a non-chargeable bill, in either wording
     or v_name ~ '(owner|owners|partner|partners|proprietor|proprietors)[a-z0-9 ]{0,20} nc '
     or v_name like '% non chargeable %'
     or v_name like '% noncharge%'
  then
    perform app.refuse('KM032', 'owner_movement_is_not_an_expense',
      'Money drawn by an owner, and food they or their family consume, are not business expenses — they belong to the Owner Ledger, where they are recorded against that owner''s account. Recording them here would reduce Operating Profit for something the business did not spend.',
      jsonb_build_object('code', new.code, 'name', new.name));
  end if;

  return new;
end;
$$;

comment on function app.refuse_owner_drawings_expense_category() is
  'Refuses an expense category whose code or name could only mean an owner movement (OA-1 section 25). An owner withdrawal or a non-chargeable bill belongs to the Owner Ledger and must never reduce Operating Profit.';

revoke all on function app.refuse_owner_drawings_expense_category()
  from public, anon, authenticated;

drop trigger if exists trg_expense_category_not_owner_drawings on public.expense_categories;
create trigger trg_expense_category_not_owner_drawings
  before insert or update on public.expense_categories
  for each row execute function app.refuse_owner_drawings_expense_category();

-- ═════════════════════════════════════════════════════════════════════════════
-- The guard is proven to fire, at deploy time, against real rows
-- ═════════════════════════════════════════════════════════════════════════════
--
-- A trigger that exists is not a control; a trigger that has been seen to refuse is. This
-- probe inserts a category the guard must reject, requires the rejection, and rolls back
-- — so the assertion runs against the schema that is actually being deployed rather than
-- against a reading of it.
--
-- It also asserts the **other** direction, which is the half that is easy to skip: an
-- ordinary category still inserts. A guard that refused everything would satisfy the
-- first assertion perfectly and would have broken master administration entirely.

do $$
declare
  v_section  record;
  v_refused  boolean := false;
  v_state    text;
  v_msg      text;
begin
  select s.id, s.org_id, s.business_unit_id, s.department_id
    into v_section
    from public.sections s
   where s.archived_at is null
   limit 1;

  if v_section.id is null then
    -- A schema with no hierarchy yet. The trigger's existence is asserted below either
    -- way; there is simply nothing to probe it against, and inventing a section to probe
    -- with would leave master data this migration had no business creating.
    raise notice 'no section available to probe the owner-drawings guard against';
  else
    -- ── The refusal, and it must be THIS guard's refusal ────────────────────
    --
    -- `when sqlstate 'KM032'` rather than `when others`, and that distinction is the
    -- whole value of the probe. The first run of this block caught `when others` and
    -- reported the guard proven — while **both** inserts were in fact failing with
    -- `column "created_by" does not exist`, because this table has no such column. The
    -- negative probe was passing for a reason that had nothing to do with the rule.
    --
    -- It was caught only by the positive control below, which is the assertion that is
    -- easiest to leave out. That is the fourth or fifth time this project has found a
    -- check passing for the wrong reason (D-071, D-074, D-094, D-139, D-180), and it is
    -- recorded here because the fix is general: a probe must assert *which* failure it
    -- got, not merely that one happened.
    begin
      insert into public.expense_categories
        (id, org_id, business_unit_id, department_id, section_id, code, name)
      values (extensions.gen_random_uuid(), v_section.org_id, v_section.business_unit_id,
              v_section.department_id, v_section.id,
              'OA1_PROBE_REFUSED', 'Owner Withdrawal');
    exception
      when sqlstate 'KM032' then
        v_refused := true;
      when others then
        get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
        raise exception
          'the owner-drawings probe failed for an unrelated reason (% / %). A negative '
          'probe that fails for the wrong reason proves nothing about the guard',
          v_state, v_msg;
    end;

    if not v_refused then
      raise exception
        'the owner-drawings guard did not refuse a category named "Owner Withdrawal". '
        'A rule that cannot fail is not a control (OA-1 section 25)';
    end if;

    -- ── And the positive control: an ordinary category still inserts ────────
    --
    -- A guard that refused everything would satisfy the assertion above perfectly and
    -- would have broken master administration entirely. "Kitchen Drawings Board" is
    -- deliberately chosen: it contains the word *drawings*, which the guard must not
    -- refuse without an owner, partner or proprietor qualifier.
    begin
      insert into public.expense_categories
        (id, org_id, business_unit_id, department_id, section_id, code, name)
      values (extensions.gen_random_uuid(), v_section.org_id, v_section.business_unit_id,
              v_section.department_id, v_section.id,
              'OA1_PROBE_ALLOWED', 'Kitchen Drawings Board');
      -- Remove the probe row. This is master data nobody asked for, and it goes in the
      -- same block that created it rather than being left for a cleanup nobody runs.
      delete from public.expense_categories where code = 'OA1_PROBE_ALLOWED';
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
      raise exception
        'the owner-drawings guard refused an ordinary category (% / %). A guard that '
        'refuses everything satisfies its own negative test and has broken master '
        'administration', v_state, v_msg;
    end;
  end if;
end $$;

-- And the trigger is attached, asserted separately so a future `create or replace` of the
-- function that forgot the trigger would be caught.
do $$
begin
  if not exists (
    select 1 from pg_trigger tg
      join pg_class c on c.oid = tg.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_proc p on p.oid = tg.tgfoid
     where n.nspname = 'public' and c.relname = 'expense_categories'
       and p.proname = 'refuse_owner_drawings_expense_category'
       and not tg.tgisinternal) then
    raise exception
      'the owner-drawings guard is not attached to expense_categories';
  end if;
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- The Revenue side needs no trigger, and here is why that is not an omission
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Section 26 requires that owner NC never enters ordinary canonical Revenue. It cannot,
-- and the reason is structural rather than guarded: the Owner Ledger writes to
-- `owner_ledger_entries` and to nothing else, `revenue_period_contributions` is a view
-- over accepted revenue components, and there is no path from one to the other. No
-- revenue category is added, no tax rule is touched, and the five conditional dimensions
-- are unchanged.
--
-- What *would* be a defect is an NC bill typed into the Restaurant revenue screen, and no
-- database trigger can tell that from a real sale — the amounts and the category are
-- identical. That is an operator-workflow question, answered by Scenario A (paid revenue
-- entered separately, NC entered in the Owner Ledger) and, when Petpooja's actual
-- behaviour is confirmed, by an explicit reconciliation workflow. It is recorded as an
-- operational question rather than pretended away with a rule that cannot see it.
--
-- The non-interference property itself is asserted where it can be: host tests that
-- record owner movements and compare the expense and revenue contribution totals before
-- and after, byte for byte.
