# Migration provenance ledger

Every migration version `krishna-mis-dev` believes it has applied, and the committed file
that accounts for it. Maintained deliberately, in the same spirit as the reviewed API
surface (D-044): it is restated when it grows, and a test fails when it drifts.

This exists because the Slice 4 report claimed "seven migrations, all committed" while the
repository held **two** files for **seven** ledger versions. The SQL was equivalent;
the provenance was not, and equivalence is not what an audit trail is for (A0).

## The convention

Supabase records its own application timestamp as the ledger `version`. Repository
filenames carry an *authored* sequence number, so the two timestamps differ for the same
migration — `conventions` is ledger `20260827130730` and file `20260827090000_conventions.sql`.
**Matching is by name, not by version number.**

From Phase 4 Slice 4 onward, each ledger version gets its own file, named
`<ledger-version>_<ledger-name>.sql`.

## Phase 2 and Phase 3 — grouped files, recorded rather than rewritten

Twelve Phase 2/3 ledger entries were applied as separate steps and committed as grouped
files. Their SQL is committed; only the one-file-per-version mapping is absent. They are
**not** being renamed retroactively: they are settled, released history, and rewriting it
to satisfy a convention introduced later would be a worse trade than recording the
grouping. Each is accounted for here.

| Ledger version | Ledger name | Accounted for by |
|---|---|---|
| 20260828165850 | `api_surface_invariant_v3` | `20260827092000_api_surface_invariant.sql` lineage — the surface is restated in full each time it grows; the newest restatement supersedes the earlier ones |
| 20260828190824 | `api_surface_invariant_v4` | same lineage |
| 20260829133240 | `api_surface_invariant_v5` | same lineage |
| 20260828185444 | `expense_schema_tables` | `20260829090100_expense_schema.sql` |
| 20260828185516 | `expense_schema_triggers` | `20260829090100_expense_schema.sql` |
| 20260828185844 | `expense_rpc_helpers` | `20260829090400_expense_rpcs.sql` |
| 20260828190253 | `expense_numbering_fix_ambiguity` | `20260829090200_expense_numbering.sql` |
| 20260828190803 | `expense_trigger_function_grants` | `20260829090100_expense_schema.sql` |
| 20260829132925 | `master_usage_historical_and_active` | `20260829100000_usage_and_attachment_storage.sql` |
| 20260829133017 | `expense_attachment_storage` | `20260829100000_usage_and_attachment_storage.sql` |
| 20260829133621 | `drop_superseded_record_master_usage` | `20260829100000_usage_and_attachment_storage.sql` |
| 20260829142013 | `expense_update_accepts_either_edit_capability` | `20260829110000_edit_window_property_date.sql` |

## Phase 4 Slice 4 — one file per version

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260901115849 | `revenue_tables` | `20260901115849_revenue_tables.sql` |
| 20260901115939 | `revenue_tax_resolution` | `20260901115939_revenue_tax_resolution.sql` |
| 20260901132003 | `revenue_resolver_numbering_projection` | `20260901132003_revenue_resolver_numbering_projection.sql` |
| 20260901132148 | `revenue_rpcs` | `20260901132148_revenue_rpcs.sql` |
| 20260901132225 | `revenue_verified_baseline_fy2627` | `20260901132225_revenue_verified_baseline_fy2627.sql` |
| 20260901132659 | `revenue_projection_security_barrier` | `20260901132659_revenue_projection_security_barrier.sql` |
| 20260901135812 | `api_surface_invariant_revenue` | `20260901135812_api_surface_invariant_revenue.sql` |

## Phase 4 Slice 4 audit corrections (A1, A2) and Slice 5

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260901142347 | `premises_status_no_overlap` | `20260901142347_premises_status_no_overlap.sql` |
| 20260901144002 | `revenue_arithmetic_parity` | `20260901144002_revenue_arithmetic_parity.sql` |

## Phase 4 Slice 6

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260901181358 | `revenue_config_read_boundary` | `20260901181358_revenue_config_read_boundary.sql` |
| 20260902104120 | `revenue_config_policy_uses_public_helper` | `20260902104120_revenue_config_policy_uses_public_helper.sql` |
| 20260902104238 | `api_surface_invariant_revenue_config` | `20260902104238_api_surface_invariant_revenue_config.sql` |

## Phase 4 Slice 7

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260902111217 | `revenue_create_declared_totals` | `20260902111217_revenue_create_declared_totals.sql` |
| 20260902115805 | `revenue_numbering_ambiguous_column` | `20260902115805_revenue_numbering_ambiguous_column.sql` |
| 20260902120217 | `revenue_projections_use_a_real_capability` | `20260902120217_revenue_projections_use_a_real_capability.sql` |

The first two were applied during the audit and were **not committed at the time** — the
same omission A0 exists to catch, caught by A0's own check one slice later. Both were
recovered verbatim from the server's migration record (the D-056 procedure) rather than
retyped from memory, because a file that merely resembles what ran is not provenance.

## Phase 4 Slice 10

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260904144542 | `revenue_update_boundary` | `20260904144542_revenue_update_boundary.sql` |
| 20260904150814 | `api_surface_invariant_revenue_update` | `20260904150814_api_surface_invariant_revenue_update.sql` |

## Phase 3 corrective — expense business-date correction

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260905141738 | `expense_business_date_correction` | `20260905141738_expense_business_date_correction.sql` |
| 20260905142059 | `correction_reason_rejects_all_whitespace` | `20260905142059_correction_reason_rejects_all_whitespace.sql` |

Two versions for one corrective, and the second is not tidiness. The first was applied and
its live test then found a defect **in the fix**: `btrim(text)` strips spaces and not tabs,
so a one-tab correction reason was accepted. The applied file is not rewritten to look like
something that never ran — both are committed as they were applied, and each was verified
byte-for-byte against `supabase_migrations.schema_migrations.statements` rather than by
resemblance (D-056).

## Phase 4 corrective — revenue business-date correction governance

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260905144151 | `revenue_business_date_correction_governance` | `20260905144151_revenue_business_date_correction_governance.sql` |

Found by the bounded parity audit the expense corrective required, and by probe rather than
by reading: a Manager holding no correction capability moved a sale's business date, with no
reason and no distinct audit action. Verified byte-for-byte against the applied statements,
like the two above.

## Pre-Slice-11 corrective — whitespace-only reasons, and revenue date provenance

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260905185903 | `financial_reasons_reject_all_whitespace` | `20260905185903_financial_reasons_reject_all_whitespace.sql` |
| 20260905190229 | `revenue_business_date_provenance` | `20260905190229_revenue_business_date_provenance.sql` |

Two approved items, one migration each. The first closes the defect the previous
corrective recorded and deliberately left: one-argument `btrim` strips spaces and not
tabs, so a lone tab satisfied the mandatory void reason on **both** engines — proven by
voiding two development fixtures with one before anything was changed. The second adds
`revenue_entries.business_date_source`, backfilled to `derived` and never inferred.

Both verified byte-for-byte against `supabase_migrations.schema_migrations.statements`
rather than by resemblance (D-056).

## Final pre-Slice-11 corrective — the last mandatory financial reason

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260905202325 | `period_reopen_uses_canonical_reason` | `20260905202325_period_reopen_uses_canonical_reason.sql` |

The fifth and last mandatory financial reason to reach the canonical all-whitespace rule.
D-142 fixed the two voids and recorded this one as outside its approved scope; proven by
reopening a genuinely closed period with a lone tab before anything was changed.

It also makes the reason constraints **validate where the data allows**. All three are
installed `NOT VALID` and then validated by a block that counts violating rows, so a clean
environment ends up fully validated while `krishna-mis-dev` — which holds one immutable
probe row per table — stays unvalidated and says why. No environment is named, no fixture
id is hardcoded, and no financial history is rewritten.

Verified byte-for-byte against `supabase_migrations.schema_migrations.statements` (D-056).

## Phase 4 Slice 11 closure - the upload lifecycle after the bytes land

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260906121007 | `attachment_upload_lifecycle` | `20260906121007_attachment_upload_lifecycle.sql` |
| 20260906121034 | `api_surface_invariant_attachment_lifecycle` | `20260906121034_api_surface_invariant_attachment_lifecycle.sql` |

Storage write authority stops being read authority, so a voided parent can no longer
accept bytes its own register RPC will refuse; an object no metadata row names can be
reclaimed by the client that wrote it, and one that is named cannot be touched at all.
Proven red first: four of the eight objects the Slice 11 report could not account for
were produced by the ordinary path against a voided sale, with no seam involved, and the
same defect had been latent on the expense side since D-073a (D-154).

Verified byte-for-byte against `supabase_migrations.schema_migrations.statements` (D-056).

## Phase 4 Slice 12 - the revenue reporting interface

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260906124407 | `revenue_period_contributions` | `20260906124407_revenue_period_contributions.sql` |

A `security_barrier` **view**, not a table, and the migration asserts that it is not
a table (D-157). Everything a contribution reports is already stored: its money on
the component and its period on the entry, under the CHECK that ties `pnl_period_key`
to the business date. A stored copy would add nothing except the obligation to keep
two copies in step through a correction, an edit, a void and a replay - and each of
those is a way for a month to be counted twice or not at all.

It carries `voided_at` and does not filter on it, exactly as
`expense_period_contributions` does: the row stays for audit and every aggregate
excludes it (D-006).

Verified byte-for-byte against `supabase_migrations.schema_migrations.statements` (D-056).

## Phase 4 closure corrective - the fourth write privilege

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260907021741 | `clients_hold_no_write_privilege_at_all` | `20260907021741_clients_hold_no_write_privilege_at_all.sql` |

The Phase 3 RLS migration revoked `insert, update, delete` and left **TRUNCATE**
standing on four financial base tables, because Supabase grants ALL to `authenticated`
by template - and TRUNCATE does not consult row level security. Not reachable through
PostgREST, which has no way to say it, but a privilege nobody reviewed on four tables
that hold financial history. The five projections carried the whole default GRANT ALL
as well. Everything is revoked and exactly the reads the product performs are granted
back, with the invariant restated over all four privileges and over the whole schema
rather than over a list (D-162).

Verified byte-for-byte against `supabase_migrations.schema_migrations.statements` (D-056).

## Phase 5 Slice 5 - the server reporting boundary

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260907201332 | `reporting_primitives_boundary` | `20260907201332_reporting_primitives_boundary.sql` |
| 20260907201539 | `api_surface_invariant_reporting_primitives` | `20260907201539_api_surface_invariant_reporting_primitives.sql` |
| 20260907204444 | `reporting_primitives_reads_each_side_once` | `20260907204444_reporting_primitives_reads_each_side_once.sql` |

`public.reporting_primitives` is the authoritative comparison point the D-020 parity suite
measures the offline cache against. It is **`security invoker`**, which is the whole of its
safety: it reads the two `security_barrier` projections with the caller's own privileges, so
it can return nothing the caller could not already have selected row by row and added up
(D-184). It gates each side of the P&L on D-164's data half - `revenue.view` and
`expense.view.all`, per property, `expense.view.own` never - and an unauthorised side comes
back **null rather than zero**. It does not check `reports.view`, which the corrective below
adds; the sentence that once stood here - that its absence stays Slice 7's and adds no
exposure - was wrong, and is corrected there rather than edited out of an applied
migration's own account (D-187).

One SQL statement, so both sides come from one snapshot; the invariant refuses a second
statement or a `plpgsql` rewrite. It derives nothing, needs no tax configuration to answer a
historical P&L, casts every sum to `bigint`, and has no branch in which an omitted unit set
means the whole organisation.

The expense projection is recreated to carry `txn_number`, appended after `change_seq`
because `create or replace view` may only grow at the end - stating the canonical rule
D-168 settled on the server in the same words the client uses.

The third migration is a **measured** change, not a tidy-up: the expense projection carries a
per-row `security definer` predicate (D-169), and the first version scanned it twice whenever
a breakdown was asked for. Each side is now grouped once and the headline rolls up from those
subtotals - the same integer, since integer addition is associative. A whole financial year
went from 774 ms to 399 ms; a month is 39 ms (D-186).

All three verified byte-for-byte against `supabase_migrations.schema_migrations.statements`
(D-056).

## Phase 5 Slice 5 corrective - the reporting boundary enforces `reports.view`

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260908050614 | `reporting_primitives_requires_reports_view` | `20260908050614_reporting_primitives_requires_reports_view.sql` |

**Proven red first.** A controlled authority fixture - a principal holding `revenue.view`
and `expense.view.all` for Crystal Canopy and **no** `reports.view`, stated by capability
and never by role name - received Rs 2,28,086.02 of that property's cost base over 63
contributions from the shipped RPC. `security invoker` had kept it from returning any row
that principal could not already select, and that is a statement about data access rather
than about the approved reporting authorization contract, which is D-164 and names three
capabilities.

`reporting_primitives` now requires `reports.view` per property before either side is
considered, and the **unscoped** form of all three for a request naming more than one
property - so two scoped grants cannot become an organisation-wide consolidated privilege.
Missing authority is still `null` and never zero, and missing `reports.view` removes both
sides together, so no combination produces half a P&L (D-163). The same green probe returns
`revenue: null, expense: null`.

The migration restates every Slice 5 invariant over the replacement - not `security
definer`, `stable`, `language sql`, one statement, both projections read exactly once, no
base table, `pnl_date` only, no rate, no float, no role name, scope never widening by
omission - because a `create or replace` is where a lost predicate gets in (D-174).

**D-139's exemption machinery is updated in the same migration**, which is the only honest
place for it: `reports.view` now has an evaluator, so its line goes, and `reports.export`,
`reports.print` and `settings.manage` stay because those surfaces genuinely do not exist.
A third assertion states it positively - `reports.view` must be granted to some role **and**
named by the boundary - because the first two would both pass if it were simply granted to
nobody.

Verified byte-for-byte against `supabase_migrations.schema_migrations.statements` (D-056).

## Phase 5 OA-1 - Owner Accounts Foundation

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260909105555 | `owner_accounts_capabilities` | `20260909105555_owner_accounts_capabilities.sql` |
| 20260909110038 | `owner_accounts_schema` | `20260909110038_owner_accounts_schema.sql` |
| 20260909110608 | `owner_ledger_rpcs` | `20260909110608_owner_ledger_rpcs.sql` |
| 20260909110912 | `expense_categories_refuse_owner_drawings` | `20260909110912_expense_categories_refuse_owner_drawings.sql` |
| 20260909111051 | `owner_trigger_functions_revoked` | `20260909111051_owner_trigger_functions_revoked.sql` |
| 20260909111136 | `api_surface_invariant_owner_accounts` | `20260909111136_api_surface_invariant_owner_accounts.sql` |
| 20260909112045 | `owner_ledger_view_is_grantable` | `20260909112045_owner_ledger_view_is_grantable.sql` |
| 20260910161035 | `owner_share_set_refuses_backdating` | `20260910161035_owner_share_set_refuses_backdating.sql` |
| 20260910171751 | `owner_share_set_enforces_the_v1_vector` | `20260910171751_owner_share_set_enforces_the_v1_vector.sql` |
| 20260910172611 | `owner_share_refusal_promises_no_unavailable_act` | `20260910172611_owner_share_refusal_promises_no_unavailable_act.sql` |
| 20260910180630 | `owner_ledger_snapshot_transport` | `20260910180630_owner_ledger_snapshot_transport.sql` |
| 20260910180836 | `api_surface_invariant_owner_snapshot` | `20260910180836_api_surface_invariant_owner_snapshot.sql` |

Five tables, all RLS-enabled and default-deny; the `KI-OWN` sequence; nine reviewed RPCs;
the capability namespace under `owner_masters.*` and `owner_ledger.*`; and a trigger that
refuses an expense category named for an owner movement, proven at deploy time against
real rows with a positive control beside it.

**Two of the eight are correctives, and both are the same family the log keeps recording.**
`owner_ledger_view_is_grantable` replaces `has_unscoped_capability('owner_ledger.view')`
with `has_capability_anywhere`: D-025 forces every non-Owner grant to name a business unit,
so the unscoped form could be satisfied by the Owner and by nobody else, and the Accountant
could record, correct and void a movement and then read nothing. That is D-110 and D-116, a
third time. `owner_share_set_refuses_backdating` gives the forward-only ownership timeline
a refusal of its own, so configuring a ratio at or before one already configured meets a
sentence rather than `23P01` and a constraint name.

`owner_trigger_functions_revoked` is the third instance of D-044 / D-101: two new trigger
functions were left `PUBLIC EXECUTE`, and the API-surface invariant refused the migration
that would have shipped them.

`owner_share_set_enforces_the_v1_vector` is the project lead's 2026-09-10 ruling (D-204) at
the configuration boundary: exactly two owners, 5000 basis points each. **Its header names
no ledger version**, deliberately — the version is assigned at apply time, so a file naming
it cannot be the text submitted, which is what the note below had to record about every
earlier OA-1 file. Its executable lines match the applied statement exactly (130 lines,
`3870b23c…`).

`owner_share_refusal_promises_no_unavailable_act` corrects a sentence that migration
deployed: the third-owner refusal told an administrator to end an existing owner's share,
and **no API can do that** (D-205). Executable lines match exactly (108 lines,
`a03c565e…`).

## Phase 5 OA-2 - the canonical owner data a settlement reads

`owner_ledger_snapshot_transport` closes the gap the OA-2 completeness audit proved: a
second device saw **no** owner movements another device had recorded, and **no** ownership
masters at all. The gap was entirely client-side — the same session was handed everything
by the server — so this adds a caller's read rather than a boundary (D-173's finding, in a
second domain).

**One `language sql` statement**, returning movements, owners and ownership shares together
with `pg_current_snapshot()` and `now()` from that same statement. Four separate reads would
be four MVCC snapshots, and a settlement assembled from them would be a position of a moment
that never existed — the defect D-188 corrected for reporting, which it would be worse to
repeat knowingly. An invariant refuses a `plpgsql` rewrite or a second statement.

It **calculates nothing** — no entitlement, no position, no balance — and is
`security invoker`, so it returns only rows the caller could already have selected under
`owner_ledger.view`. No new capability: `owner_settlement.view` stays reserved for OA-3, and
a deploy assertion fails if it appears (OA-2 §44).

`api_surface_invariant_owner_snapshot` restates the reviewed surface at 58. **One assertion
from the OA-1 restatement is deliberately not copied forward**: it required the two owner
read policies to use the *unscoped* capability, which `20260909112045` replaced (D-200).
Copying it would have restated a rule the database no longer satisfies, from the migration
that first defined the policy rather than the one that last replaced it — D-174 exactly.

Executable lines match exactly: 134 lines `79fe63e3…`, and 167 lines `f2c12219…`.

## Phase 5 OA-3 - the settlement permission, the start date, and a closed transport

| Ledger version | Ledger name | Committed file |
|---|---|---|
| 20260911130948 | `owner_settlement_view_capability` | `20260911130948_owner_settlement_view_capability.sql` |
| 20260911131042 | `owner_settlement_start_date` | `20260911131042_owner_settlement_start_date.sql` |
| 20260911131130 | `owner_ledger_snapshot_requires_settlement_view` | `20260911131130_owner_ledger_snapshot_requires_settlement_view.sql` |
| 20260911131228 | `api_surface_invariant_owner_settlement` | `20260911131228_api_surface_invariant_owner_settlement.sql` |

`owner_settlement_view_capability` creates the capability D-197 reserved, granted to the
Owner bundle only by the project lead's OA-3 ruling, with a deploy assertion that no other
bundle holds it.

`owner_settlement_start_date` adds the one server setting from which 50:50 ownership and
owner settlement begin (OA-3 Q1): one row per organisation, first of a month, **no row
seeded** because the production date is outstanding, written only by
`owner_settlement_start_set` under `owner_masters.manage`, audited, with explicit
`base_row_version` concurrency.

`owner_ledger_snapshot_requires_settlement_view` closes a gap **proven RED first**: signed in
as the Accountant — who holds `owner_ledger.view` and by ruling has no settlement access —
the OA-2 transport returned 159 movements, 3 owners, 34 ownership-share rows and 2 family
links. It now returns `settlement_authorised: false` and null datasets to that principal,
while the Accountant still reads the same 159 ledger rows through RLS: the settlement
transport is gated, the underlying ledger right is not.

`api_surface_invariant_owner_settlement` restates the reviewed surface at 59.

Executable lines match the applied statements exactly: 27 `820020c1`, 179 `7a9243c2`,
123 `14bcd622`, 194 `e65bd1e2`.

### On "byte-for-byte", stated accurately rather than repeated

Earlier sections of this ledger say each migration was "verified byte-for-byte against
`supabase_migrations.schema_migrations.statements`". Measured rather than asserted, that
has never been literally true of any migration in this repository, and it is worth stating
once rather than repeating a claim that does not hold:

* Supabase stores the submitted text **without its trailing newline**, so every committed
  file is one byte longer than the statement it is accounted for by;
* an OA-1 file's header names its own ledger version, and the version is assigned by the
  server *at apply time* - so a file that names it cannot have been the text submitted.
  These headers were corrected after the versions came back.

What **is** true, and is checked mechanically rather than claimed: for all eight OA-1
versions, the committed file and the applied statement are **identical in every executable
line**. Comparing both sides with blank lines and `--` comment lines removed and each
remaining line trimmed gives an exact match, line count and digest, for each of the eight.
The divergences are confined to comments, blank lines, indentation and that header line.

## The full applied ledger, in order

```
20260827130730 conventions
20260827130806 identity
20260827130845 masters
20260827130918 master_integrity
20260827130945 user_roles
20260827131010 period_control
20260827131045 tax_rules
20260827131121 audit_and_usage
20260827131206 authorization
20260827131256 rls
20260827131424 master_rpcs
20260827131555 vendor_tax_period_rpcs
20260827131654 seed
20260827131734 owner_bootstrap
20260827131805 function_grants
20260827132133 uniform_refusal_entity_type
20260827132256 fix_restore_guard_branching
20260827134503 user_provisioning
20260827135003 policies_use_public_helper
20260827135132 check_capability_before_existence
20260827135634 api_surface_invariant
20260828103538 my_authority
20260828160905 user_reactivate
20260828165850 api_surface_invariant_v3
20260828184635 expense_capabilities
20260828185444 expense_schema_tables
20260828185516 expense_schema_triggers
20260828185540 expense_numbering
20260828185740 expense_rls
20260828185844 expense_rpc_helpers
20260828185938 expense_rpcs
20260828190253 expense_numbering_fix_ambiguity
20260828190803 expense_trigger_function_grants
20260828190824 api_surface_invariant_v4
20260829132925 master_usage_historical_and_active
20260829133017 expense_attachment_storage
20260829133240 api_surface_invariant_v5
20260829133621 drop_superseded_record_master_usage
20260829142013 expense_update_accepts_either_edit_capability
20260829180301 edit_window_property_date
20260830161150 attachment_register
20260830164150 attachment_metadata_uses_definer_predicate
20260901115849 revenue_tables
20260901115939 revenue_tax_resolution
20260901132003 revenue_resolver_numbering_projection
20260901132148 revenue_rpcs
20260901132225 revenue_verified_baseline_fy2627
20260901132659 revenue_projection_security_barrier
20260901135812 api_surface_invariant_revenue
20260901142248 revenue_rule_completeness
20260901142347 premises_status_no_overlap
20260901144002 revenue_arithmetic_parity
20260901181358 revenue_config_read_boundary
20260902104120 revenue_config_policy_uses_public_helper
20260902104238 api_surface_invariant_revenue_config
20260902111217 revenue_create_declared_totals
20260902115805 revenue_numbering_ambiguous_column
20260902120217 revenue_projections_use_a_real_capability
20260904144542 revenue_update_boundary
20260904150814 api_surface_invariant_revenue_update
20260905141738 expense_business_date_correction
20260905142059 correction_reason_rejects_all_whitespace
20260905144151 revenue_business_date_correction_governance
20260905185903 financial_reasons_reject_all_whitespace
20260905190229 revenue_business_date_provenance
20260905202325 period_reopen_uses_canonical_reason
20260905210226 revenue_attachments
20260905210332 api_surface_invariant_revenue_attachments
20260906121007 attachment_upload_lifecycle
20260906121034 api_surface_invariant_attachment_lifecycle
20260906124407 revenue_period_contributions
20260907021741 clients_hold_no_write_privilege_at_all
20260907030228 expense_view_own_means_own
20260907030255 api_surface_invariant_expense_view_own
20260907030443 attachment_metadata_policy_restored_and_guarded
20260907115757 revenue_change_seq_advances_on_update
20260907121017 reporting_contributions_carry_document_generation
20260907201332 reporting_primitives_boundary
20260907201539 api_surface_invariant_reporting_primitives
20260907204444 reporting_primitives_reads_each_side_once
20260908050614 reporting_primitives_requires_reports_view
20260908122910 reporting_snapshot_transport
20260908123059 api_surface_invariant_reporting_snapshot
20260908124127 reporting_primitives_states_server_time
20260909105555 owner_accounts_capabilities
20260909110038 owner_accounts_schema
20260909110608 owner_ledger_rpcs
20260909110912 expense_categories_refuse_owner_drawings
20260909111051 owner_trigger_functions_revoked
20260909111136 api_surface_invariant_owner_accounts
20260909112045 owner_ledger_view_is_grantable
20260910161035 owner_share_set_refuses_backdating
20260910171751 owner_share_set_enforces_the_v1_vector
20260910172611 owner_share_refusal_promises_no_unavailable_act
20260910180630 owner_ledger_snapshot_transport
20260910180836 api_surface_invariant_owner_snapshot
20260911130948 owner_settlement_view_capability
20260911131042 owner_settlement_start_date
20260911131130 owner_ledger_snapshot_requires_settlement_view
20260911131228 api_surface_invariant_owner_settlement
```
