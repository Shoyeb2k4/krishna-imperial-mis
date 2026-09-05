-- Revenue records how its current business date was established
--
-- Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.2 · pre-Slice-11 corrective
--
-- **An approved V1 product decision**, settling the disagreement the previous corrective
-- raised and deliberately did not decide. `expenses.business_date_source` has existed
-- since Phase 3 (D-019); `revenue_entries` had nothing, spec §8.0 enumerates a revenue
-- entry's fields without it, and spec §9 says the record notes how its date was arrived
-- at. The project lead has resolved it in favour of §9: **revenue carries provenance**.
--
-- The reason is reporting. Revenue feeds Net Sales, which feeds Operating Profit, and the
-- period a sale lands in is decided by its business date. Whether that trading day was
-- derived by the cut-off rule or moved by a person afterwards is a durable financial fact
-- about the row, and answering it should not require reconstructing an audit sequence.
--
-- ## Two values, not three
--
-- `derived` and `corrected`. Expense also has `manual` — a date the operator chose while
-- *recording* the document — and revenue has no such path: the entry surfaces show the
-- trading day and do not offer to change it, and `revenue_create` takes no provenance
-- argument. Admitting a value nothing can produce would be a column that lies about what
-- the system can do. A third value later is a migration and a decision, taken deliberately.
--
-- ## The client never chooses it
--
-- `revenue_create` has no provenance parameter and sets `derived` itself; `revenue_update`
-- writes `corrected` only on the branch where it has already established, from canonical
-- state, that the date moved. There is no shape of request that lets a caller assert its
-- own provenance, which is the same rule the expense engine follows and the reason the
-- column can be trusted.
--
-- ## Backfill: derived, and nothing cleverer
--
-- The column defaults to `derived`, so every existing row gets it. Nothing infers a past
-- correction from `updated_at`, `row_version`, notes or a date comparison — none of those
-- is evidence, and inventing provenance is worse than not having it.
--
-- There *is* exact canonical evidence for two rows: `audit_logs` holds two
-- `business_date_corrected` actions from the corrective that introduced them. Both belong
-- to **voided development fixtures**, and no open revenue entry on this project has ever
-- been corrected. Backfilling from the audit trail would be machinery written to move two
-- voided test rows, so it is deliberately not written — and this paragraph is the record
-- of that being a decision rather than an oversight.
--
-- ## What this is not
--
-- It does not replace the audit trail. `business_date_corrected` still carries the old
-- date, the new date, the reason, the actor, the server timestamp and the mutation id;
-- that is the historical sequence. This column answers one question about the row as it
-- stands now. The two are not collapsed, and Phase 5 may read the provenance but must not
-- let it alter an amount: aggregation stays keyed on the business date and the
-- contribution model, exactly as before.

alter table public.revenue_entries
  add column if not exists business_date_source text not null default 'derived';

alter table public.revenue_entries
  drop constraint if exists revenue_entries_business_date_source;
alter table public.revenue_entries
  add constraint revenue_entries_business_date_source
  check (business_date_source in ('derived', 'corrected'));

comment on column public.revenue_entries.business_date_source is
  'How the CURRENT business date was established: derived by the unit cut-off rule, or '
  'corrected afterwards by a privileged user (D-019, spec §9). The audit trail remains '
  'the historical sequence; this is the row''s present-state provenance.';

-- ── The projection carries it, so a client never has to infer it ─────────────
--
-- Appended at the end of the select list, which is the only place `create or replace
-- view` permits a new column. The view keeps its `security_barrier` and its own
-- predicate; nothing about who may read it changes.
create or replace view public.revenue_document
with (security_barrier = true) as
select e.id, e.org_id, e.txn_number, e.financial_year,
       e.business_unit_id, e.revenue_category_id, e.business_date, e.pnl_period_key,
       e.entry_kind, e.source_reference, e.notes,
       e.created_by, e.created_at, e.updated_at,
       e.voided_at, e.void_reason, e.row_version, e.change_seq,
       coalesce(t.gross_minor, 0)::bigint as gross_amount_minor,
       coalesce(t.tax_minor, 0)::bigint   as tax_amount_minor,
       coalesce(t.net_minor, 0)::bigint   as net_amount_minor,
       coalesce(t.component_count, 0)     as component_count,
       e.business_date_source
  from public.revenue_entries e
  left join lateral (
    select sum(c.gross_amount_minor) as gross_minor,
           sum(c.tax_amount_minor)   as tax_minor,
           sum(c.net_amount_minor)   as net_minor,
           count(*)                  as component_count
      from public.revenue_components c
     where c.revenue_entry_id = e.id) t on true
 where e.org_id = public.current_org_id()
   and public.has_capability('revenue.view', e.business_unit_id);

-- ── Create: the server states `derived`, and returns it ─────────────────────
--
-- Restated with two lines different: the insert names the column explicitly rather than
-- leaning on the default, so a reader of the create path sees who decides it; and the
-- acceptance payload carries it, so reconciliation writes the server's answer instead of
-- assuming the two sides agree on a constant.
create or replace function public.revenue_create(
  p_id uuid,
  p_business_unit_id uuid,
  p_revenue_category_id uuid,
  p_business_date date,
  p_components jsonb,
  p_entry_kind text default 'daily_summary',
  p_source_reference text default null,
  p_notes text default null,
  p_captured_at timestamptz default null,
  p_mutation_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_replay jsonb; v_comp jsonb;
  v_rule public.revenue_tax_rates; v_calc record;
  v_number text; v_fy text;
  v_band public.revenue_value_bands; v_subtype public.revenue_supply_subtypes;
  v_count integer := 0;
  v_dg bigint; v_dt bigint; v_dn bigint;
  v_gross bigint := 0; v_tax bigint := 0; v_net bigint := 0;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  perform app.require_capability_anywhere('revenue.create');
  perform app.require_capability('revenue.create', p_business_unit_id);

  if not exists (
    select 1 from public.revenue_categories
     where id = p_revenue_category_id and org_id = v_org
       and business_unit_id = p_business_unit_id and archived_at is null
  ) then
    perform app.refuse('KM015', 'unknown_entity',
      'That revenue category does not belong to that business unit, or is archived.', '{}'::jsonb);
  end if;

  perform app.require_period_open(to_char(p_business_date, 'YYYY-MM'), p_business_unit_id);

  if jsonb_array_length(coalesce(p_components, '[]'::jsonb)) = 0 then
    perform app.refuse('KM024', 'revenue_without_components',
      'A revenue entry must have at least one component.', '{}'::jsonb);
  end if;

  insert into public.revenue_entries (
    id, org_id, business_unit_id, revenue_category_id, business_date,
    pnl_period_key, captured_at, entry_kind, source_reference, notes, created_by,
    business_date_source)
  values (
    p_id, v_org, p_business_unit_id, p_revenue_category_id, p_business_date,
    to_char(p_business_date, 'YYYY-MM'), coalesce(p_captured_at, now()),
    p_entry_kind, p_source_reference, p_notes, v_actor,
    -- Stated by the server, never by the caller. There is no provenance parameter, so a
    -- client cannot claim its own (spec §9, D-019).
    'derived');

  for v_comp in select * from jsonb_array_elements(p_components)
  loop
    -- The server resolves. Anything the caller sent about rate or tax is ignored, not
    -- trusted and then checked.
    v_rule := app.resolve_revenue_rule(
      p_revenue_category_id, p_business_date,
      nullif(v_comp->>'value_band_id', '')::uuid,
      nullif(v_comp->>'supply_subtype_id', '')::uuid,
      nullif(v_comp->>'premises_status_code', ''));

    select * into v_calc from app.revenue_compute(
      (v_comp->>'entered_amount_minor')::bigint, v_rule.rate_bp, v_rule.treatment);

    -- Compared, never used.
    v_dg := nullif(v_comp->>'declared_gross_minor', '')::bigint;
    v_dt := nullif(v_comp->>'declared_tax_minor', '')::bigint;
    v_dn := nullif(v_comp->>'declared_net_minor', '')::bigint;

    if (v_dg is not null and v_dg <> v_calc.gross)
       or (v_dt is not null and v_dt <> v_calc.tax)
       or (v_dn is not null and v_dn <> v_calc.net) then
      perform app.refuse('KM030', 'tax_configuration_mismatch',
        'The tax on this entry has changed since it was prepared. Review the current '
        'figures and record it again.',
        jsonb_build_object(
          'entered_amount_minor', (v_comp->>'entered_amount_minor')::bigint,
          'declared', jsonb_build_object('gross', v_dg, 'tax', v_dt, 'net', v_dn),
          'server',   jsonb_build_object('gross', v_calc.gross, 'tax', v_calc.tax,
                                         'net', v_calc.net),
          'tax_rule_id', v_rule.id, 'rate_bp', v_rule.rate_bp,
          'treatment', v_rule.treatment));
    end if;

    select * into v_band from public.revenue_value_bands where id = v_rule.value_band_id;
    select * into v_subtype from public.revenue_supply_subtypes where id = v_rule.supply_subtype_id;

    insert into public.revenue_components (
      id, org_id, revenue_entry_id, entered_amount_minor, entered_basis,
      gross_amount_minor, tax_amount_minor, net_amount_minor,
      tax_rule_id, tax_rate_bp, tax_treatment,
      value_band_id, value_band_label, value_band_floor_minor, value_band_ceiling_minor,
      supply_subtype_id, supply_subtype_label, premises_status_code)
    values (
      coalesce(nullif(v_comp->>'id','')::uuid, extensions.gen_random_uuid()),
      v_org, p_id,
      (v_comp->>'entered_amount_minor')::bigint,
      v_rule.input_basis,
      v_calc.gross, v_calc.tax, v_calc.net,
      v_rule.id, v_rule.rate_bp, v_rule.treatment,
      v_rule.value_band_id, v_band.label, v_band.floor_minor, v_band.ceiling_minor,
      v_rule.supply_subtype_id, v_subtype.label, v_rule.premises_status_code);

    v_gross := v_gross + v_calc.gross;
    v_tax   := v_tax   + v_calc.tax;
    v_net   := v_net   + v_calc.net;
    v_count := v_count + 1;
  end loop;

  -- Numbering only after every validation has passed, so a refused attempt burns no
  -- number.
  select issued_number, issued_financial_year into v_number, v_fy
    from app.next_revenue_number(v_org, p_business_date);

  update public.revenue_entries
     set txn_number = v_number, financial_year = v_fy
   where id = p_id;

  perform app.write_audit(v_org, 'revenue_entry', p_id, 'created', v_actor, null,
    jsonb_build_object('txn_number', v_number, 'business_date', p_business_date,
                       'components', v_count),
    null, p_business_unit_id, p_mutation_id);

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'create',
    jsonb_build_object('id', p_id, 'txn_number', v_number,
                       'financial_year', v_fy, 'row_version', 1, 'status', 'created',
                       'components', v_count,
                       'business_date_source', 'derived',
                       'gross_minor', v_gross, 'tax_minor', v_tax, 'net_minor', v_net));
end; $$;

revoke all on function public.revenue_create(uuid, uuid, uuid, date, jsonb, text, text, text, timestamptz, uuid) from public, anon;
grant execute on function public.revenue_create(uuid, uuid, uuid, date, jsonb, text, text, text, timestamptz, uuid) to authenticated;

-- ── Update: `corrected` on the moved branch, preserved on every other ────────
--
-- Restated with the provenance write and the provenance in the answer. Everything else is
-- the contract the previous corrective established and is unchanged: the move detected
-- from canonical state by comparing dates, the capability per property, the reason
-- required and normalised, both periods checked, the tax re-resolved against the new
-- date, KI-REV never restated, and the distinct `business_date_corrected` audit action.
--
-- **Once corrected, it stays corrected.** An ordinary later edit preserves the existing
-- value rather than resetting it to `derived`, because the question the column answers is
-- "how did this trading day come to be what it is", and a subsequent amount correction
-- does not change that answer.
create or replace function public.revenue_update(
  p_id                uuid,
  p_base_row_version  integer,
  p_business_date     date,
  p_components        jsonb,
  p_entry_kind        text default 'daily_summary',
  p_source_reference  text default null,
  p_notes             text default null,
  p_correction_reason text default null,
  p_mutation_id       uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_org uuid; v_replay jsonb; v_comp jsonb;
  v_entry public.revenue_entries;
  v_rule public.revenue_tax_rates; v_calc record;
  v_band public.revenue_value_bands; v_subtype public.revenue_supply_subtypes;
  v_before jsonb; v_window integer; v_today date;
  v_dg bigint; v_dt bigint; v_dn bigint;
  v_gross bigint := 0; v_tax bigint := 0; v_net bigint := 0;
  v_count integer := 0;
  v_target_period text;
  v_date_moved boolean;
  v_reason text;
  v_source text;
begin
  v_replay := app.replay_mutation(p_mutation_id);
  if v_replay is not null then
    return v_replay || jsonb_build_object('status', 'replayed');
  end if;

  v_actor := app.require_actor();
  v_org   := app.current_org_id();

  perform app.require_any_revenue_edit_capability();

  select * into v_entry from public.revenue_entries
   where id = p_id and org_id = v_org;
  if v_entry.id is null then
    perform app.refuse('KM015', 'unknown_entity',
      'That revenue entry does not exist.', '{}'::jsonb);
  end if;

  -- A voided document is immutable. Correction after a void is a new document, which is
  -- what void-and-re-enter means (spec §14, D-006).
  if v_entry.voided_at is not null then
    perform app.refuse('KM020', 'record_voided',
      'This revenue entry has been voided. Corrections are made by recording a new entry.',
      '{}'::jsonb);
  end if;

  -- Ownership. Without `revenue.edit.all` for this property, a caller may correct only
  -- what they recorded themselves.
  if not public.has_capability('revenue.edit.all', v_entry.business_unit_id) then
    perform app.require_capability('revenue.edit', v_entry.business_unit_id);
    if v_entry.created_by <> v_actor then
      perform app.refuse('KM001', 'missing_capability',
        'You may only change entries you recorded yourself.', '{}'::jsonb);
    end if;
  end if;

  -- ── Moving the date is its own act (spec §9) ────────────────────────────────
  --
  -- Decided from canonical state, by comparing **dates**. The period-key comparison
  -- below decides which locks to check and is a different question: 15 June to 20 June
  -- is a business-date correction and stays inside one period, so a guard keyed on the
  -- period would have missed most real corrections.
  v_date_moved := p_business_date is distinct from v_entry.business_date;

  if v_date_moved then
    perform app.require_capability('transaction.correct.business_date',
                                   v_entry.business_unit_id);

    -- The canonical rule for every mandatory financial reason: all whitespace, not just
    -- spaces. One helper, so the voids and the corrections cannot drift apart.
    v_reason := app.stated_reason(p_correction_reason);
    if length(v_reason) = 0 then
      perform app.refuse('KM008', 'reason_required',
        'Changing the business date of a recorded sale always states why. '
        'The reason is kept with the correction.',
        jsonb_build_object('revenue_entry_id', p_id,
                           'from', v_entry.business_date,
                           'to',   p_business_date));
    end if;
  end if;

  -- Configuration, not a constant (spec §13.3).
  select coalesce((os.value)::text::integer, 7) into v_window
    from public.org_settings os
   where os.org_id = v_org and os.key = 'edit_window_days';

  v_today := app.revenue_window_today(p_id);

  -- Inclusive of its last day: a business date of D is editable on D+7 and refused on
  -- D+8 (D-065). `transaction.correct.beyond_window` lifts the *age* rule and nothing
  -- else — every period check below still runs, and it authorises no date move.
  if (v_today - v_entry.business_date) > coalesce(v_window, 7)
     and not public.has_capability_anywhere('transaction.correct.beyond_window') then
    perform app.refuse('KM021', 'edit_window_expired',
      format('This entry is more than %s days old and can no longer be changed here.',
             coalesce(v_window, 7)),
      jsonb_build_object('business_date', v_entry.business_date,
                         'days_elapsed', v_today - v_entry.business_date,
                         'window_days', coalesce(v_window, 7)));
  end if;

  -- **Both** periods. The one the entry is in, and the one it would move to (D-124).
  perform app.require_period_open(v_entry.pnl_period_key, v_entry.business_unit_id);
  v_target_period := to_char(p_business_date, 'YYYY-MM');
  if v_target_period <> v_entry.pnl_period_key then
    perform app.require_period_open(v_target_period, v_entry.business_unit_id);
  end if;

  -- Concurrency, after authority and state, so a caller without permission never learns
  -- the current version (D-021, D-046).
  if v_entry.row_version <> p_base_row_version then
    perform app.refuse('KM003', 'version_conflict',
      'Somebody else changed this revenue entry while you were working on it.',
      jsonb_build_object('expected', p_base_row_version,
                         'actual', v_entry.row_version));
  end if;

  if jsonb_array_length(coalesce(p_components, '[]'::jsonb)) = 0 then
    perform app.refuse('KM024', 'revenue_without_components',
      'A revenue entry must have at least one component.', '{}'::jsonb);
  end if;

  -- Every refusal above happens before this point, so a refused correction leaves the
  -- provenance exactly as it found it.
  v_source := case when v_date_moved then 'corrected'
                   else v_entry.business_date_source end;

  v_before := to_jsonb(v_entry);

  -- The old components stop being the explanation of this document. The audit row below
  -- carries them, so the pre-edit figures remain evidence (spec §14).
  delete from public.revenue_components where revenue_entry_id = p_id;

  for v_comp in select * from jsonb_array_elements(p_components)
  loop
    -- The server resolves, against the **new** business date. A correction that moves an
    -- entry to a date where another rule applies gets that rule, not the old snapshot.
    v_rule := app.resolve_revenue_rule(
      v_entry.revenue_category_id, p_business_date,
      nullif(v_comp->>'value_band_id', '')::uuid,
      nullif(v_comp->>'supply_subtype_id', '')::uuid,
      nullif(v_comp->>'premises_status_code', ''));

    select * into v_calc from app.revenue_compute(
      (v_comp->>'entered_amount_minor')::bigint, v_rule.rate_bp, v_rule.treatment);

    -- Compared, never used (D-114).
    v_dg := nullif(v_comp->>'declared_gross_minor', '')::bigint;
    v_dt := nullif(v_comp->>'declared_tax_minor', '')::bigint;
    v_dn := nullif(v_comp->>'declared_net_minor', '')::bigint;

    if (v_dg is not null and v_dg <> v_calc.gross)
       or (v_dt is not null and v_dt <> v_calc.tax)
       or (v_dn is not null and v_dn <> v_calc.net) then
      perform app.refuse('KM030', 'tax_configuration_mismatch',
        'The tax on this entry has changed since it was prepared. Review the current '
        'figures and record it again.',
        jsonb_build_object(
          'entered_amount_minor', (v_comp->>'entered_amount_minor')::bigint,
          'declared', jsonb_build_object('gross', v_dg, 'tax', v_dt, 'net', v_dn),
          'server',   jsonb_build_object('gross', v_calc.gross, 'tax', v_calc.tax,
                                         'net', v_calc.net),
          'tax_rule_id', v_rule.id, 'rate_bp', v_rule.rate_bp,
          'treatment', v_rule.treatment));
    end if;

    select * into v_band from public.revenue_value_bands where id = v_rule.value_band_id;
    select * into v_subtype from public.revenue_supply_subtypes
     where id = v_rule.supply_subtype_id;

    insert into public.revenue_components (
      id, org_id, revenue_entry_id, entered_amount_minor, entered_basis,
      gross_amount_minor, tax_amount_minor, net_amount_minor,
      tax_rule_id, tax_rate_bp, tax_treatment,
      value_band_id, value_band_label, value_band_floor_minor, value_band_ceiling_minor,
      supply_subtype_id, supply_subtype_label, premises_status_code)
    values (
      coalesce(nullif(v_comp->>'id','')::uuid, extensions.gen_random_uuid()),
      v_org, p_id,
      (v_comp->>'entered_amount_minor')::bigint,
      v_rule.input_basis,
      v_calc.gross, v_calc.tax, v_calc.net,
      v_rule.id, v_rule.rate_bp, v_rule.treatment,
      v_rule.value_band_id, v_band.label, v_band.floor_minor, v_band.ceiling_minor,
      v_rule.supply_subtype_id, v_subtype.label, v_rule.premises_status_code);

    v_gross := v_gross + v_calc.gross;
    v_tax   := v_tax   + v_calc.tax;
    v_net   := v_net   + v_calc.net;
    v_count := v_count + 1;
  end loop;

  -- The business unit, the category and the transaction number are **not** in this list.
  -- The number belongs to the document's identity and survives every correction; the unit
  -- and the category are not editable, because an edit that moved revenue between
  -- properties would be a scope transfer rather than a correction.
  update public.revenue_entries
     set business_date  = p_business_date,
         pnl_period_key = v_target_period,
         business_date_source = v_source,
         entry_kind     = p_entry_kind,
         source_reference = p_source_reference,
         notes          = p_notes,
         row_version    = row_version + 1,
         updated_at     = now(),
         updated_by     = v_actor
   where id = p_id;

  perform app.write_audit(v_org, 'revenue_entry', p_id, 'edited', v_actor,
    v_before,
    jsonb_build_object('business_date', p_business_date,
                       'business_date_source', v_source,
                       'components', v_count,
                       'gross_minor', v_gross, 'tax_minor', v_tax, 'net_minor', v_net),
    null, v_entry.business_unit_id, p_mutation_id);

  -- A distinct action, so "which trading days were moved, by whom, and why" is answerable
  -- by reading one action rather than by diffing every edited row. Written only on the
  -- moved branch, and after the replay guard, so a redelivery produces no second effect.
  -- This remains the historical record; the column is the row's present-state provenance,
  -- and neither replaces the other.
  if v_date_moved then
    perform app.write_audit(v_org, 'revenue_entry', p_id, 'business_date_corrected',
      v_actor,
      jsonb_build_object('business_date', v_entry.business_date,
                         'pnl_period_key', v_entry.pnl_period_key,
                         'business_date_source', v_entry.business_date_source),
      jsonb_build_object('business_date', p_business_date,
                         'pnl_period_key', v_target_period,
                         'business_date_source', 'corrected'),
      v_reason, v_entry.business_unit_id, p_mutation_id);
  end if;

  return app.remember_mutation(p_mutation_id, v_org, v_actor,
    'revenue_entry', p_id, 'update',
    jsonb_build_object('id', p_id,
                       'txn_number', v_entry.txn_number,
                       'financial_year', v_entry.financial_year,
                       'row_version', v_entry.row_version + 1,
                       'status', 'updated',
                       'business_date_corrected', v_date_moved,
                       'business_date_source', v_source,
                       'components', v_count,
                       'gross_minor', v_gross, 'tax_minor', v_tax, 'net_minor', v_net));
end; $$;

revoke all on function public.revenue_update(
  uuid, integer, date, jsonb, text, text, text, text, uuid) from public, anon;
grant execute on function public.revenue_update(
  uuid, integer, date, jsonb, text, text, text, text, uuid) to authenticated;

-- ── Invariants ───────────────────────────────────────────────────────────────
do $$
declare v_def text; v_count integer; v_leak text; v_bad integer;
begin
  -- Two values, and only two. A third would be a column claiming the system can do
  -- something it cannot.
  if exists (select 1 from public.revenue_entries
              where business_date_source not in ('derived', 'corrected')) then
    raise exception 'revenue_entries holds a provenance value outside the approved set';
  end if;

  -- Every existing row is `derived`: nothing was inferred from updated_at, row_version,
  -- notes or a date comparison, and no correction was invented.
  select count(*) into v_bad
    from public.revenue_entries where business_date_source <> 'derived';
  if v_bad <> 0 then
    raise exception
      'the backfill produced % non-derived rows; it must invent no corrections', v_bad;
  end if;

  -- The client cannot choose it. `revenue_create` takes no provenance argument, and both
  -- write paths are the only writers.
  if pg_get_function_identity_arguments(
       'public.revenue_create(uuid,uuid,uuid,date,jsonb,text,text,text,timestamptz,uuid)'::regprocedure)
     like '%business_date_source%' then
    raise exception 'revenue_create accepts provenance from the caller';
  end if;

  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('revenue_create', 'revenue_update')
   group by p.proname having count(*) <> 1 limit 1;
  if v_count is not null then
    raise exception 'a revenue write path has more than one overload';
  end if;

  v_def := pg_get_functiondef(
    'public.revenue_update(uuid,integer,date,jsonb,text,text,text,text,uuid)'::regprocedure);

  -- Set on the moved branch, preserved otherwise. Asserted by name, because a
  -- restatement is exactly where this goes missing.
  if v_def not like '%case when v_date_moved then ''corrected''%' then
    raise exception 'revenue_update no longer records a corrected date as corrected';
  end if;
  if v_def not like '%else v_entry.business_date_source end%' then
    raise exception
      'revenue_update no longer preserves provenance across an ordinary edit';
  end if;
  -- And the guards the previous corrective added are all still there.
  if v_def not like '%transaction.correct.business_date%'
     or v_def not like '%transaction.correct.beyond_window%'
     or v_def not like '%app.stated_reason(p_correction_reason)%'
     or v_def not like '%require_period_open(v_entry.pnl_period_key%'
     or v_def not like '%resolve_revenue_rule%'
     or v_def not like '%business_date_corrected%' then
    raise exception 'a revenue correction guard was lost during the restatement';
  end if;
  if v_def like '%set%txn_number =%' then
    raise exception 'the transaction number must survive every correction';
  end if;

  -- The projection carries it, so nothing downstream has to infer it.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'revenue_document'
       and column_name = 'business_date_source') then
    raise exception 'revenue_document does not expose the provenance';
  end if;

  -- Unchanged boundaries.
  if not has_function_privilege('authenticated',
        'public.revenue_update(uuid,integer,date,jsonb,text,text,text,text,uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated',
        'public.revenue_create(uuid,uuid,uuid,date,jsonb,text,text,text,timestamptz,uuid)',
        'EXECUTE') then
    raise exception 'a revenue write path lost its EXECUTE grant';
  end if;
  if has_function_privilege('anon',
        'public.revenue_update(uuid,integer,date,jsonb,text,text,text,text,uuid)', 'EXECUTE')
     or has_function_privilege('anon',
        'public.revenue_create(uuid,uuid,uuid,date,jsonb,text,text,text,timestamptz,uuid)',
        'EXECUTE') then
    raise exception 'a revenue write path is reachable by anon';
  end if;

  select string_agg(p.proname, ', ') into v_leak
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_leak is not null then
    raise exception 'a client role can execute functions in app: %', v_leak;
  end if;
end $$;
