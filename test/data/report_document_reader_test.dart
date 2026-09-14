/// Opening a document from a report: fetched, compared with the cached row, held in memory
/// (Phase 5 Slice 10, D-233).
///
/// The gateways are substituted at the transport, and every write method they have is made
/// to fail the test if it is ever called — the reader reads projections and nothing else.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/report_document_reader.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/expenses/expense_document_detail.dart';
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

SupabaseClient _client() => SupabaseClient(
  'http://localhost',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

typedef Answer<T> = RemoteOutcome<T>;

Never _write(String what) => fail('the reader must never call $what');

final class _Revenue extends RevenueGateway {
  _Revenue() : super(_client());

  Answer<Map<String, dynamic>?> document = const RemoteOk(null);
  Answer<List<Map<String, dynamic>>> components = const RemoteOk([]);
  Answer<List<Map<String, dynamic>>> attachments = const RemoteOk([]);
  final asked = <String>[];

  @override
  Future<RemoteOutcome<Map<String, dynamic>?>> fetchDocument(String id) async {
    asked.add('document:$id');
    return document;
  }

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchComponents(
    String entryId,
  ) async => components;

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchAttachments(
    String entryId,
  ) async => attachments;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required Map<String, Object?> arguments,
    required String mutationId,
  }) => _write('revenue_create');

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> update({
    required Map<String, Object?> arguments,
    required int baseRowVersion,
    required String mutationId,
  }) => _write('revenue_update');

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> voidEntry({
    required String entryId,
    required int baseRowVersion,
    required String reason,
    required String mutationId,
  }) => _write('revenue_void');
}

final class _Expenses extends ExpenseGateway {
  _Expenses() : super(_client());

  Answer<Map<String, dynamic>?> document = const RemoteOk(null);
  Answer<List<Map<String, dynamic>>> allocations = const RemoteOk([]);
  Answer<List<Map<String, dynamic>>> periods = const RemoteOk([]);
  Answer<List<Map<String, dynamic>>> attachments = const RemoteOk([]);

  @override
  Future<RemoteOutcome<Map<String, dynamic>?>> fetchDocument(
    String expenseId,
  ) async => document;

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchAllocations(
    String expenseId,
  ) async => allocations;

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchPeriodContributions(
    String expenseId,
  ) async => periods;

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchAttachments(
    String expenseId,
  ) async => attachments;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required Map<String, Object?> arguments,
    required String mutationId,
  }) => _write('expense_create');

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> update({
    required Map<String, Object?> arguments,
    required int baseRowVersion,
    required String mutationId,
  }) => _write('expense_update');

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> voidExpense({
    required String expenseId,
    required int baseRowVersion,
    required String reason,
    required String mutationId,
  }) => _write('expense_void');
}

void main() {
  late _Revenue revenue;
  late _Expenses expenses;
  late ReportDocumentReader reader;

  final june =
      (CustomRangePeriod(
                from: BusinessDate.of(2026, 6, 1),
                to: BusinessDate.of(2026, 6, 30),
              ).resolve()
              as ReportRangeResolved)
          .range;

  setUp(() {
    revenue = _Revenue();
    expenses = _Expenses();
    reader = ReportDocumentReader(expenses: expenses, revenue: revenue);
  });

  // ── Revenue ─────────────────────────────────────────────────────────────

  final saleLine = RevenueDocumentLine(
    businessUnitId: 'ccr',
    revenueCategoryId: 'restaurant',
    revenueEntryId: 're-1',
    pnlDate: BusinessDate.of(2026, 6, 15),
    totals: RevenueTotals(
      gross: Money.fromPaise(10000000),
      tax: Money.fromPaise(476190),
      net: Money.fromPaise(9523810),
      contributions: 1,
    ),
  );

  Map<String, dynamic> saleHeader({
    String date = '2026-06-15',
    Object? voidedAt,
  }) => {
    'id': 're-1',
    'org_id': 'org',
    'txn_number': 'KI-REV-26-27-000123',
    'business_unit_id': 'ccr',
    'revenue_category_id': 'restaurant',
    'business_date': date,
    'entry_kind': 'daily_summary',
    'notes': 'Dinner service',
    'created_by': 'user-a',
    'created_at': '2026-06-15T18:00:00Z',
    'voided_at': voidedAt,
    'row_version': 2,
    'business_date_source': 'derived',
  };

  Map<String, dynamic> component({int gross = 10000000, int tax = 476190}) => {
    'id': 'rc-1',
    'revenue_entry_id': 're-1',
    'entered_amount_minor': gross,
    'entered_basis': 'inclusive_total',
    'gross_amount_minor': gross,
    'tax_amount_minor': tax,
    'net_amount_minor': gross - tax,
    'tax_rule_id': 'rule-1',
    'tax_rate_bp': 500,
    'tax_treatment': 'inclusive',
  };

  group('a revenue document', () {
    test(
      'matching the cached row is ready, with its number and components',
      () async {
        revenue
          ..document = RemoteOk(saleHeader())
          ..components = RemoteOk([component()])
          ..attachments = const RemoteOk([
            {
              'id': 'att-1',
              'file_name': 'z-report.jpg',
              'content_type': 'image/jpeg',
              'byte_size': 1024,
              'content_hash': 'abc',
            },
          ]);
        final outcome = await reader.revenueFor(saleLine, range: june);
        expect(outcome, isA<ReportDocumentReady<RevenueEntry>>());
        final entry = (outcome as ReportDocumentReady<RevenueEntry>).document;
        expect(entry.txnNumber, 'KI-REV-26-27-000123');
        expect(entry.gross.paise, 10000000);
        expect(entry.attachments.single.fileName, 'z-report.jpg');
      },
    );

    test(
      'a corrected amount is a changed transaction, not fresher figures',
      () async {
        revenue
          ..document = RemoteOk(saleHeader())
          ..components = RemoteOk([component(gross: 10000100, tax: 476195)]);
        expect(
          await reader.revenueFor(saleLine, range: june),
          isA<ReportDocumentChanged<RevenueEntry>>(),
        );
      },
    );

    test('a void or a moved business date is a changed transaction', () async {
      revenue
        ..document = RemoteOk(saleHeader(voidedAt: '2026-06-20T00:00:00Z'))
        ..components = RemoteOk([component()]);
      expect(
        await reader.revenueFor(saleLine, range: june),
        isA<ReportDocumentChanged<RevenueEntry>>(),
      );
      revenue.document = RemoteOk(saleHeader(date: '2026-07-01'));
      expect(
        await reader.revenueFor(saleLine, range: june),
        isA<ReportDocumentChanged<RevenueEntry>>(),
      );
    });

    test('withheld by the server is not available to this person', () async {
      revenue.document = const RemoteOk(null);
      expect(
        await reader.revenueFor(saleLine, range: june),
        isA<ReportDocumentNotAvailable<RevenueEntry>>(),
      );
    });

    test('no answer is detail not downloaded', () async {
      revenue.document = const RemoteUnreachable(RemoteFailure.offline);
      expect(
        await reader.revenueFor(saleLine, range: june),
        isA<ReportDocumentNotDownloaded<RevenueEntry>>(),
      );
      revenue
        ..document = RemoteOk(saleHeader())
        ..components = const RemoteUnreachable(RemoteFailure.offline);
      expect(
        await reader.revenueFor(saleLine, range: june),
        isA<ReportDocumentNotDownloaded<RevenueEntry>>(),
      );
    });

    test(
      'a figure that is not integer paise is refused, never rounded',
      () async {
        revenue
          ..document = RemoteOk(saleHeader())
          ..components = RemoteOk([
            component()..['gross_amount_minor'] = 10000000.0,
          ]);
        expect(
          await reader.revenueFor(saleLine, range: june),
          isA<ReportDocumentChanged<RevenueEntry>>(),
        );
      },
    );
  });

  // ── Expenses ────────────────────────────────────────────────────────────

  final costLine = ExpenseDocumentLine(
    businessUnitId: 'ccr',
    departmentId: 'util',
    sectionId: 'power',
    categoryId: 'elec',
    expenseId: 'ex-1',
    firstPnlDate: BusinessDate.of(2026, 6, 18),
    lastPnlDate: BusinessDate.of(2026, 6, 18),
    totals: ExpenseTotals(amount: Money.fromPaise(2500000), contributions: 1),
  );

  Map<String, dynamic> costHeader({required bool complete, Object? voidedAt}) =>
      {
        'id': 'ex-1',
        'org_id': 'org',
        'txn_number': 'KI-EXP-26-27-000077',
        'business_date': '2026-06-18',
        'payment_status': 'unpaid',
        'created_by': 'user-a',
        'captured_at': '2026-06-18T09:00:00Z',
        'row_version': 1,
        'voided_at': voidedAt,
        'visible_amount_minor': complete ? 5800000 : 2500000,
        'is_complete': complete,
        'total_amount_minor': complete ? 5800000 : null,
      };

  Map<String, dynamic> line(String unit, int paise, String id) => {
    'id': id,
    'business_unit_id': unit,
    'category_label': 'Electricity',
    'amount_minor': paise,
  };

  Map<String, dynamic> period(String unit, int paise, String allocation) => {
    'allocation_id': allocation,
    'business_unit_id': unit,
    'department_id': 'util',
    'section_id': 'power',
    'category_id': 'elec',
    'pnl_date': '2026-06-18',
    'pnl_period_key': '2026-06',
    'amount_minor': paise,
    'is_derived': true,
  };

  group('an expense document', () {
    test(
      'a scoped reader sees their allocation, and it explains the row',
      () async {
        expenses
          ..document = RemoteOk(costHeader(complete: false))
          ..allocations = RemoteOk([line('ccr', 2500000, 'al-1')])
          ..periods = RemoteOk([period('ccr', 2500000, 'al-1')]);
        final outcome = await reader.expenseFor(costLine, range: june);
        expect(outcome, isA<ReportDocumentReady<ExpenseDocumentDetail>>());
        final detail =
            (outcome as ReportDocumentReady<ExpenseDocumentDetail>).document;
        expect(detail.isScoped, isTrue);
        expect(detail.visibleAmount.paise, 2500000);
        expect(detail.txnNumber, 'KI-EXP-26-27-000077');
        expect(detail.allocations.single.businessUnitId, 'ccr');
      },
    );

    test(
      'an unscoped reader sees the whole bill; the row is still its share',
      () async {
        expenses
          ..document = RemoteOk(costHeader(complete: true))
          ..allocations = RemoteOk([
            line('ccr', 2500000, 'al-1'),
            line('hki', 3300000, 'al-2'),
          ])
          ..periods = RemoteOk([
            period('ccr', 2500000, 'al-1'),
            period('hki', 3300000, 'al-2'),
          ]);
        final outcome = await reader.expenseFor(costLine, range: june);
        final detail =
            (outcome as ReportDocumentReady<ExpenseDocumentDetail>).document;
        expect(detail.isScoped, isFalse);
        expect(detail.visibleAmount.paise, 5800000);
      },
    );

    test('a re-apportioned or voided bill is a changed transaction', () async {
      expenses
        ..document = RemoteOk(costHeader(complete: false))
        ..allocations = RemoteOk([line('ccr', 2000000, 'al-1')])
        ..periods = RemoteOk([period('ccr', 2000000, 'al-1')]);
      expect(
        await reader.expenseFor(costLine, range: june),
        isA<ReportDocumentChanged<ExpenseDocumentDetail>>(),
      );
      expenses
        ..document = RemoteOk(
          costHeader(complete: false, voidedAt: '2026-06-20T00:00:00Z'),
        )
        ..periods = RemoteOk([period('ccr', 2500000, 'al-1')]);
      expect(
        await reader.expenseFor(costLine, range: june),
        isA<ReportDocumentChanged<ExpenseDocumentDetail>>(),
      );
    });

    test('withheld is not available; no answer is not downloaded', () async {
      expenses.document = const RemoteOk(null);
      expect(
        await reader.expenseFor(costLine, range: june),
        isA<ReportDocumentNotAvailable<ExpenseDocumentDetail>>(),
      );
      expenses.document = const RemoteUnreachable(
        RemoteFailure.serverUnreachable,
      );
      expect(
        await reader.expenseFor(costLine, range: june),
        isA<ReportDocumentNotDownloaded<ExpenseDocumentDetail>>(),
      );
      expenses
        ..document = RemoteOk(costHeader(complete: false))
        ..periods = const RemoteUnreachable(RemoteFailure.offline);
      expect(
        await reader.expenseFor(costLine, range: june),
        isA<ReportDocumentNotDownloaded<ExpenseDocumentDetail>>(),
      );
    });
  });
}
