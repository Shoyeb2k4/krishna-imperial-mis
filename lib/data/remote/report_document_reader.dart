/// Opens a document from a report: fetched on demand, held in memory, never persisted
/// (Phase 5 Slice 10, D-233).
///
/// ## What this is for, and the three things it must never do
///
/// A P&L row names a canonical document whose full detail — number, notes, payment,
/// components, attachment names — is deliberately not in the reporting cache. This reads it
/// from the **existing authorised projections** (`revenue_document`,
/// `revenue_component_detail`, `revenue_attachments`, `expense_document`,
/// `expense_allocations`, `expense_period_contributions`, `expense_attachments`), under the
/// signed-in person's own session, so every transaction boundary the server already draws
/// still decides what comes back — including D-062's scoped share of a shared expense.
///
/// It **writes nothing**: no ordinary transaction table, no reporting cache, no outbox. It
/// holds no database at all. `ExpensePull.pullOne` and `applyServerDocument` persist into
/// the transaction tables, which would put a colleague's document into this device's ledger
/// and mix authority classes D-171 keeps apart, so neither is used.
///
/// It **invokes no RPC**. Every call is a read of a projection.
///
/// It **never substitutes fresher figures for a cached row**. The fetched document is
/// returned only when its canonical contribution to the selected bucket equals the cached
/// row exactly; otherwise the answer is [ReportDocumentChanged], and the report is
/// refreshed rather than contradicted in place.
library;

import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/domain/expenses/expense_document_detail.dart';
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

final class ReportDocumentReader {
  const ReportDocumentReader({required this.expenses, required this.revenue});

  final ExpenseGateway expenses;
  final RevenueGateway revenue;

  /// The revenue document behind [line], or why it cannot explain it.
  Future<ReportDocumentDetail<RevenueEntry>> revenueFor(
    RevenueDocumentLine line, {
    required ReportRange range,
  }) async {
    final id = line.revenueEntryId;

    final header = await revenue.fetchDocument(id);
    if (header is RemoteUnreachable) return const ReportDocumentNotDownloaded();
    // A refusal and an empty answer both mean the server will not show it to this person.
    final headerValue = header.valueOrNull;
    if (headerValue == null) return const ReportDocumentNotAvailable();

    final components = await revenue.fetchComponents(id);
    final attachments = await revenue.fetchAttachments(id);
    if (components is RemoteUnreachable || attachments is RemoteUnreachable) {
      return const ReportDocumentNotDownloaded();
    }
    final componentRows = components.valueOrNull ?? const [];
    if (componentRows.isEmpty) return const ReportDocumentNotAvailable();

    try {
      final entry = _revenueEntry(
        headerValue,
        componentRows,
        attachments.valueOrNull ?? const [],
      );
      final explains = PnlDrilldown.revenueDocumentExplains(
        line,
        range: range,
        fetched: RevenueDocumentFacts(
          businessUnitId: entry.businessUnitId,
          revenueCategoryId: entry.revenueCategoryId,
          businessDate: entry.businessDate,
          accepted: entry.txnNumber != null,
          voided: entry.isVoided,
          components: [
            for (final c in entry.components)
              (gross: c.gross, tax: c.tax, net: c.net),
          ],
        ),
      );
      return explains
          ? ReportDocumentReady(entry)
          : const ReportDocumentChanged();
    } on FormatException {
      // A payload this build cannot read is not a document it can explain a figure with.
      return const ReportDocumentChanged();
    }
  }

  /// The expense document behind [line], or why it cannot explain it.
  Future<ReportDocumentDetail<ExpenseDocumentDetail>> expenseFor(
    ExpenseDocumentLine line, {
    required ReportRange range,
  }) async {
    final id = line.expenseId;

    final header = await expenses.fetchDocument(id);
    if (header is RemoteUnreachable) return const ReportDocumentNotDownloaded();
    final headerValue = header.valueOrNull;
    if (headerValue == null) return const ReportDocumentNotAvailable();

    final lines = await expenses.fetchAllocations(id);
    final periods = await expenses.fetchPeriodContributions(id);
    final attachments = await expenses.fetchAttachments(id);
    if (lines is RemoteUnreachable ||
        periods is RemoteUnreachable ||
        attachments is RemoteUnreachable) {
      return const ReportDocumentNotDownloaded();
    }
    final lineRows = lines.valueOrNull ?? const [];
    final periodRows = periods.valueOrNull ?? const [];
    if (lineRows.isEmpty || periodRows.isEmpty) {
      return const ReportDocumentNotAvailable();
    }

    try {
      final detail = _expenseDetail(
        headerValue,
        lineRows,
        periodRows,
        attachments.valueOrNull ?? const [],
      );
      final explains = PnlDrilldown.expenseDocumentExplains(
        line,
        range: range,
        fetched: ExpenseDocumentFacts(
          accepted: detail.txnNumber != null,
          voided: detail.isVoided,
          contributions: [
            for (final row in periodRows)
              ExpenseContributionFact(
                businessUnitId: _string(row['business_unit_id']),
                departmentId: _string(row['department_id']),
                sectionId: _string(row['section_id']),
                categoryId: _string(row['category_id']),
                pnlDate: _date(row['pnl_date']),
                amount: Money.fromPaise(_int(row['amount_minor'])),
              ),
          ],
        ),
      );
      return explains
          ? ReportDocumentReady(detail)
          : const ReportDocumentChanged();
    } on FormatException {
      return const ReportDocumentChanged();
    }
  }

  // ── Mapping, into immutable values ───────────────────────────────────────

  static RevenueEntry _revenueEntry(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> components,
    List<Map<String, dynamic>> attachments,
  ) => RevenueEntry(
    id: _string(header['id']),
    txnNumber: header['txn_number'] as String?,
    businessUnitId: _string(header['business_unit_id']),
    revenueCategoryId: _string(header['revenue_category_id']),
    businessDate: _date(header['business_date']),
    // The projection states when the server recorded it; the device capture instant is
    // forensic metadata this surface never shows.
    capturedAt: _instant(header['created_at']) ?? DateTime.utc(1970),
    entryKind: RevenueEntryKind.fromName(
      header['entry_kind'] as String? ?? 'daily_summary',
    ),
    sourceReference: header['source_reference'] as String?,
    notes: header['notes'] as String?,
    createdBy: header['created_by'] as String?,
    rowVersion: header['row_version'] as int? ?? 1,
    voidedAt: _instant(header['voided_at']),
    voidReason: header['void_reason'] as String?,
    businessDateSource: BusinessDateSource.fromWire(
      header['business_date_source'] as String? ?? 'derived',
    ),
    components: [
      for (final c in components)
        RevenueComponent(
          id: _string(c['id']),
          enteredAmount: Money.fromPaise(_int(c['entered_amount_minor'])),
          enteredBasis: EnteredBasis.fromName(_string(c['entered_basis'])),
          gross: Money.fromPaise(_int(c['gross_amount_minor'])),
          tax: Money.fromPaise(_int(c['tax_amount_minor'])),
          net: Money.fromPaise(_int(c['net_amount_minor'])),
          taxRuleId: _string(c['tax_rule_id']),
          taxRateBasisPoints: _int(c['tax_rate_bp']),
          taxTreatment: TaxTreatment.fromName(_string(c['tax_treatment'])),
          valueBandId: c['value_band_id'] as String?,
          valueBandLabel: c['value_band_label'] as String?,
          valueBandFloor: c['value_band_floor_minor'] == null
              ? null
              : Money.fromPaise(_int(c['value_band_floor_minor'])),
          valueBandCeiling: c['value_band_ceiling_minor'] == null
              ? null
              : Money.fromPaise(_int(c['value_band_ceiling_minor'])),
          supplySubtypeId: c['supply_subtype_id'] as String?,
          premisesStatusCode: c['premises_status_code'] as String?,
        ),
    ],
    attachments: [
      for (final a in attachments)
        DocumentAttachment(
          id: _string(a['id']),
          fileName: _string(a['file_name']),
          contentType: a['content_type'] as String? ?? '',
          byteSize: a['byte_size'] as int? ?? 0,
          contentHash: a['content_hash'] as String? ?? '',
          uploadState: AttachmentUploadState.uploaded,
        ),
    ],
  );

  static ExpenseDocumentDetail _expenseDetail(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> lines,
    List<Map<String, dynamic>> periods,
    List<Map<String, dynamic>> attachments,
  ) {
    // `is_complete` is the server's word for it, exactly as the ledger pull reads it: the
    // client never works out its own visibility (D-062).
    final complete = header['is_complete'] == true;
    return ExpenseDocumentDetail(
      id: _string(header['id']),
      txnNumber: header['txn_number'] as String?,
      businessDate: _string(header['business_date']),
      accountingPeriodStart: header['accounting_period_start'] as String?,
      accountingPeriodEnd: header['accounting_period_end'] as String?,
      paymentStatus: header['payment_status'] as String? ?? 'unpaid',
      paymentDate: header['payment_date'] as String?,
      referenceNumber: header['reference_number'] as String?,
      notes: header['notes'] as String?,
      isScoped: !complete,
      visibleAmount: Money.fromPaise(_int(header['visible_amount_minor'])),
      allocations: [
        for (final line in lines)
          ExpenseDetailAllocation(
            id: _string(line['id']),
            businessUnitId: _string(line['business_unit_id']),
            label: line['category_label'] as String? ?? '',
            amount: Money.fromPaise(_int(line['amount_minor'])),
          ),
      ],
      periods: [
        for (final part in periods)
          ExpenseDetailPeriod(
            allocationId: _string(part['allocation_id']),
            periodKey: _string(part['pnl_period_key']),
            isDerived: part['is_derived'] == true,
            amount: Money.fromPaise(_int(part['amount_minor'])),
          ),
      ],
      attachments: [
        for (final a in attachments)
          ExpenseDetailAttachment(
            fileName: _string(a['file_name']),
            uploadState: 'uploaded',
          ),
      ],
      createdBy: header['created_by'] as String? ?? '',
      capturedAt: _instant(header['captured_at']),
      serverUpdatedAt: _instant(header['updated_at']),
      rowVersion: header['row_version'] as int? ?? 1,
      voidedAt: _instant(header['voided_at']),
      voidedBy: header['voided_by'] as String?,
      voidReason: header['void_reason'] as String?,
    );
  }

  static String _string(Object? value) => switch (value) {
    final String v => v,
    _ => throw FormatException('expected text, got ${value.runtimeType}'),
  };

  /// Money arrives as an integer number of paise and is read as one. A non-integer is
  /// refused rather than rounded.
  static int _int(Object? value) => switch (value) {
    final int v => v,
    _ => throw FormatException(
      'expected integer paise, got ${value.runtimeType}',
    ),
  };

  static BusinessDate _date(Object? value) {
    final parsed = BusinessDate.tryParse(_string(value));
    if (parsed == null) throw FormatException('not a date: $value');
    return parsed;
  }

  static DateTime? _instant(Object? value) =>
      value == null ? null : DateTime.tryParse('$value')?.toUtc();
}
