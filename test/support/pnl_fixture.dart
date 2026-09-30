/// Shared fixtures for the P&L surface tests, Windows and Android (Phase 5 Slices 8 and 9).
///
/// What is real behind these: the page, its providers, the master graph and business-day
/// rules read from SQLite, the canonical reporting cache, `ReportingSync`, `MarkerCoverage`,
/// `CachedReportingSource`, the local reporting engine and `Pnl.compute`.
///
/// What is substituted, and only this: the remote reporting transport ([FakeReportingGateway])
/// and the instant the surface treats as "now". A test never hands a widget a figure: every
/// paisa is synchronised into the cache and read back by the engine.
library;

import 'dart:async';

import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

import 'test_session.dart';

const pnlCcr = 'unit-ccr';
const pnlHki = 'unit-hki';
const pnlMe = 'user-me';

/// Saturday 19 September 2026, 21:00 UTC: 02:30 IST on the 20th. Crystal Canopy's 05:00
/// cut-off keeps it on the 19th; Hotel Krishna's midnight cut-off puts it on the 20th.
final pnlInstant = DateTime.utc(2026, 9, 19, 21);

final class FakeReportingGateway extends ReportingGateway {
  FakeReportingGateway()
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final revenue = <Map<String, dynamic>>[];
  final expense = <Map<String, dynamic>>[];
  RemoteFailure? snapshotUnreachable;
  RemoteFailure? newerUnreachable;
  Completer<void>? gate;
  final askedUnits = <Set<String>>[];
  int snapshots = 0;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
    List<int> financialYears = const [],
    ReportingPageCursor after = const ReportingPageCursor.start(),
    int pageDocuments = ReportingPageCursor.defaultPageDocuments,
  }) async {
    askedUnits.add(businessUnitIds.toSet());
    if (gate case final waiting?) await waiting.future;
    if (snapshotUnreachable case final failure?) {
      return RemoteUnreachable(failure);
    }
    snapshots++;
    List<Map<String, dynamic>> since(
      List<Map<String, dynamic>> rows,
      int generation,
    ) => [
      for (final row in rows)
        if ((row['change_seq'] as int) > generation &&
            businessUnitIds.contains(row['business_unit_id']))
          Map<String, dynamic>.from(row),
    ];
    return RemoteOk({
      'snapshot_id': 'snapshot-$snapshots',
      'server_time': '2026-09-19T20:30:00.000Z',
      'units': [
        for (final unit in businessUnitIds)
          {'business_unit_id': unit, 'reporting_authorised': true},
      ],
      'revenue': since(revenue, revenueSince),
      'expense': since(expense, expenseSince),
    });
  }

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> newerThan({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) async {
    if (newerUnreachable case final failure?) return RemoteUnreachable(failure);
    bool any(List<Map<String, dynamic>> rows, int generation) => rows.any(
      (r) =>
          (r['change_seq'] as int) > generation &&
          businessUnitIds.contains(r['business_unit_id']),
    );
    return RemoteOk({
      'server_time': '2026-09-19T20:31:00.000Z',
      'revenue_newer': any(revenue, revenueSince),
      'expense_newer': any(expense, expenseSince),
    });
  }
}

var _seq = 0;

Map<String, dynamic> pnlSale(
  String unit,
  String date, {
  required int gross,
  required int tax,
  String category = 'restaurant',
}) => {
  'id': 'rc-${++_seq}',
  'revenue_entry_id': 're-$_seq',
  'business_unit_id': unit,
  'revenue_category_id': '$unit-$category',
  'pnl_date': date,
  'pnl_period_key': date.substring(0, 7),
  'gross_minor': gross,
  'tax_minor': tax,
  'net_minor': gross - tax,
  'tax_treatment': tax == 0 ? 'none' : 'inclusive',
  'tax_rate_bp': tax == 0 ? 0 : 500,
  'entered_basis': 'inclusive_total',
  'change_seq': _seq,
  'voided_at': null,
};

Map<String, dynamic> pnlCost(
  String unit,
  String date,
  int amount, {
  String category = 'kirana',
}) => {
  'id': 'ec-${++_seq}',
  'expense_id': 'ex-$_seq',
  'allocation_id': 'al-$_seq',
  'business_unit_id': unit,
  'department_id': '$unit-dept',
  'section_id': '$unit-section',
  'category_id': '$unit-$category',
  'vendor_id': null,
  'pnl_date': date,
  'pnl_period_key': date.substring(0, 7),
  'amount_minor': amount,
  'change_seq': _seq,
  'voided_at': null,
};

/// The D2 intersection, for one property or (with no unit) unscoped.
List<CapabilityGrant> pnlD2([String? unit]) => [
  CapabilityGrant(Capability.reportsView, businessUnitId: unit),
  CapabilityGrant(Capability.revenueView, businessUnitId: unit),
  CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
];

SessionState pnlSession({
  List<CapabilityGrant>? grants,
  String userId = pnlMe,
}) => readySession(
  authority: AuthoritySnapshot(
    userId: userId,
    orgId: 'test-org',
    resolvedAt: DateTime.utc(2026, 9, 19),
    grants: grants ?? pnlD2(),
  ),
);

/// A session a test can move from one person to another, the way signing out and back in
/// moves the real one.
class SwitchableSession extends StubSession {
  SwitchableSession(super.initial);

  void switchTo(SessionState next) => state = next;
}

/// Two properties with different cut-offs, their hierarchies, and the categories the
/// fixtures above name.
Future<void> seedPnlMasters(AppDatabase db) async {
  Future<void> insert(String table, String columns, List<Object?> values) =>
      db.customStatement(
        'INSERT INTO $table ($columns, sort_order, row_version, updated_at) '
        'VALUES (${List.filled(values.length, '?').join(', ')}, 1, 1, '
        "'2026-06-01T00:00:00.000Z')",
        values,
      );

  for (final (id, code, name, cutoff) in const [
    (pnlCcr, 'CCR', 'Crystal Canopy Rooftop', '05:00'),
    (pnlHki, 'HKI', 'Hotel Krishna Imperial', '00:00'),
  ]) {
    await insert(
      'business_units',
      'id, org_id, code, name, kind, timezone, business_day_cutoff',
      [id, 'test-org', code, name, 'hotel', 'Asia/Kolkata', cutoff],
    );
    await insert('departments', 'id, org_id, code, name, business_unit_id', [
      '$id-dept',
      'test-org',
      '$code-D',
      'Department',
      id,
    ]);
    await insert('sections', 'id, org_id, code, name, department_id', [
      '$id-section',
      'test-org',
      '$code-S',
      'Section',
      '$id-dept',
    ]);
  }
  for (final (unit, code, name) in const [
    (pnlCcr, 'restaurant', 'Restaurant'),
    (pnlCcr, 'nandbhog', 'Nandbhog'),
    (pnlHki, 'banquet', 'Banquet'),
  ]) {
    await insert(
      'revenue_categories',
      'id, org_id, code, name, business_unit_id',
      ['$unit-$code', 'test-org', code.toUpperCase(), name, unit],
    );
  }
  for (final (unit, code, name) in const [
    (pnlCcr, 'kirana', 'Kirana & Pulses'),
    (pnlHki, 'electricity', 'Electricity'),
  ]) {
    await insert('expense_categories', 'id, org_id, code, name, section_id', [
      '$unit-$code',
      'test-org',
      code.toUpperCase(),
      name,
      '$unit-section',
    ]);
  }
}
