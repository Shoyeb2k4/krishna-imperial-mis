/// Substitute transports for opening a document from a report (Phase 5 Slice 10).
///
/// Only the network is replaced. The reader, the providers, the drill-down and the bodies
/// behind these are the production ones. Every write method fails the test if called.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

SupabaseClient _client() => SupabaseClient(
  'http://localhost',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

Never _write(String what) => fail('report detail must never call $what');

final class FakeRevenueDocuments extends RevenueGateway {
  FakeRevenueDocuments() : super(_client());

  final documents = <String, Map<String, dynamic>>{};
  final components = <String, List<Map<String, dynamic>>>{};
  final attachments = <String, List<Map<String, dynamic>>>{};
  bool offline = false;
  int reads = 0;

  /// A canonical sale document for a reporting fixture row, as the projections state it.
  void addFromSale(Map<String, dynamic> row, {String? txnNumber}) {
    final id = row['revenue_entry_id'] as String;
    documents[id] = {
      'id': id,
      'org_id': 'test-org',
      'txn_number':
          txnNumber ?? 'KI-REV-26-27-${id.hashCode.abs() % 900000 + 100000}',
      'business_unit_id': row['business_unit_id'],
      'revenue_category_id': row['revenue_category_id'],
      'business_date': row['pnl_date'],
      'entry_kind': 'daily_summary',
      'notes': 'Dinner service',
      'created_by': 'user-a',
      'created_at': '${row['pnl_date']}T18:00:00Z',
      'voided_at': null,
      'row_version': 1,
      'business_date_source': 'derived',
    };
    (components[id] ??= []).add({
      'id': row['id'],
      'revenue_entry_id': id,
      'entered_amount_minor': row['gross_minor'],
      'entered_basis': 'inclusive_total',
      'gross_amount_minor': row['gross_minor'],
      'tax_amount_minor': row['tax_minor'],
      'net_amount_minor': row['net_minor'],
      'tax_rule_id': 'rule-1',
      'tax_rate_bp': row['tax_rate_bp'],
      'tax_treatment': row['tax_treatment'],
    });
  }

  @override
  Future<RemoteOutcome<Map<String, dynamic>?>> fetchDocument(String id) async {
    reads++;
    if (offline) return const RemoteUnreachable(RemoteFailure.offline);
    return RemoteOk(documents[id]);
  }

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchComponents(
    String entryId,
  ) async => offline
      ? const RemoteUnreachable(RemoteFailure.offline)
      : RemoteOk(components[entryId] ?? const []);

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchAttachments(
    String entryId,
  ) async => offline
      ? const RemoteUnreachable(RemoteFailure.offline)
      : RemoteOk(attachments[entryId] ?? const []);

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

final class FakeExpenseDocuments extends ExpenseGateway {
  FakeExpenseDocuments() : super(_client());

  final documents = <String, Map<String, dynamic>>{};
  final allocations = <String, List<Map<String, dynamic>>>{};
  final periods = <String, List<Map<String, dynamic>>>{};
  bool offline = false;
  int reads = 0;

  /// A canonical expense for reporting fixture rows of one document. [complete] is whether
  /// this reader is given the whole bill (D-062); [visibleMinor] is what they may see.
  void addFromCosts(
    List<Map<String, dynamic>> rows, {
    required bool complete,
    required int visibleMinor,
    String? txnNumber,
  }) {
    final id = rows.first['expense_id'] as String;
    documents[id] = {
      'id': id,
      'org_id': 'test-org',
      'txn_number':
          txnNumber ?? 'KI-EXP-26-27-${id.hashCode.abs() % 900000 + 100000}',
      'business_date': rows.first['pnl_date'],
      'payment_status': 'unpaid',
      'reference_number': 'INV-42',
      'notes': 'Sharma Traders',
      'created_by': 'user-a',
      'captured_at': '${rows.first['pnl_date']}T09:00:00Z',
      'row_version': 1,
      'voided_at': null,
      'visible_amount_minor': visibleMinor,
      'is_complete': complete,
      'total_amount_minor': complete ? visibleMinor : null,
    };
    allocations[id] = [
      for (final row in rows)
        {
          'id': row['allocation_id'],
          'business_unit_id': row['business_unit_id'],
          'category_label': 'Kirana & Pulses',
          'amount_minor': row['amount_minor'],
        },
    ];
    periods[id] = [
      for (final row in rows)
        {
          'allocation_id': row['allocation_id'],
          'business_unit_id': row['business_unit_id'],
          'department_id': row['department_id'],
          'section_id': row['section_id'],
          'category_id': row['category_id'],
          'pnl_date': row['pnl_date'],
          'pnl_period_key': row['pnl_period_key'],
          'amount_minor': row['amount_minor'],
          'is_derived': true,
        },
    ];
  }

  @override
  Future<RemoteOutcome<Map<String, dynamic>?>> fetchDocument(
    String expenseId,
  ) async {
    reads++;
    if (offline) return const RemoteUnreachable(RemoteFailure.offline);
    return RemoteOk(documents[expenseId]);
  }

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchAllocations(
    String expenseId,
  ) async => offline
      ? const RemoteUnreachable(RemoteFailure.offline)
      : RemoteOk(allocations[expenseId] ?? const []);

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchPeriodContributions(
    String expenseId,
  ) async => offline
      ? const RemoteUnreachable(RemoteFailure.offline)
      : RemoteOk(periods[expenseId] ?? const []);

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchAttachments(
    String expenseId,
  ) async => offline
      ? const RemoteUnreachable(RemoteFailure.offline)
      : const RemoteOk([]);

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
