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
```
