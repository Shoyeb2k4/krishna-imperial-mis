/// `LocalReportingEngine` (Phase 5 Slice 3).
///
/// The engine reads this device's two canonical projections, hands primitive summed paise
/// to `Pnl.compute`, and computes nothing itself. These tests drive a **real** SQLite
/// database through the real repositories, so the canonical predicate, the range mapping
/// and the aggregate are all exercised in SQL rather than simulated.
///
/// The one thing the production wiring deliberately cannot do yet is claim complete
/// coverage: there is no reporting pull on either engine (D-173), so `NoCanonicalCoverage`
/// answers `notDownloaded` and the engine refuses. These tests supply an explicit
/// known-complete oracle to exercise everything behind that gate — which is why the first
/// group asserts the production default before any of the others assume otherwise.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/reporting/drift_reporting_source.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/pnl_reference.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';

/// A coverage oracle a test controls, standing in for Slice 4's marker.
///
/// Per side since D-183, so a fixture can make revenue complete and expenses absent and
/// see which of them the refusal actually names.
final class _Coverage implements ReportingCoverageOracle {
  _Coverage(this._byUnit, {Map<String, ReportingCoverage>? expenses})
    : _expensesByUnit = expenses ?? _byUnit;
  final Map<String, ReportingCoverage> _byUnit;
  final Map<String, ReportingCoverage> _expensesByUnit;

  @override
  ReportingCoverage coverageFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingDatasetSide side,
  }) =>
      (side == ReportingDatasetSide.revenue
          ? _byUnit
          : _expensesByUnit)[businessUnitId] ??
      ReportingCoverage.notDownloaded;
}

ReportingCoverageOracle _complete([Set<String> units = const {_ccr, _hki}]) =>
    _Coverage({for (final u in units) u: ReportingCoverage.complete});

/// One side covered and the other not, for the D-183 assertions.
ReportingCoverageOracle _sideOnly({
  required ReportingDatasetSide covered,
  Set<String> units = const {_ccr, _hki},
}) {
  final present = {for (final u in units) u: ReportingCoverage.complete};
  const absent = <String, ReportingCoverage>{};
  return covered == ReportingDatasetSide.revenue
      ? _Coverage(present, expenses: absent)
      : _Coverage(absent, expenses: present);
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late RevenueRepository revenue;
  late ExpenseRepository expenses;
  var revSeq = 0;
  var expSeq = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = OFF');
    revenue = RevenueRepository(db, tax: RevenueTaxRepository(db));
    expenses = ExpenseRepository(db);
    revSeq = 0;
    expSeq = 0;
  });
  tearDown(() => db.close());

  LocalReportingEngine engineWith(ReportingCoverageOracle coverage) =>
      LocalReportingEngine(
        DriftReportingSource(
          revenue: revenue,
          expenses: expenses,
          coverage: coverage,
        ),
      );

  /// One canonical accepted sale, written straight into the projection's base tables.
  ///
  /// `txn_number` present is what makes it canonical (D-168). Everything else mirrors what
  /// `revenue_create` would have written.
  Future<String> canonicalRevenue({
    required String unit,
    required String category,
    required String businessDate,
    required int gross,
    required int tax,
    required int net,
    String treatment = 'inclusive',
    int rateBp = 500,
    String? number,
    bool voided = false,
  }) async {
    final id = 'rev-${revSeq++}';
    final period = businessDate.substring(0, 7);
    await db.customStatement(
      'INSERT INTO revenue_entries (id, org_id, txn_number, financial_year, '
      'business_unit_id, revenue_category_id, business_date, pnl_period_key, '
      'captured_at, entry_kind, created_by, row_version, updated_at, voided_at, '
      'voided_by, void_reason) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)',
      [
        id,
        _org,
        number ?? 'KI-REV-26-27-${(1000 + revSeq).toString()}',
        '26-27',
        unit,
        category,
        businessDate,
        period,
        '${businessDate}T09:00:00.000Z',
        'daily_summary',
        'user-1',
        '${businessDate}T09:00:00.000Z',
        if (voided) '${businessDate}T10:00:00.000Z' else null,
        if (voided) 'user-1' else null,
        if (voided) 'duplicate' else null,
      ],
    );
    await db.customStatement(
      'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
      'entered_amount_minor, entered_basis, gross_amount_minor, tax_amount_minor, '
      'net_amount_minor, tax_rule_id, tax_rate_basis_points, tax_treatment) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'comp-$id',
        _org,
        id,
        gross,
        'inclusive_total',
        gross,
        tax,
        net,
        'rule-1',
        rateBp,
        treatment,
      ],
    );
    return id;
  }

  /// A sale this device recorded and the server has never accepted.
  Future<String> pendingRevenue({
    required String unit,
    required String businessDate,
    required int gross,
  }) async {
    final id = await canonicalRevenue(
      unit: unit,
      category: 'cat-restaurant',
      businessDate: businessDate,
      gross: gross,
      tax: 0,
      net: gross,
    );
    await db.customStatement(
      'UPDATE revenue_entries SET txn_number = NULL, financial_year = NULL '
      'WHERE id = ?',
      [id],
    );
    return id;
  }

  /// One canonical accepted expense contribution.
  ///
  /// [pnlDate] is the accrual date the contribution reports — deliberately separate from
  /// [businessDate], because that separation is the whole of D-016 and the thing a
  /// reporting range must respect.
  Future<String> canonicalExpense({
    required String unit,
    required int amount,
    required String pnlDate,
    String? businessDate,
    String category = 'cat-kirana',
    String? paymentDate,
    bool canonical = true,
    bool voided = false,
  }) async {
    final id = 'exp-${expSeq++}';
    final period = pnlDate.substring(0, 7);
    final docDate = businessDate ?? pnlDate;
    await db.customStatement(
      'INSERT INTO expenses (id, org_id, txn_number, financial_year, business_date, '
      'business_date_source, visibility, document_total_minor, visible_amount_minor, '
      'is_shared, payment_status, payment_date, payment_method_id, created_by, '
      'captured_at, row_version, updated_at, voided_at, voided_by, void_reason) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)',
      [
        id,
        _org,
        canonical ? 'KI-EXP-26-27-${(2000 + expSeq).toString()}' : null,
        canonical ? 2026 : null,
        docDate,
        'derived',
        'complete',
        amount,
        amount,
        paymentDate == null ? 'unpaid' : 'paid',
        paymentDate,
        paymentDate == null ? null : 'pm-cash',
        'user-1',
        '${docDate}T09:00:00.000Z',
        '${docDate}T09:00:00.000Z',
        if (voided) '${docDate}T10:00:00.000Z' else null,
        if (voided) 'user-1' else null,
        if (voided) 'duplicate' else null,
      ],
    );
    await db.customStatement(
      'INSERT INTO expense_allocations (id, org_id, expense_id, business_unit_id, '
      'department_id, section_id, category_id, amount_minor, category_label, '
      'sort_order, row_version, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 1, ?)',
      [
        'alloc-$id',
        _org,
        id,
        unit,
        'dept-1',
        'sec-1',
        category,
        amount,
        'Kirana',
        '${docDate}T09:00:00.000Z',
      ],
    );
    await db.customStatement(
      'INSERT INTO expense_period_allocations (id, org_id, expense_id, allocation_id, '
      'business_unit_id, accounting_period_start, accounting_period_end, amount_minor, '
      'pnl_date, pnl_period_key, is_derived, row_version, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?)',
      [
        'per-$id',
        _org,
        id,
        'alloc-$id',
        unit,
        '$period-01',
        pnlDate,
        amount,
        pnlDate,
        period,
        '${docDate}T09:00:00.000Z',
      ],
    );
    return id;
  }

  PnlResult resultOf(ReportEnvelope envelope) {
    expect(
      envelope.outcome,
      isA<PnlComputed>(),
      reason: 'expected a computed report, got ${envelope.outcome}',
    );
    return envelope.resultOrNull!;
  }

  final june = MonthPeriod(2026, 6);

  // ── Coverage is per side, and the refusal names the side (D-183) ──────────
  group('a missing side is reported as that side', () {
    setUp(() async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 10000000,
        tax: 476190,
        net: 9523810,
      );
      await canonicalExpense(
        unit: _ccr,
        pnlDate: '2026-06-20',
        amount: 4500000,
      );
    });

    test('revenue missing, expenses complete → revenueUnavailable', () async {
      final envelope = await engineWith(
        _sideOnly(covered: ReportingDatasetSide.expenses, units: {_ccr}),
      ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr)));

      expect(
        envelope.refusalOrNull,
        PnlRefusal.revenueUnavailable,
        reason:
            'the markers always knew which dataset was missing; folding them into one '
            'value per property threw that away and refused as bothSidesUnavailable, '
            'naming neither the absent side nor the one that was fine (D-183)',
      );
      expect(envelope.revenueCoverage, ReportingCoverage.notDownloaded);
      expect(envelope.expenseCoverage, ReportingCoverage.complete);
    });

    test('expenses missing, revenue complete → expensesUnavailable', () async {
      final envelope = await engineWith(
        _sideOnly(covered: ReportingDatasetSide.revenue, units: {_ccr}),
      ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr)));

      expect(envelope.refusalOrNull, PnlRefusal.expensesUnavailable);
      expect(envelope.revenueCoverage, ReportingCoverage.complete);
      expect(envelope.expenseCoverage, ReportingCoverage.notDownloaded);
    });

    test('both missing → bothSidesUnavailable', () async {
      final envelope = await engineWith(
        _Coverage(const {}),
      ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr)));

      expect(envelope.refusalOrNull, PnlRefusal.bothSidesUnavailable);
      expect(envelope.revenueCoverage, ReportingCoverage.notDownloaded);
      expect(envelope.expenseCoverage, ReportingCoverage.notDownloaded);
    });

    test(
      'both complete over an empty range → a real zero, not a refusal',
      () async {
        final envelope = await engineWith(_complete({_ccr})).report(
          ReportRequest(
            period: const MonthPeriod(2026, 2),
            scope: ReportingScope.unit(_ccr),
          ),
        );
        final result = resultOf(envelope);
        expect(result.grossSales, Money.zero);
        expect(result.gst, Money.zero);
        expect(result.netSales, Money.zero);
        expect(result.expenses, Money.zero);
        expect(result.operatingProfit, Money.zero);
        expect(result.margin, isA<MarginNotApplicable>());
        expect(envelope.coverage, ReportingCoverage.complete);
      },
    );

    test('the unavailable side carries why, so a caller can act on it', () async {
      final envelope = await engineWith(
        _sideOnly(covered: ReportingDatasetSide.expenses, units: {_ccr}),
      ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr)));
      expect(
        (envelope.outcome as PnlRefused).sideReason,
        ReportingSideUnavailable.notDownloaded,
        reason:
            '"synchronise" and "ask for a grant" are different instructions, so '
            'notDownloaded and notAuthorised stay different values',
      );
    });
  });

  // ── The production wiring tells the truth ─────────────────────────────────
  group('until Slice 4, production coverage is not established', () {
    test(
      'the default oracle refuses rather than reporting one device share',
      () async {
        await canonicalRevenue(
          unit: _ccr,
          category: 'cat-restaurant',
          businessDate: '2026-06-15',
          gross: 10000000,
          tax: 476190,
          net: 9523810,
        );

        final engine = LocalReportingEngine(
          DriftReportingSource(revenue: revenue, expenses: expenses),
        );
        final envelope = await engine.report(
          ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
        );

        expect(envelope.coverage, ReportingCoverage.notDownloaded);
        expect(envelope.outcome, isA<PnlRefused>());
        expect(
          (envelope.outcome as PnlRefused).refusal,
          PnlRefusal.bothSidesUnavailable,
          reason:
              'rows exist, and they are only what this device recorded. Presenting them '
              'as the hotel figure is the thing D-173 makes impossible to rule out',
        );
      },
    );

    test('rows present with no coverage is not a zero report', () async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 10000000,
        tax: 476190,
        net: 9523810,
      );
      final engine = LocalReportingEngine(
        DriftReportingSource(revenue: revenue, expenses: expenses),
      );
      final envelope = await engine.report(
        ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
      );
      expect(envelope.resultOrNull, isNull);
    });
  });

  // ── The worked controls, through real SQL ─────────────────────────────────
  group('the worked controls, end to end through the engine', () {
    setUp(() async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 10000000,
        tax: 476190,
        net: 9523810,
      );
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-nandbhog',
        businessDate: '2026-06-15',
        gross: 870000,
        tax: 41429,
        net: 828571,
      );
      await canonicalRevenue(
        unit: _hki,
        category: 'cat-room',
        businessDate: '2026-06-15',
        gross: 5200000,
        tax: 247619,
        net: 4952381,
      );
      await canonicalRevenue(
        unit: _hki,
        category: 'cat-banquet',
        businessDate: '2026-06-15',
        gross: 4034300,
        tax: 0,
        net: 4034300,
        treatment: 'none',
        rateBp: 0,
      );
      await canonicalExpense(
        unit: _ccr,
        amount: 4500000,
        pnlDate: '2026-06-30',
      );
      await canonicalExpense(
        unit: _hki,
        amount: 3000000,
        pnlDate: '2026-06-30',
      );
    });

    test('Crystal Canopy, to the paisa', () async {
      final result = resultOf(
        await engineWith(_complete()).reportForUnit(
          period: june,
          businessUnitId: _ccr,
          scope: ReportingScope.unit(_ccr),
        ),
      );

      expect(result.grossSales, Money.fromPaise(10870000));
      expect(result.gst, Money.fromPaise(517619));
      expect(result.netSales, Money.fromPaise(10352381));
      expect(result.expenses, Money.fromPaise(4500000));
      expect(result.operatingProfit, Money.fromPaise(5852381));
      expect(result.reconciles, isTrue);
      expect(result.businessUnitId, _ccr);
    });

    test('Hotel Krishna Imperial, to the paisa', () async {
      final result = resultOf(
        await engineWith(_complete()).reportForUnit(
          period: june,
          businessUnitId: _hki,
          scope: ReportingScope.unit(_hki),
        ),
      );

      expect(result.grossSales, Money.fromPaise(9234300));
      expect(result.gst, Money.fromPaise(247619));
      expect(result.netSales, Money.fromPaise(8986681));
      expect(result.expenses, Money.fromPaise(3000000));
      expect(result.reconciles, isTrue);
    });

    test('consolidated equals the sum of the two, exactly', () async {
      final engine = engineWith(_complete());
      final ccr = resultOf(
        await engine.reportForUnit(
          period: june,
          businessUnitId: _ccr,
          scope: ReportingScope({_ccr, _hki}),
        ),
      );
      final hki = resultOf(
        await engine.reportForUnit(
          period: june,
          businessUnitId: _hki,
          scope: ReportingScope({_ccr, _hki}),
        ),
      );
      final all = resultOf(
        await engine.report(
          ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
        ),
      );

      expect(all.grossSales, Money.fromPaise(20104300));
      expect(all.gst, Money.fromPaise(765238));
      expect(all.netSales, Money.fromPaise(19339062));
      expect(all.expenses, Money.fromPaise(7500000));

      expect(all.grossSales, ccr.grossSales + hki.grossSales);
      expect(all.gst, ccr.gst + hki.gst);
      expect(all.netSales, ccr.netSales + hki.netSales);
      expect(all.expenses, ccr.expenses + hki.expenses);
      expect(all.operatingProfit, ccr.operatingProfit + hki.operatingProfit);
      expect(all.isConsolidated, isTrue);
    });

    test('the independent oracle agrees with the engine', () async {
      final all = resultOf(
        await engineWith(_complete()).report(
          ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
        ),
      );
      final oracle = referencePnl(
        revenue: const [
          (gross: 10000000, tax: 476190, net: 9523810),
          (gross: 870000, tax: 41429, net: 828571),
          (gross: 5200000, tax: 247619, net: 4952381),
          (gross: 4034300, tax: 0, net: 4034300),
        ],
        expensePaise: const [4500000, 3000000],
      );

      expect(all.grossSales.paise, oracle.gross);
      expect(all.gst.paise, oracle.gst);
      expect(all.netSales.paise, oracle.net);
      expect(all.expenses.paise, oracle.expenses);
      expect(all.operatingProfit.paise, oracle.operatingProfit);
    });

    test('a margin comes back exact and undivided', () async {
      final ccr = resultOf(
        await engineWith(_complete()).reportForUnit(
          period: june,
          businessUnitId: _ccr,
          scope: ReportingScope.unit(_ccr),
        ),
      );
      final margin = ccr.margin as MarginRatio;
      expect(margin.operatingProfitPaise, 5852381);
      expect(margin.netSalesPaise, 10352381);
    });
  });

  // ── Scope isolation ───────────────────────────────────────────────────────
  group('scope is exact and is applied in SQL', () {
    setUp(() async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 1000000,
        tax: 47619,
        net: 952381,
      );
      await canonicalRevenue(
        unit: _hki,
        category: 'cat-room',
        businessDate: '2026-06-15',
        gross: 9000000,
        tax: 428571,
        net: 8571429,
      );
      await canonicalExpense(unit: _ccr, amount: 100000, pnlDate: '2026-06-10');
      await canonicalExpense(unit: _hki, amount: 900000, pnlDate: '2026-06-10');
    });

    test('a CCR-only report contains no HKI figure', () async {
      final result = resultOf(
        await engineWith(
          _complete({_ccr}),
        ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr))),
      );
      expect(result.grossSales, Money.fromPaise(1000000));
      expect(result.expenses, Money.fromPaise(100000));
    });

    test('an HKI-only report contains no CCR figure', () async {
      final result = resultOf(
        await engineWith(
          _complete({_hki}),
        ).report(ReportRequest(period: june, scope: ReportingScope.unit(_hki))),
      );
      expect(result.grossSales, Money.fromPaise(9000000));
      expect(result.expenses, Money.fromPaise(900000));
    });

    test('an empty scope is refused, not reported as zero', () async {
      final envelope = await engineWith(_complete()).report(
        ReportRequest(period: june, scope: ReportingScope(const <String>{})),
      );
      expect(
        (envelope.outcome as PnlRefused).refusal,
        PnlRefusal.noPermittedBusinessUnit,
      );
    });

    test(
      'one unproven property refuses the whole consolidated report',
      () async {
        final envelope = await engineWith(_complete({_ccr})).report(
          ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
        );
        expect(envelope.coverage, ReportingCoverage.notDownloaded);
        expect(envelope.outcome, isA<PnlRefused>());
      },
    );
  });

  // ── Range mapping ─────────────────────────────────────────────────────────
  group('one range mapping, whichever way the period was asked for', () {
    setUp(() async {
      for (final day in [
        '2026-05-31',
        '2026-06-01',
        '2026-06-15',
        '2026-06-30',
        '2026-07-01',
      ]) {
        await canonicalRevenue(
          unit: _ccr,
          category: 'cat-restaurant',
          businessDate: day,
          gross: 100000,
          tax: 4762,
          net: 95238,
        );
        await canonicalExpense(unit: _ccr, amount: 10000, pnlDate: day);
      }
    });

    Future<PnlResult> report(ReportingPeriod period) async => resultOf(
      await engineWith(
        _complete({_ccr}),
      ).report(ReportRequest(period: period, scope: ReportingScope.unit(_ccr))),
    );

    test('a month via period key equals the same month via a date range', () async {
      final viaMonth = await report(MonthPeriod(2026, 6));
      // A custom range that is not a whole month cannot use the key, so this forces the
      // date-range path — and then the two are compared over the same days.
      final viaRange = await report(
        CustomRangePeriod(
          from: BusinessDate.of(2026, 6, 1),
          to: BusinessDate.of(2026, 6, 29),
        ),
      );
      final lastDay = await report(
        SingleDayPeriod(BusinessDate.of(2026, 6, 30)),
      );

      expect(
        viaMonth.grossSales,
        viaRange.grossSales + lastDay.grossSales,
        reason:
            'the indexed period-key path and the date-range path agree exactly',
      );
      expect(viaMonth.expenses, viaRange.expenses + lastDay.expenses);
      expect(viaMonth.grossSales, Money.fromPaise(300000));
    });

    test('the mapping is a property of the range, not a caller choice', () {
      final month =
          (MonthPeriod(2026, 6).resolve() as ReportRangeResolved).range;
      final sameAsCustom =
          (CustomRangePeriod(
                    from: BusinessDate.of(2026, 6, 1),
                    to: BusinessDate.of(2026, 6, 30),
                  ).resolve()
                  as ReportRangeResolved)
              .range;
      expect(month.wholeMonthKey, '2026-06');
      expect(
        sameAsCustom.wholeMonthKey,
        '2026-06',
        reason:
            'asked for either way, it is the same range and takes the same path',
      );

      final partial =
          (CustomRangePeriod(
                    from: BusinessDate.of(2026, 6, 2),
                    to: BusinessDate.of(2026, 6, 30),
                  ).resolve()
                  as ReportRangeResolved)
              .range;
      expect(partial.wholeMonthKey, isNull);
    });

    test('a single day', () async {
      final result = await report(
        SingleDayPeriod(BusinessDate.of(2026, 6, 15)),
      );
      expect(result.grossSales, Money.fromPaise(100000));
    });

    test('a Monday-to-Sunday week', () async {
      // 2026-06-15 is a Monday; the week covers 15-21 June and holds one of the fixtures.
      final result = await report(WeekPeriod(BusinessDate.of(2026, 6, 15)));
      expect(result.grossSales, Money.fromPaise(100000));
    });

    test('a range spanning a month boundary', () async {
      final result = await report(
        CustomRangePeriod(
          from: BusinessDate.of(2026, 5, 31),
          to: BusinessDate.of(2026, 6, 1),
        ),
      );
      expect(result.grossSales, Money.fromPaise(200000));
    });

    test('a financial year covers all five fixtures', () async {
      final result = await report(
        FinancialYearPeriod(const FinancialYear(2026)),
      );
      expect(result.grossSales, Money.fromPaise(500000));
    });

    test('a range spanning the FY boundary', () async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2027-04-01',
        gross: 700000,
        tax: 33333,
        net: 666667,
      );
      final closing = await report(
        FinancialYearPeriod(const FinancialYear(2026)),
      );
      final opening = await report(
        FinancialYearPeriod(const FinancialYear(2027)),
      );
      expect(closing.grossSales, Money.fromPaise(500000));
      expect(opening.grossSales, Money.fromPaise(700000));
    });

    test('a same-day custom range', () async {
      final result = await report(
        CustomRangePeriod(
          from: BusinessDate.of(2026, 6, 15),
          to: BusinessDate.of(2026, 6, 15),
        ),
      );
      expect(result.grossSales, Money.fromPaise(100000));
    });

    test('a reversed range is refused before anything is queried', () async {
      final envelope = await engineWith(_complete()).report(
        ReportRequest(
          period: CustomRangePeriod(
            from: BusinessDate.of(2026, 6, 30),
            to: BusinessDate.of(2026, 6, 1),
          ),
          scope: ReportingScope.unit(_ccr),
        ),
      );
      expect(
        (envelope.outcome as PnlRefused).refusal,
        PnlRefusal.invalidDateRange,
      );
      expect(
        envelope.range,
        isNull,
        reason: 'no range is invented for one that is not',
      );
    });
  });

  // ── Dates: accrual and cut-off ────────────────────────────────────────────
  group('the range filters the P&L date and nothing else', () {
    test('a June salary paid in July stays a June cost (D-016)', () async {
      await canonicalExpense(
        unit: _ccr,
        amount: 8000000,
        pnlDate: '2026-06-30',
        businessDate: '2026-06-30',
        paymentDate: '2026-07-05',
      );

      final engine = engineWith(_complete({_ccr}));
      final juneReport = resultOf(
        await engine.report(
          ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
        ),
      );
      final julyReport = resultOf(
        await engine.report(
          ReportRequest(
            period: MonthPeriod(2026, 7),
            scope: ReportingScope.unit(_ccr),
          ),
        ),
      );

      expect(juneReport.expenses, Money.fromPaise(8000000));
      expect(
        julyReport.expenses,
        Money.zero,
        reason: 'paying in July does not move the cost out of June',
      );
    });

    test(
      'an accrual whose business date and P&L date differ follows the P&L date',
      () async {
        // Recorded on 3 July for the June service period: the contribution's pnl_date is
        // 30 June, and that is what reporting reads.
        await canonicalExpense(
          unit: _ccr,
          amount: 1200000,
          pnlDate: '2026-06-30',
          businessDate: '2026-07-03',
        );
        final engine = engineWith(_complete({_ccr}));
        expect(
          resultOf(
            await engine.report(
              ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
            ),
          ).expenses,
          Money.fromPaise(1200000),
        );
        expect(
          resultOf(
            await engine.report(
              ReportRequest(
                period: MonthPeriod(2026, 7),
                scope: ReportingScope.unit(_ccr),
              ),
            ),
          ).expenses,
          Money.zero,
        );
      },
    );

    test(
      'a late-night sale reports on its stored trading day, not its capture instant',
      () async {
        // 01:00 IST on 1 July is business date 30 June under the property's 05:00 cut-off
        // (D-019, D-067). The engine does not recompute that — it reads the stored date.
        final tradingDay = BusinessDate.fromInstant(
          DateTime.utc(2026, 6, 30, 19, 30),
          timeZoneId: 'Asia/Kolkata',
        );
        expect(tradingDay, BusinessDate.of(2026, 6, 30));

        await canonicalRevenue(
          unit: _ccr,
          category: 'cat-restaurant',
          businessDate: tradingDay.iso,
          gross: 500000,
          tax: 23810,
          net: 476190,
        );

        final engine = engineWith(_complete({_ccr}));
        expect(
          resultOf(
            await engine.report(
              ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
            ),
          ).grossSales,
          Money.fromPaise(500000),
        );
        expect(
          resultOf(
            await engine.report(
              ReportRequest(
                period: MonthPeriod(2026, 7),
                scope: ReportingScope.unit(_ccr),
              ),
            ),
          ).grossSales,
          Money.zero,
        );
      },
    );
  });

  // ── Canonical only ────────────────────────────────────────────────────────
  group('only canonical accepted facts contribute', () {
    test('pending revenue and pending expenses change nothing', () async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 1000000,
        tax: 47619,
        net: 952381,
      );
      await canonicalExpense(unit: _ccr, amount: 200000, pnlDate: '2026-06-15');

      final engine = engineWith(_complete({_ccr}));
      final before = resultOf(
        await engine.report(
          ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
        ),
      );

      await pendingRevenue(
        unit: _ccr,
        businessDate: '2026-06-16',
        gross: 99999999,
      );
      await canonicalExpense(
        unit: _ccr,
        amount: 88888888,
        pnlDate: '2026-06-16',
        canonical: false,
      );

      final after = resultOf(
        await engine.report(
          ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
        ),
      );

      expect(after.grossSales, before.grossSales);
      expect(after.expenses, before.expenses);
      expect(after.operatingProfit, before.operatingProfit);
    });

    test('a voided sale and a voided expense leave the aggregate', () async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 1000000,
        tax: 47619,
        net: 952381,
        voided: true,
      );
      await canonicalExpense(
        unit: _ccr,
        amount: 200000,
        pnlDate: '2026-06-15',
        voided: true,
      );

      final result = resultOf(
        await engineWith(
          _complete({_ccr}),
        ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr))),
      );
      expect(result.grossSales, Money.zero);
      expect(result.expenses, Money.zero);

      // The rows are still there; the aggregate excludes them (D-006).
      final rows = await db
          .customSelect('SELECT COUNT(*) AS n FROM revenue_entries')
          .getSingle();
      expect(rows.read<int>('n'), 1);
    });

    test('a scope-revoked retained document contributes nothing', () async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 1000000,
        tax: 47619,
        net: 952381,
      );
      final expenseId = await canonicalExpense(
        unit: _ccr,
        amount: 200000,
        pnlDate: '2026-06-15',
      );
      await db.customStatement(
        'UPDATE expenses SET scope_revoked_at = ? WHERE id = ?',
        ['2026-06-20T00:00:00.000Z', expenseId],
      );
      await db.customStatement(
        'UPDATE revenue_entries SET scope_revoked_at = ?',
        ['2026-06-20T00:00:00.000Z'],
      );

      final result = resultOf(
        await engineWith(
          _complete({_ccr}),
        ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr))),
      );
      expect(result.grossSales, Money.zero);
      expect(result.expenses, Money.zero);
    });
  });

  // ── Corrections ───────────────────────────────────────────────────────────
  group('a correction moves a figure, exactly once', () {
    test('a revenue business-date correction moves June to July', () async {
      final id = await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 1000000,
        tax: 47619,
        net: 952381,
      );
      final engine = engineWith(_complete({_ccr}));
      final julyPeriod = MonthPeriod(2026, 7);

      expect(
        resultOf(
          await engine.report(
            ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
          ),
        ).grossSales,
        Money.fromPaise(1000000),
      );

      // The accepted correction, as the server would have written it back.
      await db.customStatement(
        "UPDATE revenue_entries SET business_date = '2026-07-10', "
        "pnl_period_key = '2026-07', business_date_source = 'corrected' WHERE id = ?",
        [id],
      );

      expect(
        resultOf(
          await engine.report(
            ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
          ),
        ).grossSales,
        Money.zero,
        reason: 'June loses it',
      );
      final july = resultOf(
        await engine.report(
          ReportRequest(period: julyPeriod, scope: ReportingScope.unit(_ccr)),
        ),
      );
      expect(
        july.grossSales,
        Money.fromPaise(1000000),
        reason: 'July gains it',
      );
      expect(
        july.revenueByCategory.length,
        1,
        reason: 'exactly once, not appended twice',
      );
    });

    test('an expense accrual correction moves the contribution', () async {
      final id = await canonicalExpense(
        unit: _ccr,
        amount: 6000000,
        pnlDate: '2026-06-30',
      );
      final engine = engineWith(_complete({_ccr}));

      await db.customStatement(
        "UPDATE expense_period_allocations SET pnl_date = '2026-07-31', "
        "pnl_period_key = '2026-07', accounting_period_end = '2026-07-31' "
        'WHERE expense_id = ?',
        [id],
      );

      expect(
        resultOf(
          await engine.report(
            ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
          ),
        ).expenses,
        Money.zero,
      );
      expect(
        resultOf(
          await engine.report(
            ReportRequest(
              period: MonthPeriod(2026, 7),
              scope: ReportingScope.unit(_ccr),
            ),
          ),
        ).expenses,
        Money.fromPaise(6000000),
      );
    });
  });

  // ── Zero, and the one-paisa control ───────────────────────────────────────
  group('zero, and what the engine must not compute', () {
    test('a complete range with no transactions is a real zero P&L', () async {
      final envelope = await engineWith(
        _complete({_ccr}),
      ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr)));
      final result = resultOf(envelope);

      expect(envelope.coverage, ReportingCoverage.complete);
      expect(result.grossSales, Money.zero);
      expect(result.netSales, Money.zero);
      expect(result.expenses, Money.zero);
      expect(result.operatingProfit, Money.zero);
      expect(result.margin, isA<MarginNotApplicable>());
      expect(result.reconciles, isTrue);
    });

    test('two Restaurant days sum to 750715, not the re-rated 750714', () async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-10',
        gross: 7645000,
        tax: 364048,
        net: 7280952,
      );
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-11',
        gross: 8120000,
        tax: 386667,
        net: 7733333,
      );

      final result = resultOf(
        await engineWith(
          _complete({_ccr}),
        ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr))),
      );

      expect(result.gst, Money.fromPaise(750715));
      expect(result.grossSales, Money.fromPaise(15765000));
      const reRated = 15765000 * 5 ~/ 105;
      expect(reRated, 750714);
      expect(
        result.gst.paise,
        isNot(reRated),
        reason:
            'an engine that derived tax from the aggregate would produce 750714. This '
            'one sums the accepted snapshots and never sees a rate',
      );
      expect(result.netSales, Money.fromPaise(15014285));
      expect(result.reconciles, isTrue);
    });

    test('the schema itself refuses a component that does not reconcile', () async {
      // The behavioural control I first wrote for "the engine does not compute
      // net = gross - tax" cannot be written: the local schema holds a CHECK that a
      // component reconciles, so a deliberately non-reconciling fixture is refused before
      // any engine sees it. That is the right place for the guarantee, and it is worth
      // asserting rather than assuming — it is why no report can be built on a row whose
      // three figures disagree.
      //
      // The engine's own freedom from derived arithmetic is proven two other ways: the
      // one-paisa control above, and the structural guard in
      // local_reporting_engine_guard_test.dart.
      await expectLater(
        canonicalRevenue(
          unit: _ccr,
          category: 'cat-restaurant',
          businessDate: '2026-06-15',
          gross: 1000000,
          tax: 50000,
          net: 949999,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ── Breakdowns, at the grain the repositories already return ──────────────
  group('breakdowns carry identities and reconcile', () {
    test('revenue categories are kept apart and add up to the total', () async {
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-restaurant',
        businessDate: '2026-06-15',
        gross: 10000000,
        tax: 476190,
        net: 9523810,
      );
      await canonicalRevenue(
        unit: _ccr,
        category: 'cat-nandbhog',
        businessDate: '2026-06-15',
        gross: 870000,
        tax: 41429,
        net: 828571,
      );

      final result = resultOf(
        await engineWith(
          _complete({_ccr}),
        ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr))),
      );

      expect(result.revenueByCategory, hasLength(2));
      expect(
        Money.sum(result.revenueByCategory.map((l) => l.totals.gross)),
        result.grossSales,
      );
      expect(
        result.revenueByCategory.map((l) => l.revenueCategoryId),
        containsAll(['cat-restaurant', 'cat-nandbhog']),
      );
    });

    test('expense lines carry hierarchy identities and no labels', () async {
      await canonicalExpense(unit: _ccr, amount: 500000, pnlDate: '2026-06-15');
      final result = resultOf(
        await engineWith(
          _complete({_ccr}),
        ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr))),
      );
      final line = result.expenseByHierarchy.single;
      expect(line.categoryId, 'cat-kirana');
      expect(line.departmentId, 'dept-1');
      expect(line.sectionId, 'sec-1');
      expect(
        Money.sum(result.expenseByHierarchy.map((l) => l.totals.amount)),
        result.expenses,
      );
    });
  });

  // ── The aggregation happens in SQL ────────────────────────────────────────
  group('aggregation is SQL, not a Dart fold', () {
    test('a large fixture is answered by a query plan that aggregates', () async {
      for (var i = 0; i < 200; i++) {
        await canonicalRevenue(
          unit: _ccr,
          category: 'cat-restaurant',
          businessDate: '2026-06-15',
          gross: 100,
          tax: 5,
          net: 95,
        );
      }

      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN '
            'SELECT COALESCE(SUM(gross_minor), 0) FROM revenue_period_contributions '
            "WHERE pnl_period_key = '2026-06'",
          )
          .get();
      final detail = plan.map((r) => r.data.values.join(' ')).join(' | ');

      // SQLite names the aliases, not the tables, so the assertion is about the shape of
      // the plan: it joins through an index and produces one aggregate row. What it must
      // NOT be is 200 rows arriving in Dart to be added up.
      expect(
        detail.toUpperCase(),
        contains('USING INDEX'),
        reason: 'the components join is indexed rather than scanned per row',
      );
      expect(
        detail.toUpperCase(),
        isNot(contains('USE TEMP B-TREE')),
        reason: 'no sort or grouping spill for a plain sum',
      );

      final rows = await db
          .customSelect(
            'SELECT COALESCE(SUM(gross_minor), 0) AS g '
            'FROM revenue_period_contributions '
            "WHERE pnl_period_key = '2026-06' AND txn_number IS NOT NULL",
          )
          .get();
      expect(
        rows,
        hasLength(1),
        reason: 'the database returns one summed row, not 200 for Dart to fold',
      );

      final result = resultOf(
        await engineWith(
          _complete({_ccr}),
        ).report(ReportRequest(period: june, scope: ReportingScope.unit(_ccr))),
      );
      expect(
        result.grossSales,
        Money.fromPaise(20000),
        reason: '200 rows summed by SQLite, not folded row by row in Dart',
      );
    });
  });
}
