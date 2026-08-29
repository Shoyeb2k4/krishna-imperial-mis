/// Pulling expenses down, in the shape this user was given them.
///
/// The security property this file has to preserve is the one the server projection
/// already established, and it preserves it the only way that actually works: **it never
/// receives the withheld figure in the first place.**
///
///     Invoice          ₹58,000
///       Crystal Canopy ₹25,000
///       Hotel Krishna  ₹33,000
///
/// A Crystal Canopy manager reads `expense_document`, which returns
/// `visible_amount_minor = 2500000`, `is_complete = false` and `total_amount_minor =
/// null`. Those three values are written into the local row as they arrive. Nothing is
/// fetched and then dropped, nothing is fetched and then hidden — the ₹33,000 and the
/// ₹58,000 are simply not in the response, so they cannot be in the database, and a raw
/// dump of that device contains neither.
///
/// The local schema then makes the mistake unrepeatable: a `scoped` row carrying a
/// document total violates a check constraint, so a future writer cannot reintroduce the
/// leak by being careless with a null.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';

/// What one pull did.
final class ExpensePullReport {
  const ExpensePullReport({
    required this.documents,
    required this.allocations,
    required this.contributions,
    required this.attachments,
  });

  final int documents;
  final int allocations;
  final int contributions;
  final int attachments;

  @override
  String toString() =>
      'ExpensePullReport(documents: $documents, lines: $allocations, '
      'contributions: $contributions, attachments: $attachments)';
}

class ExpensePull {
  ExpensePull({required this.db, required this.gateway});

  final AppDatabase db;
  final ExpenseGateway gateway;

  /// Pulls one document and everything this caller may see of it.
  ///
  /// Returns null when the server will not show it — which is a legitimate answer, not an
  /// error: a Hotel Krishna manager asking about a Crystal Canopy-only expense should
  /// learn nothing, including whether it exists.
  Future<ExpensePullReport?> pullOne(String expenseId) async {
    final document = await gateway.fetchDocument(expenseId);
    if (document is! RemoteOk<Map<String, dynamic>?>) return null;
    final header = document.value;
    if (header == null) return null;

    final lines = await gateway.fetchAllocations(expenseId);
    final periods = await gateway.fetchPeriodContributions(expenseId);
    final attachments = await gateway.fetchAttachments(expenseId);

    final allocationRows = lines is RemoteOk<List<Map<String, dynamic>>>
        ? lines.value
        : const <Map<String, dynamic>>[];
    final periodRows = periods is RemoteOk<List<Map<String, dynamic>>>
        ? periods.value
        : const <Map<String, dynamic>>[];
    final attachmentRows = attachments is RemoteOk<List<Map<String, dynamic>>>
        ? attachments.value
        : const <Map<String, dynamic>>[];

    await _write(header, allocationRows, periodRows, attachmentRows);

    return ExpensePullReport(
      documents: 1,
      allocations: allocationRows.length,
      contributions: periodRows.length,
      attachments: attachmentRows.length,
    );
  }

  Future<void> _write(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> lines,
    List<Map<String, dynamic>> periods,
    List<Map<String, dynamic>> attachments,
  ) async {
    final expenseId = header['id'] as String;
    // `is_complete` is the server's word for it. The client does not recompute it from
    // the lines it happens to hold — that would be the client deciding its own
    // visibility, which is the thing this design refuses to do.
    final complete = header['is_complete'] == true;
    final now = DateTime.now().toUtc();

    await db.transaction(() async {
      await db
          .into(db.expenses)
          .insertOnConflictUpdate(
            ExpensesCompanion.insert(
              id: expenseId,
              orgId: header['org_id'] as String,
              txnNumber: Value(header['txn_number'] as String?),
              financialYear: Value(header['financial_year'] as int?),
              businessDate: header['business_date'] as String,
              businessDateSource: Value(
                header['business_date_source'] as String? ?? 'derived',
              ),
              accountingPeriodStart: Value(
                header['accounting_period_start'] as String?,
              ),
              accountingPeriodEnd: Value(
                header['accounting_period_end'] as String?,
              ),
              visibility: Value(complete ? 'complete' : 'scoped'),
              // Null unless complete — and the check constraint agrees. On a scoped
              // record this value was never in the response to begin with.
              documentTotalMinor: Value(
                complete ? header['total_amount_minor'] as int? : null,
              ),
              visibleAmountMinor: header['visible_amount_minor'] as int,
              isShared: Value(!complete || lines.length > 1),
              vendorId: Value(header['vendor_id'] as String?),
              paymentStatus: Value(
                header['payment_status'] as String? ?? 'unpaid',
              ),
              paymentDate: Value(header['payment_date'] as String?),
              paymentMethodId: Value(header['payment_method_id'] as String?),
              referenceNumber: Value(header['reference_number'] as String?),
              notes: Value(header['notes'] as String?),
              taxAmountMinor: Value(header['tax_amount_minor'] as int?),
              createdBy: header['created_by'] as String,
              capturedAt:
                  DateTime.tryParse('${header['captured_at']}')?.toUtc() ?? now,
              voidedAt: Value(
                DateTime.tryParse('${header['voided_at']}')?.toUtc(),
              ),
              voidedBy: Value(header['voided_by'] as String?),
              voidReason: Value(header['void_reason'] as String?),
              rowVersion: Value(header['row_version'] as int? ?? 1),
              serverUpdatedAt: Value(
                DateTime.tryParse('${header['updated_at']}')?.toUtc(),
              ),
              updatedAt: now,
            ),
          );

      // Replace the visible lines wholesale. A line that has stopped being visible —
      // because scope was withdrawn — must leave, not linger.
      await (db.delete(
        db.expensePeriodAllocations,
      )..where((t) => t.expenseId.equals(expenseId))).go();
      await (db.delete(
        db.expenseAllocations,
      )..where((t) => t.expenseId.equals(expenseId))).go();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        await db
            .into(db.expenseAllocations)
            .insert(
              ExpenseAllocationsCompanion.insert(
                id: line['id'] as String,
                orgId: line['org_id'] as String,
                expenseId: expenseId,
                businessUnitId: line['business_unit_id'] as String,
                departmentId: line['department_id'] as String,
                sectionId: line['section_id'] as String,
                categoryId: line['category_id'] as String,
                amountMinor: line['amount_minor'] as int,
                categoryLabel: line['category_label'] as String? ?? '',
                sortOrder: Value(line['sort_order'] as int? ?? i),
                rowVersion: Value(line['row_version'] as int? ?? 1),
                updatedAt: now,
              ),
            );
      }

      for (final part in periods) {
        await db
            .into(db.expensePeriodAllocations)
            .insert(
              ExpensePeriodAllocationsCompanion.insert(
                id: part['id'] as String,
                orgId: part['org_id'] as String,
                expenseId: expenseId,
                allocationId: part['allocation_id'] as String,
                businessUnitId: part['business_unit_id'] as String,
                accountingPeriodStart:
                    part['accounting_period_start'] as String,
                accountingPeriodEnd: part['accounting_period_end'] as String,
                amountMinor: part['amount_minor'] as int,
                pnlDate: part['pnl_date'] as String,
                pnlPeriodKey: part['pnl_period_key'] as String,
                isDerived: Value(part['is_derived'] == true),
                updatedAt: now,
              ),
            );
      }

      // Attachments arrive only for a caller entitled to the whole document. A scoped
      // caller receives an empty list from the server — nothing is filtered here.
      for (final attachment in attachments) {
        await db
            .into(db.expenseAttachments)
            .insertOnConflictUpdate(
              ExpenseAttachmentsCompanion.insert(
                id: attachment['id'] as String,
                orgId: attachment['org_id'] as String,
                expenseId: expenseId,
                fileName: attachment['file_name'] as String,
                contentType: attachment['content_type'] as String,
                byteSize: attachment['byte_size'] as int,
                contentHash: attachment['content_hash'] as String,
                uploadState: const Value('uploaded'),
                storagePath: Value(attachment['storage_path'] as String?),
                uploadedAt: Value(
                  DateTime.tryParse('${attachment['uploaded_at']}')?.toUtc(),
                ),
                uploadedBy: attachment['uploaded_by'] as String,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
  }
}
