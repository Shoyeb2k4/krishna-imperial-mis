/// The reporting delta transport.
///
/// Phase 5 Slice 4. Reads the two contribution projections, which since
/// `20260907121017` carry the **effective document generation** — so a delta is one scoped
/// query per dataset and needs no bespoke endpoint (D-177).
///
/// ## Why no sync RPC was written
///
/// The projections already enforce exactly the authority a reporting read needs:
/// `may_read_expense` plus `expense_visible_units` on one side,
/// `has_capability('revenue.view', unit)` on the other. A dedicated delta RPC would have
/// been a second place for that boundary to live, and Slice 7 would then have to tighten
/// two things instead of one when `reports.view` acquires its evaluator.
///
/// ## Why the query carries no period filter
///
/// The obvious delta is *"changed rows inside the year I am synchronising"*, and it is
/// wrong. A business-date correction that moves a sale out of June leaves **no row in
/// June at all** — so a June-filtered query would not return it, and the stale June figure
/// would sit in the cache for ever. The delta therefore asks for every changed
/// contribution the caller may see, whatever period it lands in, and the client decides
/// which of them fall inside the coverage it is refreshing.
///
/// At V1 volume that is a few thousand rows on a first pull and a handful thereafter.
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/supabase_gateway.dart';

/// Which canonical dataset a reporting read is about.
enum ReportingDataset {
  revenue('revenue', 'revenue_period_contributions', 'revenue_entry_id'),
  expense('expense', 'expense_period_contributions', 'expense_id');

  const ReportingDataset(this.wireName, this.relation, this.documentColumn);

  /// The stored form, pinned rather than taken from `.name` — the trap D-104 recorded.
  final String wireName;

  /// The scoped projection this dataset is read through. Never a base table.
  final String relation;

  /// The column naming the financial document, which is the delta unit.
  final String documentColumn;

  static ReportingDataset fromWire(String value) => values.firstWhere(
    (d) => d.wireName == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'unknown reporting dataset — the stored vocabulary is revenue|expense',
    ),
  );
}

class ReportingGateway extends SupabaseGateway {
  const ReportingGateway(super.client);

  /// Every contribution the caller may see whose document changed after [sinceGeneration].
  ///
  /// [sinceGeneration] is already reduced by the safety overlap by the caller: a sequence
  /// value is allocated when a row is written and becomes visible only when its
  /// transaction commits, so a naive `> last seen` can step over a transaction that
  /// committed late (ARCHITECTURE §5.2). Re-reading below the watermark is harmless
  /// because the client replaces by document identity.
  ///
  /// Ordered by generation so a client applying in order never regresses its watermark,
  /// and paged, because an initial pull of a busy year is not a small answer.
  Future<RemoteOutcome<List<Map<String, dynamic>>>> changedContributions({
    required ReportingDataset dataset,
    required int sinceGeneration,
    int pageSize = 1000,
  }) => guard(() async {
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await client
          .from(dataset.relation)
          .select()
          .gt('change_seq', sinceGeneration)
          .order('change_seq')
          .range(offset, offset + pageSize - 1);
      all.addAll([for (final row in page) Map<String, dynamic>.from(row)]);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  });

  /// One authoritative reporting snapshot: both datasets, from one server statement.
  ///
  /// This replaces a delta per dataset (D-188). Two queries are two MVCC snapshots, and
  /// ordinary concurrent financial writes between them leave the cache holding revenue as
  /// it stood at one moment beside expenses as they stood at another — a pair that was
  /// never true of the hotel, and which nothing in the stored evidence could detect.
  ///
  /// The response carries the snapshot's own identity and the **server's** transaction
  /// time from that same statement. A second call asking the clock afterwards would
  /// describe a different moment, and the device clock is not evidence about a server at
  /// all.
  ///
  /// The cursors stay per dataset because they answer a different question — where the
  /// next delta resumes — and each is already reduced by the caller's safety overlap.
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) => guard(() async {
    final answer = await client.rpc<dynamic>(
      'reporting_snapshot',
      params: {
        'p_business_unit_ids': businessUnitIds,
        'p_revenue_since': revenueSince,
        'p_expense_since': expenseSince,
      },
    );
    return Map<String, dynamic>.from(answer as Map);
  });

  /// Whether canonical reporting facts this caller may report on have moved past the
  /// given cursors.
  ///
  /// Deliberately **not** a comparison against the global sequence head: a vendor rename,
  /// a tax-rule change or an audit row all advance that sequence and change no
  /// contribution, so a P&L would be reported as outdated because something unrelated
  /// happened. This asks only about the projections a report is built from, and returns
  /// no figures.
  Future<RemoteOutcome<Map<String, dynamic>>> newerThan({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) => guard(() async {
    final answer = await client.rpc<dynamic>(
      'reporting_newer_than',
      params: {
        'p_business_unit_ids': businessUnitIds,
        'p_revenue_since': revenueSince,
        'p_expense_since': expenseSince,
      },
    );
    return Map<String, dynamic>.from(answer as Map);
  });

  /// The authoritative primitive sums for a scope and an inclusive P&L-date range.
  ///
  /// One call, one statement, one snapshot on the server (D-184). Both sides of the P&L
  /// and every requested property come back together, because a consolidated figure
  /// assembled from several requests would be several moments' worth of the hotel.
  ///
  /// [businessUnitIds] is explicit and is never omitted to mean "everything": the function
  /// coalesces a null array to empty and returns no units, so an accidental whole-org
  /// report is unavailable rather than guarded against.
  Future<RemoteOutcome<Map<String, dynamic>>> primitives({
    required List<String> businessUnitIds,
    required String fromIsoDate,
    required String toIsoDate,
    bool breakdown = false,
  }) => guard(() async {
    final answer = await client.rpc<dynamic>(
      'reporting_primitives',
      params: {
        'p_business_unit_ids': businessUnitIds,
        'p_from': fromIsoDate,
        'p_to': toIsoDate,
        'p_breakdown': breakdown,
      },
    );
    return Map<String, dynamic>.from(answer as Map);
  });

  /// The complete current contribution set for named documents.
  ///
  /// Used where a delta has established *that* a document changed and the client needs
  /// everything it now contributes — including nothing, which is what a document whose
  /// contributions all moved out of scope correctly returns.
  Future<RemoteOutcome<List<Map<String, dynamic>>>> contributionsForDocuments({
    required ReportingDataset dataset,
    required List<String> documentIds,
  }) => guard(() async {
    if (documentIds.isEmpty) return const <Map<String, dynamic>>[];
    final rows = await client
        .from(dataset.relation)
        .select()
        .inFilter(dataset.documentColumn, documentIds);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  });
}
