/// One expense, as a value to be rendered and nothing else (Phase 5 Slice 10).
///
/// The ledger builds it from the document this device holds; the P&L drill-down builds it
/// from a document fetched on demand and held in memory only (D-233). Neither path carries
/// anything a renderer could act on: no row version to base an edit on beyond a displayed
/// number, no outbox pointer, no sync state and no attachment bytes. What a person may *do*
/// with an expense is decided by the surface that composes the renderer, never by the value.
///
/// It keeps D-062's shape: a scoped reader's value carries the visible share and no invoice
/// total, because the total was never given to them.
library;

import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:meta/meta.dart';

@immutable
final class ExpenseDocumentDetail {
  const ExpenseDocumentDetail({
    required this.id,
    required this.businessDate,
    required this.paymentStatus,
    required this.isScoped,
    required this.visibleAmount,
    required this.allocations,
    required this.periods,
    required this.attachments,
    required this.createdBy,
    required this.rowVersion,
    this.txnNumber,
    this.accountingPeriodStart,
    this.accountingPeriodEnd,
    this.paymentDate,
    this.referenceNumber,
    this.notes,
    this.capturedAt,
    this.serverUpdatedAt,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  final String id;
  final String? txnNumber;

  /// The stored business date, as `YYYY-MM-DD`.
  final String businessDate;
  final String? accountingPeriodStart;
  final String? accountingPeriodEnd;

  /// `paid` or `unpaid`.
  final String paymentStatus;
  final String? paymentDate;
  final String? referenceNumber;
  final String? notes;

  /// True when this reader was given only their own properties' share (D-062).
  final bool isScoped;

  /// What this reader may add up. On a scoped value it is never presented as the invoice.
  final Money visibleAmount;

  final List<ExpenseDetailAllocation> allocations;
  final List<ExpenseDetailPeriod> periods;
  final List<ExpenseDetailAttachment> attachments;

  final String createdBy;
  final DateTime? capturedAt;
  final DateTime? serverUpdatedAt;
  final int rowVersion;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  bool get isVoided => voidedAt != null;

  /// What to show where a number would go, before the server has issued one.
  String get displayReference =>
      txnNumber ?? 'Pending number · ${id.substring(0, 8).toUpperCase()}';
}

@immutable
final class ExpenseDetailAllocation {
  const ExpenseDetailAllocation({
    required this.id,
    required this.businessUnitId,
    required this.label,
    required this.amount,
  });

  final String id;
  final String businessUnitId;

  /// The category label as it read when the line was recorded (D-035).
  final String label;
  final Money amount;
}

@immutable
final class ExpenseDetailPeriod {
  const ExpenseDetailPeriod({
    required this.allocationId,
    required this.periodKey,
    required this.isDerived,
    required this.amount,
  });

  final String allocationId;
  final String periodKey;
  final bool isDerived;
  final Money amount;
}

/// A file's name and where its upload got to. No path, no bytes, no control.
@immutable
final class ExpenseDetailAttachment {
  const ExpenseDetailAttachment({
    required this.fileName,
    required this.uploadState,
  });

  final String fileName;
  final String uploadState;
}
