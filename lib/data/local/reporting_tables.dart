/// The canonical reporting cache: server-owned financial facts, synchronised for reporting.
///
/// Phase 5 Slice 4, local schema **v17**. This is a **different authority class** from the
/// transaction tables beside it, and that is the whole reason it is separate storage
/// (D-171).
///
/// ## Why these are not rows in `revenue_entries` / `expenses`
///
/// Those tables hold *this actor's* work, in every state a person's work can be in:
/// pending, in flight, rejected, conflicted, quarantined, or created here and never sent.
/// A reporting fact is none of those. It is a canonical accepted figure the **server**
/// returned, it belongs to a synchronisation generation, and no local edit may ever touch
/// it.
///
/// Mixing them would mean every reporting query re-deriving which rows are canonical, on
/// tables where the answer varies per row and per user — which is precisely the arrangement
/// that produced the E2 defect Slice 1 had to correct (D-168). Keeping them apart means the
/// reporting query has nothing to filter: every row in these tables is canonical by
/// construction, because only the reporting synchroniser writes them.
///
/// ## Owned by a user, not merely scoped to a property
///
/// Every row carries `owner_user_id`. A device is shared — that is the whole reason D-054
/// added a sign-out control and D-074 exists at all — so "the cached P&L for Crystal
/// Canopy" is not a fact about the device, it is a fact about *a person's* authority over
/// Crystal Canopy at a moment in time. Keying by owner makes User B inheriting User A's
/// figures structurally impossible rather than something a query has to remember.
///
/// ## What is deliberately absent
///
/// No notes, no attachments, no editable payload, no outbox state, no row version, no
/// mutation id. This is reporting data, not transaction replication: a device that has
/// synchronised a colleague's sale can report it and cannot open it, which is exactly the
/// distinction Slice 4 exists to draw.
library;

import 'package:drift/drift.dart';

/// One accepted revenue component, as reporting received it from the server.
///
/// Component grain, mirroring `public.revenue_period_contributions` — a two-band Room day
/// is two rows, because flattening them would state a blended rate that was applied to
/// nothing (D-087).
@DataClassName('ReportingRevenueRow')
class ReportingRevenueContributions extends Table {
  @override
  String get tableName => 'reporting_revenue_contributions';

  /// Whose cache this is. Never null, never inferred (D-074).
  TextColumn get ownerUserId => text().named('owner_user_id')();

  TextColumn get orgId => text().named('org_id')();

  /// The source contribution's own identity on the server — the component id. Stable, and
  /// what makes an overlapping re-pull idempotent rather than duplicating (§19).
  TextColumn get contributionId => text().named('contribution_id')();

  /// The document the contribution belongs to. The **delta unit**: a changed document has
  /// its whole contribution set replaced, never appended to (§14).
  TextColumn get revenueEntryId => text().named('revenue_entry_id')();

  TextColumn get businessUnitId => text().named('business_unit_id')();
  TextColumn get revenueCategoryId => text().named('revenue_category_id')();

  /// The stored accrual date and its `YYYY-MM` key, exactly as the server holds them.
  /// Nothing is re-derived here — a business date is decided once, under the property's
  /// timezone and cut-off, and persisted (D-019, D-067).
  TextColumn get pnlDate => text().named('pnl_date')();
  TextColumn get pnlPeriodKey => text().named('pnl_period_key')();

  /// The accepted figures. Integer paise, and never recomputed: a report of a June sale
  /// must be unchanged by a rate configured in December (D-080).
  IntColumn get grossMinor => integer().named('gross_minor')();
  IntColumn get taxMinor => integer().named('tax_minor')();
  IntColumn get netMinor => integer().named('net_minor')();

  /// Treatment travels because `none` and a configured `0%` both give ₹0 of tax and are
  /// not the same fact (D-091, D-122). The rate and basis travel with it so a breakdown
  /// can explain the figure without joining anything.
  TextColumn get taxTreatment => text().named('tax_treatment')();
  IntColumn get taxRateBasisPoints =>
      integer().named('tax_rate_basis_points')();
  TextColumn get enteredBasis => text().named('entered_basis')();

  /// The conditional identities, where the rule used them. Kept because a Room band is a
  /// reporting dimension (D-087); the bounds are not, and are not stored.
  TextColumn get valueBandId => text().named('value_band_id').nullable()();
  TextColumn get supplySubtypeId =>
      text().named('supply_subtype_id').nullable()();

  /// The financial year this contribution's P&L date falls in, stored so a coverage
  /// marker and a cache row can be matched without parsing a date in SQL.
  IntColumn get financialYear => integer().named('financial_year')();

  /// The effective document generation this row was synchronised at (D-177). Used to
  /// recognise a re-delivered document and to keep the watermark honest.
  IntColumn get documentGeneration => integer().named('document_generation')();

  DateTimeColumn get syncedAt => dateTime().named('synced_at')();

  @override
  Set<Column<Object>> get primaryKey => {ownerUserId, contributionId};
}

/// One accepted expense period contribution, as reporting received it.
///
/// Allocation-line × accounting-period grain, mirroring
/// `public.expense_period_contributions`. A shared bill contributes to two properties
/// through two lines, which is what makes a shared cost attributable at all (D-003).
@DataClassName('ReportingExpenseRow')
class ReportingExpenseContributions extends Table {
  @override
  String get tableName => 'reporting_expense_contributions';

  TextColumn get ownerUserId => text().named('owner_user_id')();
  TextColumn get orgId => text().named('org_id')();

  /// The period-allocation row's own id on the server.
  TextColumn get contributionId => text().named('contribution_id')();

  /// The delta unit.
  TextColumn get expenseId => text().named('expense_id')();

  /// The allocation line, kept because a document's contributions are grouped by line and
  /// a correction replaces lines wholesale.
  TextColumn get allocationId => text().named('allocation_id')();

  TextColumn get businessUnitId => text().named('business_unit_id')();
  TextColumn get departmentId => text().named('department_id')();
  TextColumn get sectionId => text().named('section_id')();
  TextColumn get categoryId => text().named('category_id')();
  TextColumn get vendorId => text().named('vendor_id').nullable()();

  /// The accrual attribution the server decided. Never reinterpreted here: a June salary
  /// paid on 5 July is a June cost, and payment date is a different report (D-016).
  TextColumn get pnlDate => text().named('pnl_date')();
  TextColumn get pnlPeriodKey => text().named('pnl_period_key')();

  /// Gross cost including GST — there is no input credit in V1 (spec §6.1, D-018).
  IntColumn get amountMinor => integer().named('amount_minor')();

  IntColumn get financialYear => integer().named('financial_year')();
  IntColumn get documentGeneration => integer().named('document_generation')();
  DateTimeColumn get syncedAt => dateTime().named('synced_at')();

  @override
  Set<Column<Object>> get primaryKey => {ownerUserId, contributionId};
}

/// Proof that a scope's canonical reporting dataset was completely synchronised.
///
/// **Completeness is never inferred from rows.** An empty cache and a complete year with
/// no trade look identical from the data, and collapsing them is how a device tells a
/// manager the hotel earned nothing (D-106's lesson, one layer up). So the claim is a
/// separate record, written last inside the same transaction as the rows it certifies
/// (D-108).
///
/// Keyed per **user × business unit × dataset × financial year**, because that is the
/// smallest thing that can honestly be complete on its own:
///
///   * per user — a shared workstation, D-074;
///   * per unit — authority is granted a property at a time, and gaining one says nothing
///     about the other;
///   * per dataset — revenue may synchronise while expenses fail, and a P&L needs both
///     (D-163);
///   * per financial year — retention is current + previous FY, and a range crossing
///     1 April needs two markers on each side.
@DataClassName('ReportingCoverageRow')
class ReportingCoverageMarkers extends Table {
  @override
  String get tableName => 'reporting_coverage_markers';

  TextColumn get ownerUserId => text().named('owner_user_id')();
  TextColumn get orgId => text().named('org_id')();
  TextColumn get businessUnitId => text().named('business_unit_id')();

  /// `revenue` or `expense`.
  TextColumn get dataset => text().named('dataset')();

  /// The financial year's opening year — the same identity `FinancialYear` uses, so a
  /// marker and a `FinancialYearPeriod` cannot disagree about which year they mean.
  IntColumn get financialYear => integer().named('financial_year')();

  /// The authoritative generation this scope is complete to. A later delta asks for
  /// changes above it, less the safety overlap (ARCHITECTURE §5.2).
  IntColumn get generation => integer().named('generation')();

  /// The server's own time, carried as evidence for Slice 6 and **not interpreted here**.
  /// Never the device clock: a client-authored timestamp is not proof of anything about a
  /// server's state (D-112's reasoning, applied to a different question).
  DateTimeColumn get serverConfirmedAt =>
      dateTime().named('server_confirmed_at').nullable()();

  /// Whether this year is normal retention (current or previous FY) or was fetched on
  /// demand. Pruning treats them differently and the difference has to be recorded, not
  /// recomputed — "which year is previous" changes every 1 April.
  BoolColumn get onDemand =>
      boolean().named('on_demand').withDefault(const Constant(false))();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column<Object>> get primaryKey => {
    ownerUserId,
    businessUnitId,
    dataset,
    financialYear,
  };

  @override
  List<String> get customConstraints => [
    "CHECK (dataset IN ('revenue', 'expense'))",
  ];
}
