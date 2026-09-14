/// The canonical reporting cache: reads for reporting, and the one writer that fills it.
///
/// Phase 5 Slice 4. Everything about this file follows from one fact: these rows are
/// **server-owned** (D-171). Nothing local authored them, nothing local may edit them, and
/// the only thing that writes them is the reporting synchroniser.
///
/// ## The delta unit is a document, and replacement is scoped to a year
///
/// A correction can change a contribution's amount, split it differently across
/// properties, move it to another accounting period, or remove it entirely — so a changed
/// document has its contribution set **replaced**, never appended to (§14). Replacement is
/// bounded by the financial year being refreshed, because a document may contribute to two
/// years and refreshing one must not delete the other's rows (§15).
///
/// That bound is also what makes a business-date correction work. Moving a sale from June
/// to July means the June year refresh finds *no* rows for that document and deletes what
/// it had; the July refresh finds them and inserts. Neither step needs to know a correction
/// happened.
///
/// ## Completeness is a marker, never a row count
///
/// An empty cache and a fully synchronised year with no trade are identical in the data.
/// Collapsing them is how a device tells a manager the hotel earned nothing (D-106's
/// lesson, one layer up), so the claim is a separate record — written last, inside the same
/// transaction as the rows it certifies (D-108).
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart' show TaxTreatment;
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// One coverage claim: this owner's dataset for this property and financial year is
/// complete to this generation.
final class ReportingCoverageMarker {
  const ReportingCoverageMarker({
    required this.businessUnitId,
    required this.dataset,
    required this.financialYear,
    required this.generation,
    required this.onDemand,
    this.serverConfirmedAt,
    this.snapshotId,
  });

  final String businessUnitId;
  final ReportingDataset dataset;
  final int financialYear;

  /// Where the next delta resumes. A cursor, never a clock (D-188).
  final int generation;
  final bool onDemand;

  /// The server's own time for the snapshot this segment was certified from.
  final DateTime? serverConfirmedAt;

  /// The authoritative snapshot this segment belongs to. Segments of one report must
  /// share it before the report may claim to be synchronised as of anything.
  final String? snapshotId;

  /// Whether this segment carries coherent snapshot evidence at all. A marker written
  /// before the Slice 6 corrective does not, and says so rather than guessing.
  bool get hasSnapshotEvidence =>
      snapshotId != null && serverConfirmedAt != null;
}

/// One dataset's share of a coherent snapshot, ready to be applied.
///
/// Assembled by the synchroniser from a single server response and handed to
/// [ReportingCache.applySnapshot] whole, so both datasets commit together.
final class DatasetApplication {
  const DatasetApplication({
    required this.documentIds,
    required this.rowsByYear,
    required this.generationByYear,
  });

  /// Every document the snapshot named, including those that came back only as voided
  /// rows and those whose rows now fall in a year this run is not refreshing. Both are
  /// how a stale figure would otherwise survive replacement (D-178).
  final List<String> documentIds;

  final Map<int, List<ReportingRowValues>> rowsByYear;

  /// The delta cursor each year is certified to. Separate from the snapshot identity by
  /// design: this says where the next pull resumes, not what moment these facts are.
  final Map<int, int> generationByYear;

  List<ReportingRowValues> rowsFor(int year) =>
      rowsByYear[year] ?? const <ReportingRowValues>[];

  int generationFor(int year) => generationByYear[year] ?? 0;
}

/// Reads and writes the canonical reporting cache.
final class ReportingCache {
  const ReportingCache(this._db);

  final AppDatabase _db;

  // ── Reads, for the reporting source ────────────────────────────────────────
  //
  // No canonical-only predicate appears here, and its absence is the point. In the
  // transaction tables a row may be pending, rejected or quarantined, so every reporting
  // read had to filter (D-168). Every row in this cache came from the server's own
  // projection, so there is nothing to filter — which removes the one place that rule
  // could be forgotten.
  //
  // Voided documents are simply not stored: the synchroniser drops them on the way in, so
  // "the active reporting effect" is the whole table.

  /// Summed revenue paise for one property over one inclusive P&L-date range.
  Future<RevenueTotals> revenueTotals({
    required String ownerUserId,
    required String businessUnitId,
    required ReportRange range,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(gross_minor), 0) AS g, '
          '       COALESCE(SUM(tax_minor), 0)   AS t, '
          '       COALESCE(SUM(net_minor), 0)   AS n, '
          '       COUNT(*)                      AS c '
          '  FROM reporting_revenue_contributions '
          ' WHERE owner_user_id = ? AND business_unit_id = ? '
          '   AND pnl_date >= ? AND pnl_date <= ?',
          variables: [
            Variable<String>(ownerUserId),
            Variable<String>(businessUnitId),
            Variable<String>(range.from.iso),
            Variable<String>(range.to.iso),
          ],
        )
        .getSingle();
    return RevenueTotals(
      gross: Money.fromPaise(row.read<int>('g')),
      tax: Money.fromPaise(row.read<int>('t')),
      net: Money.fromPaise(row.read<int>('n')),
      contributions: row.read<int>('c'),
    );
  }

  /// Summed expense paise for one property over one inclusive P&L-date range.
  Future<ExpenseTotals> expenseTotals({
    required String ownerUserId,
    required String businessUnitId,
    required ReportRange range,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_minor), 0) AS a, COUNT(*) AS c '
          '  FROM reporting_expense_contributions '
          ' WHERE owner_user_id = ? AND business_unit_id = ? '
          '   AND pnl_date >= ? AND pnl_date <= ?',
          variables: [
            Variable<String>(ownerUserId),
            Variable<String>(businessUnitId),
            Variable<String>(range.from.iso),
            Variable<String>(range.to.iso),
          ],
        )
        .getSingle();
    return ExpenseTotals(
      amount: Money.fromPaise(row.read<int>('a')),
      contributions: row.read<int>('c'),
    );
  }

  /// Revenue grouped by category, for the breakdown the target report shape needs.
  Future<List<RevenueCategoryTotals>> revenueByCategory({
    required String ownerUserId,
    required String businessUnitId,
    required ReportRange range,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT revenue_category_id AS r, '
          '       COALESCE(SUM(gross_minor), 0) AS g, '
          '       COALESCE(SUM(tax_minor), 0)   AS t, '
          '       COALESCE(SUM(net_minor), 0)   AS n, '
          '       COUNT(*)                      AS c, '
          // The treatment the cached components recorded. `none` and a configured 0% both
          // give zero tax and stay distinguishable (D-091, D-122); a group spanning both
          // is described by neither and collapses to null.
          '       CASE WHEN COUNT(DISTINCT tax_treatment) = 1 '
          '            THEN MIN(tax_treatment) ELSE NULL END AS tr '
          '  FROM reporting_revenue_contributions '
          ' WHERE owner_user_id = ? AND business_unit_id = ? '
          '   AND pnl_date >= ? AND pnl_date <= ? '
          ' GROUP BY revenue_category_id ORDER BY revenue_category_id',
          variables: [
            Variable<String>(ownerUserId),
            Variable<String>(businessUnitId),
            Variable<String>(range.from.iso),
            Variable<String>(range.to.iso),
          ],
        )
        .get();
    return [
      for (final row in rows)
        RevenueCategoryTotals(
          businessUnitId: businessUnitId,
          revenueCategoryId: row.read<String>('r'),
          treatment: switch (row.read<String?>('tr')) {
            final String name => TaxTreatment.fromName(name),
            null => null,
          },
          totals: RevenueTotals(
            gross: Money.fromPaise(row.read<int>('g')),
            tax: Money.fromPaise(row.read<int>('t')),
            net: Money.fromPaise(row.read<int>('n')),
            contributions: row.read<int>('c'),
          ),
        ),
    ];
  }

  /// Expenses grouped down the hierarchy.
  Future<List<ExpenseCategoryTotals>> expensesByCategory({
    required String ownerUserId,
    required String businessUnitId,
    required ReportRange range,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT department_id AS d, section_id AS s, category_id AS k, '
          '       COALESCE(SUM(amount_minor), 0) AS a, COUNT(*) AS c '
          '  FROM reporting_expense_contributions '
          ' WHERE owner_user_id = ? AND business_unit_id = ? '
          '   AND pnl_date >= ? AND pnl_date <= ? '
          ' GROUP BY department_id, section_id, category_id '
          ' ORDER BY department_id, section_id, category_id',
          variables: [
            Variable<String>(ownerUserId),
            Variable<String>(businessUnitId),
            Variable<String>(range.from.iso),
            Variable<String>(range.to.iso),
          ],
        )
        .get();
    return [
      for (final row in rows)
        ExpenseCategoryTotals(
          businessUnitId: businessUnitId,
          departmentId: row.read<String>('d'),
          sectionId: row.read<String>('s'),
          categoryId: row.read<String>('k'),
          totals: ExpenseTotals(
            amount: Money.fromPaise(row.read<int>('a')),
            contributions: row.read<int>('c'),
          ),
        ),
    ];
  }

  // ── Document rows, for the read-only drill-down (Phase 5 Slice 10) ─────────
  //
  // The same rows the category totals were summed from, summed at the document instead.
  // Every predicate here is one the headline read already applies — owner, property,
  // inclusive `pnl_date` range — plus the exact bucket identity, so a document row can only
  // ever be part of the line it sits under. No transaction timestamp, device date or server
  // calendar date is consulted.

  /// Each revenue document's contribution to one property's revenue category.
  Future<List<RevenueDocumentLine>> revenueDocuments({
    required String ownerUserId,
    required String businessUnitId,
    required String revenueCategoryId,
    required ReportRange range,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT revenue_entry_id AS d, MIN(pnl_date) AS p, '
          '       COALESCE(SUM(gross_minor), 0) AS g, '
          '       COALESCE(SUM(tax_minor), 0)   AS t, '
          '       COALESCE(SUM(net_minor), 0)   AS n, '
          '       COUNT(*)                      AS c '
          '  FROM reporting_revenue_contributions '
          ' WHERE owner_user_id = ? AND business_unit_id = ? '
          '   AND revenue_category_id = ? '
          '   AND pnl_date >= ? AND pnl_date <= ? '
          ' GROUP BY revenue_entry_id '
          ' ORDER BY p DESC, revenue_entry_id',
          variables: [
            Variable<String>(ownerUserId),
            Variable<String>(businessUnitId),
            Variable<String>(revenueCategoryId),
            Variable<String>(range.from.iso),
            Variable<String>(range.to.iso),
          ],
        )
        .get();
    return [
      for (final row in rows)
        RevenueDocumentLine(
          businessUnitId: businessUnitId,
          revenueCategoryId: revenueCategoryId,
          revenueEntryId: row.read<String>('d'),
          pnlDate: BusinessDate.tryParse(row.read<String>('p'))!,
          totals: RevenueTotals(
            gross: Money.fromPaise(row.read<int>('g')),
            tax: Money.fromPaise(row.read<int>('t')),
            net: Money.fromPaise(row.read<int>('n')),
            contributions: row.read<int>('c'),
          ),
        ),
    ];
  }

  /// Each expense document's contribution to one exact Department + Section + Category
  /// bucket of one property.
  Future<List<ExpenseDocumentLine>> expenseDocuments({
    required String ownerUserId,
    required String businessUnitId,
    required String departmentId,
    required String sectionId,
    required String categoryId,
    required ReportRange range,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT expense_id AS d, MIN(pnl_date) AS f, MAX(pnl_date) AS l, '
          '       MIN(vendor_id) AS v, '
          '       COALESCE(SUM(amount_minor), 0) AS a, COUNT(*) AS c '
          '  FROM reporting_expense_contributions '
          ' WHERE owner_user_id = ? AND business_unit_id = ? '
          '   AND department_id = ? AND section_id = ? AND category_id = ? '
          '   AND pnl_date >= ? AND pnl_date <= ? '
          ' GROUP BY expense_id '
          ' ORDER BY l DESC, expense_id',
          variables: [
            Variable<String>(ownerUserId),
            Variable<String>(businessUnitId),
            Variable<String>(departmentId),
            Variable<String>(sectionId),
            Variable<String>(categoryId),
            Variable<String>(range.from.iso),
            Variable<String>(range.to.iso),
          ],
        )
        .get();
    return [
      for (final row in rows)
        ExpenseDocumentLine(
          businessUnitId: businessUnitId,
          departmentId: departmentId,
          sectionId: sectionId,
          categoryId: categoryId,
          expenseId: row.read<String>('d'),
          firstPnlDate: BusinessDate.tryParse(row.read<String>('f'))!,
          lastPnlDate: BusinessDate.tryParse(row.read<String>('l'))!,
          vendorId: row.read<String?>('v'),
          totals: ExpenseTotals(
            amount: Money.fromPaise(row.read<int>('a')),
            contributions: row.read<int>('c'),
          ),
        ),
    ];
  }

  // ── Coverage markers ───────────────────────────────────────────────────────

  /// The marker for one scope, or null when nothing has ever certified it.
  Future<ReportingCoverageMarker?> markerFor({
    required String ownerUserId,
    required String businessUnitId,
    required ReportingDataset dataset,
    required int financialYear,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT generation, on_demand, server_confirmed_at, snapshot_id '
          '  FROM reporting_coverage_markers '
          ' WHERE owner_user_id = ? AND business_unit_id = ? '
          '   AND dataset = ? AND financial_year = ?',
          variables: [
            Variable<String>(ownerUserId),
            Variable<String>(businessUnitId),
            Variable<String>(dataset.wireName),
            Variable<int>(financialYear),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ReportingCoverageMarker(
      businessUnitId: businessUnitId,
      dataset: dataset,
      financialYear: financialYear,
      generation: row.read<int>('generation'),
      onDemand: row.read<bool>('on_demand'),
      serverConfirmedAt: row.read<DateTime?>('server_confirmed_at'),
      snapshotId: row.read<String?>('snapshot_id'),
    );
  }

  /// Every marker this owner holds. For diagnostics and the retention sweep.
  Future<List<ReportingCoverageMarker>> markersFor(String ownerUserId) async {
    final rows = await _db
        .customSelect(
          'SELECT business_unit_id, dataset, financial_year, generation, '
          '       on_demand, server_confirmed_at, snapshot_id '
          '  FROM reporting_coverage_markers WHERE owner_user_id = ? '
          ' ORDER BY business_unit_id, dataset, financial_year',
          variables: [Variable<String>(ownerUserId)],
        )
        .get();
    return [
      for (final row in rows)
        ReportingCoverageMarker(
          businessUnitId: row.read<String>('business_unit_id'),
          dataset: ReportingDataset.fromWire(row.read<String>('dataset')),
          financialYear: row.read<int>('financial_year'),
          generation: row.read<int>('generation'),
          onDemand: row.read<bool>('on_demand'),
          serverConfirmedAt: row.read<DateTime?>('server_confirmed_at'),
          snapshotId: row.read<String?>('snapshot_id'),
        ),
    ];
  }

  // ── The write path, used only by the synchroniser ──────────────────────────

  /// Replaces one financial year of one dataset for the named documents, and certifies it.
  ///
  /// **One transaction, and the marker is written last** (D-108). A crash before the
  /// commit leaves the previous state entirely — never rows without a claim, and never the
  /// reverse, which would certify facts that are not there.
  ///
  /// [documentIds] are the documents whose contribution sets are being replaced. Rows are
  /// deleted for those documents **within this financial year only**, so a document that
  /// also contributes to another retained year keeps those rows (§15).
  Future<void> applyYear({
    required String ownerUserId,
    required String orgId,
    required ReportingDataset dataset,
    required int financialYear,
    required Set<String> businessUnitIds,
    required List<String> documentIds,
    required List<ReportingRowValues> rows,
    required int generation,
    required bool onDemand,
    DateTime? serverConfirmedAt,
    String? snapshotId,
    required DateTime now,
  }) => _db.transaction(
    () => _applyYearWithin(
      ownerUserId: ownerUserId,
      orgId: orgId,
      dataset: dataset,
      financialYear: financialYear,
      businessUnitIds: businessUnitIds,
      documentIds: documentIds,
      rows: rows,
      generation: generation,
      onDemand: onDemand,
      serverConfirmedAt: serverConfirmedAt,
      snapshotId: snapshotId,
      now: now,
    ),
  );

  /// One coherent snapshot, applied atomically (D-188).
  ///
  /// Both datasets and every retained year land in **one local transaction**, and the
  /// snapshot evidence is written with the markers at the end of it. That is what makes
  /// the coherence claim true rather than hopeful: there is no committed state in which
  /// revenue has been replaced from this snapshot and expenses have not, and no state in
  /// which a marker certifies a snapshot whose rows did not land.
  ///
  /// A failure anywhere rolls the whole run back, so the previous coherent snapshot
  /// survives intact — a half-applied refresh would be exactly the mixed evidence the
  /// corrective exists to remove.
  Future<void> applySnapshot({
    required String ownerUserId,
    required String orgId,
    required String snapshotId,
    required DateTime serverConfirmedAt,
    required Set<String> businessUnitIds,
    required List<int> financialYears,
    required Map<ReportingDataset, DatasetApplication> datasets,
    required bool onDemand,
    required DateTime now,
  }) => _db.transaction(() async {
    for (final dataset in ReportingDataset.values) {
      final application = datasets[dataset];
      if (application == null) continue;
      for (final year in financialYears) {
        await _applyYearWithin(
          ownerUserId: ownerUserId,
          orgId: orgId,
          dataset: dataset,
          financialYear: year,
          businessUnitIds: businessUnitIds,
          documentIds: application.documentIds,
          rows: application.rowsFor(year),
          generation: application.generationFor(year),
          onDemand: onDemand,
          serverConfirmedAt: serverConfirmedAt,
          snapshotId: snapshotId,
          now: now,
        );
      }
    }
  });

  Future<void> _applyYearWithin({
    required String ownerUserId,
    required String orgId,
    required ReportingDataset dataset,
    required int financialYear,
    required Set<String> businessUnitIds,
    required List<String> documentIds,
    required List<ReportingRowValues> rows,
    required int generation,
    required bool onDemand,
    DateTime? serverConfirmedAt,
    String? snapshotId,
    required DateTime now,
  }) async {
    final table = dataset == ReportingDataset.revenue
        ? 'reporting_revenue_contributions'
        : 'reporting_expense_contributions';
    final documentColumn = dataset == ReportingDataset.revenue
        ? 'revenue_entry_id'
        : 'expense_id';

    {
      // 1 · Clear what these documents used to contribute to this year. Bounded by the
      //     year so another year's cached rows survive, and by the owner so nobody else's
      //     cache is touched.
      for (final chunk in _chunked(documentIds, 400)) {
        final placeholders = List.filled(chunk.length, '?').join(', ');
        await _db.customStatement(
          'DELETE FROM $table WHERE owner_user_id = ? AND financial_year = ? '
          'AND $documentColumn IN ($placeholders)',
          <Object>[ownerUserId, financialYear, ...chunk],
        );
      }

      // 2 · Write what they contribute now. `INSERT OR REPLACE` rather than plain insert:
      //     an overlapping re-pull delivers the same row twice and must land in exactly
      //     the same state, not raise (§19).
      for (final row in rows) {
        await _db.customStatement(
          row.insertSql(table),
          row.values(
            ownerUserId: ownerUserId,
            orgId: orgId,
            financialYear: financialYear,
            syncedAt: now,
          ),
        );
      }

      // 3 · Certify, last. Every unit in the run gets the same generation, because one
      //     run is one authoritative boundary (§21).
      for (final unit in businessUnitIds) {
        await _db.customStatement(
          'INSERT INTO reporting_coverage_markers '
          '(owner_user_id, org_id, business_unit_id, dataset, financial_year, '
          ' generation, server_confirmed_at, snapshot_id, on_demand, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(owner_user_id, business_unit_id, dataset, financial_year) '
          'DO UPDATE SET generation = excluded.generation, '
          '              server_confirmed_at = excluded.server_confirmed_at, '
          '              snapshot_id = excluded.snapshot_id, '
          '              on_demand = reporting_coverage_markers.on_demand '
          '                          AND excluded.on_demand, '
          '              updated_at = excluded.updated_at',
          <Object?>[
            ownerUserId,
            orgId,
            unit,
            dataset.wireName,
            financialYear,
            generation,
            serverConfirmedAt?.toUtc().toIso8601String(),
            snapshotId,
            onDemand ? 1 : 0,
            now.toUtc().toIso8601String(),
          ],
        );
      }
    }
  }

  /// Removes a year's cache and its markers for this owner. Used by retention pruning.
  Future<int> pruneYear({
    required String ownerUserId,
    required int financialYear,
  }) async {
    var removed = 0;
    await _db.transaction(() async {
      for (final table in const [
        'reporting_revenue_contributions',
        'reporting_expense_contributions',
      ]) {
        removed += await _db.customUpdate(
          'DELETE FROM $table WHERE owner_user_id = ? AND financial_year = ?',
          variables: [
            Variable<String>(ownerUserId),
            Variable<int>(financialYear),
          ],
          updates: const {},
        );
      }
      await _db.customStatement(
        'DELETE FROM reporting_coverage_markers '
        'WHERE owner_user_id = ? AND financial_year = ?',
        <Object>[ownerUserId, financialYear],
      );
    });
    return removed;
  }

  static Iterable<List<T>> _chunked<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}

/// One cache row, as the synchroniser hands it over.
///
/// A small sealed pair rather than two repository methods, so the year-replacement
/// transaction above is written once and cannot drift between the two datasets.
sealed class ReportingRowValues {
  const ReportingRowValues();

  String insertSql(String table);

  List<Object?> values({
    required String ownerUserId,
    required String orgId,
    required int financialYear,
    required DateTime syncedAt,
  });
}

final class RevenueRowValues extends ReportingRowValues {
  const RevenueRowValues({
    required this.contributionId,
    required this.revenueEntryId,
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.pnlDate,
    required this.pnlPeriodKey,
    required this.grossMinor,
    required this.taxMinor,
    required this.netMinor,
    required this.taxTreatment,
    required this.taxRateBasisPoints,
    required this.enteredBasis,
    required this.documentGeneration,
    this.valueBandId,
    this.supplySubtypeId,
  });

  final String contributionId;
  final String revenueEntryId;
  final String businessUnitId;
  final String revenueCategoryId;
  final String pnlDate;
  final String pnlPeriodKey;
  final int grossMinor;
  final int taxMinor;
  final int netMinor;
  final String taxTreatment;
  final int taxRateBasisPoints;
  final String enteredBasis;
  final int documentGeneration;
  final String? valueBandId;
  final String? supplySubtypeId;

  @override
  String insertSql(String table) =>
      'INSERT OR REPLACE INTO $table '
      '(owner_user_id, org_id, contribution_id, revenue_entry_id, business_unit_id, '
      ' revenue_category_id, pnl_date, pnl_period_key, gross_minor, tax_minor, '
      ' net_minor, tax_treatment, tax_rate_basis_points, entered_basis, value_band_id, '
      ' supply_subtype_id, financial_year, document_generation, synced_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  @override
  List<Object?> values({
    required String ownerUserId,
    required String orgId,
    required int financialYear,
    required DateTime syncedAt,
  }) => [
    ownerUserId,
    orgId,
    contributionId,
    revenueEntryId,
    businessUnitId,
    revenueCategoryId,
    pnlDate,
    pnlPeriodKey,
    grossMinor,
    taxMinor,
    netMinor,
    taxTreatment,
    taxRateBasisPoints,
    enteredBasis,
    valueBandId,
    supplySubtypeId,
    financialYear,
    documentGeneration,
    syncedAt.toUtc().toIso8601String(),
  ];
}

final class ExpenseRowValues extends ReportingRowValues {
  const ExpenseRowValues({
    required this.contributionId,
    required this.expenseId,
    required this.allocationId,
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
    required this.pnlDate,
    required this.pnlPeriodKey,
    required this.amountMinor,
    required this.documentGeneration,
    this.vendorId,
  });

  final String contributionId;
  final String expenseId;
  final String allocationId;
  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;
  final String pnlDate;
  final String pnlPeriodKey;
  final int amountMinor;
  final int documentGeneration;
  final String? vendorId;

  @override
  String insertSql(String table) =>
      'INSERT OR REPLACE INTO $table '
      '(owner_user_id, org_id, contribution_id, expense_id, allocation_id, '
      ' business_unit_id, department_id, section_id, category_id, vendor_id, '
      ' pnl_date, pnl_period_key, amount_minor, financial_year, document_generation, '
      ' synced_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  @override
  List<Object?> values({
    required String ownerUserId,
    required String orgId,
    required int financialYear,
    required DateTime syncedAt,
  }) => [
    ownerUserId,
    orgId,
    contributionId,
    expenseId,
    allocationId,
    businessUnitId,
    departmentId,
    sectionId,
    categoryId,
    vendorId,
    pnlDate,
    pnlPeriodKey,
    amountMinor,
    financialYear,
    documentGeneration,
    syncedAt.toUtc().toIso8601String(),
  ];
}
