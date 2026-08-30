/// Local persistence for expenses: the atomic save, and the reconciliation afterwards.
///
/// ## The save is one transaction, and the outbox is inside it
///
/// A financial save that succeeded locally but lost its queue entry is worse than a save
/// that failed: the user was told the entry exists, and nothing will ever send it. So the
/// document, its lines, its period contributions, its staged attachment metadata **and**
/// the outbox row are written in a single Drift transaction. Either the whole intent
/// exists or none of it does, and the interface may only say "saved" after that
/// transaction commits.
///
/// No network is involved. `create` does not know what a network is.
///
/// ## Reconciliation is separate, and never re-identifies the intent
///
/// When the server accepts a create it returns a transaction number, a row version and
/// its own timestamps. Those are written back onto the same local row, keyed by the same
/// client-generated id the expense has had since it was typed. If the *response* is lost
/// after the server committed, the retry carries the same `mutation_id` and the server
/// replays its stored answer — so the recovery path is "ask again with the same identity",
/// never "send a second expense with a new one" (D-004).
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/expense_tables.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// What the server said about a create it accepted.
final class ExpenseAcceptance {
  const ExpenseAcceptance({
    required this.expenseId,
    required this.rowVersion,
    this.txnNumber,
    this.financialYear,
    this.serverUpdatedAt,
  });

  final String expenseId;
  final int rowVersion;

  /// `KI-EXP-26-27-000001`, issued by the server. Null only if the server declined to
  /// say, which would itself be a defect worth surfacing rather than papering over.
  final String? txnNumber;
  final int? financialYear;
  final DateTime? serverUpdatedAt;

  static ExpenseAcceptance? fromResult(
    String expenseId,
    Map<String, dynamic> r,
  ) {
    final version = r['row_version'];
    if (version is! int) return null;
    return ExpenseAcceptance(
      expenseId: expenseId,
      rowVersion: version,
      txnNumber: r['txn_number'] as String?,
      financialYear: r['financial_year'] as int?,
      serverUpdatedAt: DateTime.tryParse('${r['updated_at']}')?.toUtc(),
    );
  }
}

/// An expense as this device holds it, with its sync state derived rather than stored.
final class LocalExpense {
  const LocalExpense({
    required this.row,
    required this.allocations,
    required this.periodContributions,
    required this.attachments,
    required this.syncState,
  });

  final ExpenseRow row;
  final List<ExpenseAllocationRow> allocations;
  final List<ExpensePeriodAllocationRow> periodContributions;
  final List<ExpenseAttachmentRow> attachments;

  /// Derived from the outbox through `pendingMutationId`, never from a column of its
  /// own — two sources for one fact is how a record comes to claim it is synced when it
  /// is not.
  final SyncState syncState;

  ExpenseVisibility get visibility => row.visibility == 'scoped'
      ? ExpenseVisibility.scoped
      : ExpenseVisibility.complete;

  bool get isScoped => visibility == ExpenseVisibility.scoped;

  /// What this user may add up. Never presented as the invoice on a scoped record.
  Money get visibleAmount => Money.fromPaise(row.visibleAmountMinor);

  /// The invoice total, or null when this device was not given it.
  Money? get documentTotal => row.documentTotalMinor == null
      ? null
      : Money.fromPaise(row.documentTotalMinor!);

  ExpenseNumber? get number =>
      row.txnNumber == null ? null : ExpenseNumber.tryParse(row.txnNumber!);

  /// What to show where a number would go, before the server has issued one.
  ///
  /// Deliberately not a fabricated `KI-EXP-…`: a permanent-looking reference that later
  /// changes is worse than an honest pending state.
  String get displayReference =>
      row.txnNumber ??
      'Pending number · ${row.id.substring(0, 8).toUpperCase()}';
}

/// What the ledger is being asked for.
///
/// An interface rather than a concrete type so the data layer does not depend on the
/// feature layer — the presentation's `ExpenseFilter` implements it, and the repository
/// never learns that a filter bar exists.
abstract interface class ExpenseQuery {
  String? get from;
  String? get to;
  String? get businessUnitId;
  String? get categoryId;
  String? get vendorId;
  String? get paymentStatus;
  SyncState? get syncState;
  String? get search;
  bool get includeVoided;
}

class ExpenseRepository {
  ExpenseRepository(this._db);

  final AppDatabase _db;

  /// Saves a locally created expense and queues it, atomically.
  ///
  /// The aggregate has already asserted that the money reconciles — an [ExpenseDocument]
  /// that does not balance cannot be constructed — so this method's job is durability,
  /// not arithmetic. It re-asserts the sum anyway before writing, because the cost is a
  /// comparison and the alternative is a financial record nobody can explain.
  ///
  /// Returns the `mutation_id` the intent will be delivered under. That id is generated
  /// once, here, and reused for every retry for the rest of its life.
  Future<String> createLocally(
    ExpenseDocument expense, {
    required String actorUserId,
    required String mutationId,
    required DateTime now,
  }) async {
    final allocated = Money.sum(expense.allocations.map((a) => a.amount));
    if (allocated != expense.total) {
      throw ExpenseImbalance(
        what: 'allocation lines on expense ${expense.id}',
        expected: expense.total,
        actual: allocated,
      );
    }

    await _db.transaction(() async {
      // 1 · The document. A locally created expense is `complete` by construction: this
      // user authored every line of it, so there is nothing withheld from them.
      await _db
          .into(_db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: expense.id,
              orgId: expense.orgId,
              businessDate: expense.businessDate.iso,
              businessDateSource: Value(expense.businessDateSource.name),
              accountingPeriodStart: Value(expense.accountingPeriodStart?.iso),
              accountingPeriodEnd: Value(expense.accountingPeriodEnd?.iso),
              visibility: const Value('complete'),
              documentTotalMinor: Value(expense.total.paise),
              visibleAmountMinor: expense.total.paise,
              isShared: Value(expense.isCrossUnit),
              vendorId: Value(expense.vendorId),
              paymentStatus: Value(expense.paymentStatus.name),
              paymentDate: Value(expense.paymentDate?.iso),
              paymentMethodId: Value(expense.paymentMethodId),
              referenceNumber: Value(expense.referenceNumber),
              notes: Value(expense.notes),
              taxAmountMinor: Value(expense.taxAmount?.paise),
              createdBy: expense.createdByUserId,
              capturedAt: expense.capturedAt,
              // No transaction number. The server issues it, and inventing one here would
              // be a permanent-looking reference that two offline devices both claim.
              pendingMutationId: Value(mutationId),
              updatedAt: now,
            ),
          );

      // 2 · The lines, and 3 · their period contributions.
      for (var i = 0; i < expense.allocations.length; i++) {
        final line = expense.allocations[i];
        await _db
            .into(_db.expenseAllocations)
            .insert(
              ExpenseAllocationsCompanion.insert(
                id: line.id,
                orgId: expense.orgId,
                expenseId: expense.id,
                businessUnitId: line.businessUnitId,
                departmentId: line.departmentId,
                sectionId: line.sectionId,
                categoryId: line.categoryId,
                amountMinor: line.amount.paise,
                categoryLabel: line.categoryLabel,
                sortOrder: Value(i),
                updatedAt: now,
              ),
            );

        for (final part in line.periodContributions) {
          await _db
              .into(_db.expensePeriodAllocations)
              .insert(
                ExpensePeriodAllocationsCompanion.insert(
                  id: part.id,
                  orgId: expense.orgId,
                  expenseId: expense.id,
                  allocationId: line.id,
                  businessUnitId: line.businessUnitId,
                  accountingPeriodStart: part.periodStart.iso,
                  accountingPeriodEnd: part.periodEnd.iso,
                  amountMinor: part.amount.paise,
                  pnlDate: part.pnlDate.iso,
                  pnlPeriodKey: part.periodKey,
                  isDerived: Value(part.isDerived),
                  updatedAt: now,
                ),
              );
        }
      }

      // 4 · Attachment metadata, already staged on disk by the staging service. The
      // bytes are not this transaction's business; the record of them is.
      for (final attachment in expense.attachments) {
        await _db
            .into(_db.expenseAttachments)
            .insert(
              ExpenseAttachmentsCompanion.insert(
                id: attachment.id,
                orgId: expense.orgId,
                expenseId: expense.id,
                fileName: attachment.fileName,
                contentType: attachment.contentType,
                byteSize: attachment.byteSize,
                contentHash: attachment.contentHash,
                localPath: Value(attachment.localStagingPath),
                uploadState: Value(attachment.uploadState.name),
                storagePath: Value(attachment.storagePath),
                nextAttemptAt: Value(now),
                uploadedBy: actorUserId,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      // 5 · The queue entry, in the same transaction. This is the point of the method.
      await _db
          .into(_db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              mutationId: mutationId,
              actorUserId: Value(actorUserId),
              entityType: 'expense',
              entityId: expense.id,
              op: MutationOp.create.name,
              payload: jsonEncode(_createPayload(expense)),
              nextAttemptAt: now,
              status: OutboxStatus.pending.name,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });

    return mutationId;
  }

  /// The canonical document, in the shape the RPC takes.
  ///
  /// Built here rather than in the endpoint so the payload is captured at save time and
  /// is exactly what the user intended, even if the local row is edited afterwards.
  static Map<String, Object?> _createPayload(ExpenseDocument expense) => {
    'p_id': expense.id,
    'p_business_date': expense.businessDate.iso,
    'p_total_minor': expense.total.paise,
    'p_business_date_source': expense.businessDateSource.name,
    'p_period_start': expense.accountingPeriodStart?.iso,
    'p_period_end': expense.accountingPeriodEnd?.iso,
    'p_vendor_id': expense.vendorId,
    'p_payment_status': expense.paymentStatus.name,
    'p_payment_date': expense.paymentDate?.iso,
    'p_payment_method_id': expense.paymentMethodId,
    'p_reference_number': expense.referenceNumber,
    'p_notes': expense.notes,
    'p_tax_amount_minor': expense.taxAmount?.paise,
    'p_captured_at': expense.capturedAt.toIso8601String(),
    'p_allocations': [
      for (final line in expense.allocations)
        {
          'id': line.id,
          'business_unit_id': line.businessUnitId,
          'department_id': line.departmentId,
          'section_id': line.sectionId,
          'category_id': line.categoryId,
          'amount_minor': line.amount.paise,
          // Only sent when a person chose the split. An ordinary line lets the server
          // apply the default rule, so the two sides cannot disagree about what
          // "derived" means.
          if (line.hasDeliberatePeriodSplit)
            'periods': [
              for (final part in line.periodContributions)
                {
                  'id': part.id,
                  'period_start': part.periodStart.iso,
                  'period_end': part.periodEnd.iso,
                  'amount_minor': part.amount.paise,
                  'is_derived': part.isDerived,
                },
            ],
        },
    ],
  };

  /// Applies an edit locally and queues it, atomically (D-072).
  ///
  /// The mirror of [createLocally], and deliberately the same shape: one transaction
  /// writes the document, replaces its lines and contributions, and appends the outbox
  /// entry. If any of it fails, none of it happened — the interface must never be able to
  /// say an edit is safely queued when the intent was not committed.
  ///
  /// ## What is replaced, and what is not
  ///
  /// Lines and period contributions are **replaced wholesale**, because an edit can add,
  /// remove, re-classify and re-split them at once, and reconciling a diff of financial
  /// rows would be a second implementation of the arithmetic that `ExpenseDocument`
  /// already enforces. The replacement happens inside the transaction, so there is no
  /// moment at which the document has lines that do not add up to it.
  ///
  /// Attachments are **not** replaced. An uploaded bill is historical supporting
  /// evidence; new ones may be added, and removing one is a separate audited operation
  /// that V1 does not offer. So this method inserts attachment rows it has not seen
  /// before and leaves every existing row exactly as it is, including its upload state —
  /// re-writing that here would restart uploads that had already succeeded.
  ///
  /// [baseRowVersion] is the version the *user's screen* was loaded from, not whatever
  /// the local row happens to say now. Passing it in rather than reading it here is what
  /// makes a stale edit a conflict instead of an overwrite: a background pull may have
  /// advanced the local row while the form was open, and the intent must still be judged
  /// against what the person actually saw (§3, D-021).
  Future<void> updateLocally(
    ExpenseDocument expense, {
    required String actorUserId,
    required String mutationId,
    required int baseRowVersion,
    required DateTime now,
  }) async {
    final allocated = Money.sum(expense.allocations.map((a) => a.amount));
    if (allocated != expense.total) {
      throw ExpenseImbalance(
        what: 'allocation lines on expense ${expense.id}',
        expected: expense.total,
        actual: allocated,
      );
    }

    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.expenses,
      )..where((t) => t.id.equals(expense.id))).getSingleOrNull();
      if (existing == null) {
        throw StateError(
          'expense ${expense.id} is not on this device, so there is nothing to edit',
        );
      }
      // The complete-only rule, enforced where the write happens and not only where the
      // button is drawn. A scoped row carries no document total by check constraint, so
      // writing one back would either fail or, worse, publish the share the projection
      // withheld (D-062, and the project lead's V1 read-only rule for scoped shares).
      if (existing.visibility != 'complete') {
        throw StateError(
          'expense ${expense.id} is a scoped projection and is read-only',
        );
      }
      if (existing.voidedAt != null) {
        throw StateError('expense ${expense.id} is voided and is immutable');
      }

      await (_db.update(
        _db.expenses,
      )..where((t) => t.id.equals(expense.id))).write(
        ExpensesCompanion(
          businessDate: Value(expense.businessDate.iso),
          businessDateSource: Value(expense.businessDateSource.name),
          accountingPeriodStart: Value(expense.accountingPeriodStart?.iso),
          accountingPeriodEnd: Value(expense.accountingPeriodEnd?.iso),
          documentTotalMinor: Value(expense.total.paise),
          visibleAmountMinor: Value(expense.total.paise),
          isShared: Value(expense.isCrossUnit),
          vendorId: Value(expense.vendorId),
          paymentStatus: Value(expense.paymentStatus.name),
          paymentDate: Value(expense.paymentDate?.iso),
          paymentMethodId: Value(expense.paymentMethodId),
          referenceNumber: Value(expense.referenceNumber),
          notes: Value(expense.notes),
          taxAmountMinor: Value(expense.taxAmount?.paise),
          pendingMutationId: Value(mutationId),
          updatedAt: Value(now),
        ),
      );

      // Contributions first, then lines: children before parents, so nothing is ever
      // orphaned even for the length of one statement.
      await (_db.delete(
        _db.expensePeriodAllocations,
      )..where((t) => t.expenseId.equals(expense.id))).go();
      await (_db.delete(
        _db.expenseAllocations,
      )..where((t) => t.expenseId.equals(expense.id))).go();

      for (var i = 0; i < expense.allocations.length; i++) {
        final line = expense.allocations[i];
        await _db
            .into(_db.expenseAllocations)
            .insert(
              ExpenseAllocationsCompanion.insert(
                id: line.id,
                orgId: expense.orgId,
                expenseId: expense.id,
                businessUnitId: line.businessUnitId,
                departmentId: line.departmentId,
                sectionId: line.sectionId,
                categoryId: line.categoryId,
                amountMinor: line.amount.paise,
                categoryLabel: line.categoryLabel,
                sortOrder: Value(i),
                updatedAt: now,
              ),
            );

        for (final part in line.periodContributions) {
          await _db
              .into(_db.expensePeriodAllocations)
              .insert(
                ExpensePeriodAllocationsCompanion.insert(
                  id: part.id,
                  orgId: expense.orgId,
                  expenseId: expense.id,
                  allocationId: line.id,
                  businessUnitId: line.businessUnitId,
                  accountingPeriodStart: part.periodStart.iso,
                  accountingPeriodEnd: part.periodEnd.iso,
                  amountMinor: part.amount.paise,
                  pnlDate: part.pnlDate.iso,
                  pnlPeriodKey: part.periodKey,
                  isDerived: Value(part.isDerived),
                  updatedAt: now,
                ),
              );
        }
      }

      // Additions only. `insertOrIgnore` is the whole of the "existing attachments are
      // not touched" rule, expressed where it cannot be forgotten.
      for (final attachment in expense.attachments) {
        await _db
            .into(_db.expenseAttachments)
            .insert(
              ExpenseAttachmentsCompanion.insert(
                id: attachment.id,
                orgId: expense.orgId,
                expenseId: expense.id,
                fileName: attachment.fileName,
                contentType: attachment.contentType,
                byteSize: attachment.byteSize,
                contentHash: attachment.contentHash,
                localPath: Value(attachment.localStagingPath),
                uploadState: Value(attachment.uploadState.name),
                storagePath: Value(attachment.storagePath),
                nextAttemptAt: Value(now),
                uploadedBy: actorUserId,
                createdAt: now,
                updatedAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }

      await _db
          .into(_db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              mutationId: mutationId,
              actorUserId: Value(actorUserId),
              entityType: 'expense',
              entityId: expense.id,
              op: MutationOp.update.name,
              payload: jsonEncode(_updatePayload(expense)),
              baseRowVersion: Value(baseRowVersion),
              nextAttemptAt: now,
              status: OutboxStatus.pending.name,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });
  }

  /// The edit payload, in the shape `expense_update` takes.
  ///
  /// The same document as [_createPayload] minus the two fields an edit does not
  /// restate: `p_business_date_source`, because how the *original* date was arrived at is
  /// history and a correction has its own audit row, and `p_captured_at`, because the
  /// capture instant of the original entry does not move when somebody fixes a figure.
  static Map<String, Object?> _updatePayload(ExpenseDocument expense) {
    final payload = Map<String, Object?>.from(_createPayload(expense))
      ..remove('p_business_date_source')
      ..remove('p_captured_at');
    return payload;
  }

  /// Marks an expense voided locally and queues the void, atomically.
  ///
  /// The void carries `base_row_version`, so a void issued from a stale view is a
  /// conflict rather than an overwrite (D-021) — a document somebody edited to v4 must
  /// not be voided on the strength of a v3 intent.
  Future<void> voidLocally(
    LocalExpense expense, {
    required String reason,
    required String actorUserId,
    required String mutationId,
    required DateTime now,
  }) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.expenses,
      )..where((t) => t.id.equals(expense.row.id))).write(
        ExpensesCompanion(
          voidedAt: Value(now),
          voidedBy: Value(actorUserId),
          voidReason: Value(reason),
          pendingMutationId: Value(mutationId),
          updatedAt: Value(now),
        ),
      );

      await _db
          .into(_db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              mutationId: mutationId,
              actorUserId: Value(actorUserId),
              entityType: 'expense',
              entityId: expense.row.id,
              op: MutationOp.void_.name,
              payload: jsonEncode({'p_reason': reason}),
              baseRowVersion: Value(expense.row.rowVersion),
              nextAttemptAt: now,
              status: OutboxStatus.pending.name,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });
  }

  /// Writes the server's answer onto the local row.
  ///
  /// Deliberately narrow: the transaction number, the version, the server timestamp and
  /// the release of the pending link. It does **not** touch attachment upload state — an
  /// accepted financial record says nothing about whether a photo has finished uploading,
  /// and overwriting that here would restart uploads that had already succeeded.
  Future<void> reconcileAcceptance(ExpenseAcceptance acceptance) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.expenses,
      )..where((t) => t.id.equals(acceptance.expenseId))).write(
        ExpensesCompanion(
          txnNumber: Value(acceptance.txnNumber),
          financialYear: Value(acceptance.financialYear),
          rowVersion: Value(acceptance.rowVersion),
          serverUpdatedAt: Value(acceptance.serverUpdatedAt),
          pendingMutationId: const Value(null),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  /// One expense with everything this device holds for it.
  Future<LocalExpense?> load(String expenseId) async {
    final row =
        await (_db.select(_db.expenses)
              ..where((t) => t.id.equals(expenseId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;

    final allocations =
        await (_db.select(_db.expenseAllocations)
              ..where((t) => t.expenseId.equals(expenseId))
              ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
            .get();
    final periods = await (_db.select(
      _db.expensePeriodAllocations,
    )..where((t) => t.expenseId.equals(expenseId))).get();
    final attachments = await (_db.select(
      _db.expenseAttachments,
    )..where((t) => t.expenseId.equals(expenseId))).get();

    return LocalExpense(
      row: row,
      allocations: allocations,
      periodContributions: periods,
      attachments: attachments,
      syncState: await _syncStateFor(row),
    );
  }

  /// The ledger, most recent business date first.
  ///
  /// Excludes documents retained through a revocation (D-068). Those rows exist only so
  /// the actor can inspect and reconcile their own unsent intent; they are not authorised
  /// financial data and must never appear in a ledger. [listRetainedAfterRevocation] is
  /// the one way to reach them.
  Future<List<LocalExpense>> list({int limit = 50, int offset = 0}) async {
    final rows =
        await (_db.select(_db.expenses)
              ..where((t) => t.scopeRevokedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.businessDate,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(
                  expression: t.capturedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(limit, offset: offset))
            .get();
    return [
      for (final row in rows)
        LocalExpense(
          row: row,
          allocations: await (_db.select(
            _db.expenseAllocations,
          )..where((t) => t.expenseId.equals(row.id))).get(),
          periodContributions: await (_db.select(
            _db.expensePeriodAllocations,
          )..where((t) => t.expenseId.equals(row.id))).get(),
          attachments: await (_db.select(
            _db.expenseAttachments,
          )..where((t) => t.expenseId.equals(row.id))).get(),
          syncState: await _syncStateFor(row),
        ),
    ];
  }

  /// Sync state, read from the outbox rather than from a column.
  ///
  /// A row with no pending link and a server-issued number is synced. A row whose queued
  /// intent has vanished without being reconciled is *not* quietly called synced — it is
  /// reported as pending, because something went wrong and saying "sent" would be a
  /// guess.
  Future<SyncState> _syncStateFor(ExpenseRow row) async {
    final mutationId = row.pendingMutationId;
    if (mutationId == null) {
      return row.txnNumber == null ? SyncState.pendingSync : SyncState.synced;
    }
    final entry =
        await (_db.select(_db.syncOutbox)
              ..where((t) => t.mutationId.equals(mutationId))
              ..limit(1))
            .getSingleOrNull();
    if (entry == null) return SyncState.pendingSync;
    return OutboxStatus.fromName(entry.status).userVisibleState;
  }

  /// The ledger, filtered and paged in SQL.
  ///
  /// Keyset-style: the caller asks for a window and gets exactly that. Nothing here
  /// fetches "all expenses" and narrows them in Dart — at a year of history that is the
  /// difference between a ledger that opens and one that does not (spec §27).
  Future<List<LocalExpense>> query(
    ExpenseQuery filter, {
    int limit = 100,
    int offset = 0,
  }) async {
    final select = _db.select(_db.expenses);

    // D-068: never browsable, whatever the filter asks for. First predicate rather than
    // last, so a future filter branch cannot be written that forgets it.
    select.where((t) => t.scopeRevokedAt.isNull());

    if (!filter.includeVoided) {
      select.where((t) => t.voidedAt.isNull());
    }
    if (filter.from case final from?) {
      select.where((t) => t.businessDate.isBiggerOrEqualValue(from));
    }
    if (filter.to case final to?) {
      select.where((t) => t.businessDate.isSmallerOrEqualValue(to));
    }
    if (filter.paymentStatus case final status?) {
      select.where((t) => t.paymentStatus.equals(status));
    }
    if (filter.vendorId case final vendor?) {
      select.where((t) => t.vendorId.equals(vendor));
    }
    if (filter.search case final term? when term.trim().isNotEmpty) {
      final needle = '%${term.trim()}%';
      select.where(
        (t) => t.txnNumber.like(needle) | t.referenceNumber.like(needle),
      );
    }
    if (filter.businessUnitId case final unit?) {
      // A document is in scope of the filter if any visible line charges that unit.
      select.where(
        (t) => existsQuery(
          _db.selectOnly(_db.expenseAllocations)
            ..addColumns([_db.expenseAllocations.id])
            ..where(
              _db.expenseAllocations.expenseId.equalsExp(t.id) &
                  _db.expenseAllocations.businessUnitId.equals(unit),
            ),
        ),
      );
    }
    if (filter.categoryId case final category?) {
      select.where(
        (t) => existsQuery(
          _db.selectOnly(_db.expenseAllocations)
            ..addColumns([_db.expenseAllocations.id])
            ..where(
              _db.expenseAllocations.expenseId.equalsExp(t.id) &
                  _db.expenseAllocations.categoryId.equals(category),
            ),
        ),
      );
    }

    select
      ..orderBy([
        (t) =>
            OrderingTerm(expression: t.businessDate, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.capturedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);

    final rows = await select.get();
    final loaded = <LocalExpense>[];
    for (final row in rows) {
      final expense = await _hydrate(row);
      // Sync state is derived from the outbox, so it cannot be a SQL predicate without
      // duplicating it into a column. The window is already bounded by the query above,
      // so filtering it here costs nothing meaningful.
      if (filter.syncState != null && expense.syncState != filter.syncState) {
        continue;
      }
      loaded.add(expense);
    }
    return loaded;
  }

  Future<LocalExpense> _hydrate(ExpenseRow row) async => LocalExpense(
    row: row,
    allocations:
        await (_db.select(_db.expenseAllocations)
              ..where((t) => t.expenseId.equals(row.id))
              ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
            .get(),
    periodContributions: await (_db.select(
      _db.expensePeriodAllocations,
    )..where((t) => t.expenseId.equals(row.id))).get(),
    attachments: await (_db.select(
      _db.expenseAttachments,
    )..where((t) => t.expenseId.equals(row.id))).get(),
    syncState: await _syncStateFor(row),
  );

  /// Documents kept through a confirmed scope revocation because they still carry this
  /// actor's own unsynced intent (D-068).
  ///
  /// The dedicated pending / rejected / conflict workflow, and the only read that returns
  /// them. They are deliberately absent from [list], [query] and [contributionTotal]:
  /// authority over the property is gone, so presenting these as ledger rows or letting
  /// them move a total would be exactly the leak the purge exists to close. What they
  /// remain is *evidence* — what this person submitted, and what became of it.
  ///
  /// Ownership is the outbox's, not this table's: `dueEntries` filters by
  /// `actor_user_id` (D-050), so another user signing in on the same installation can
  /// neither push nor inherit this work, and the session's own scope decides what they
  /// are shown.
  Future<List<LocalExpense>> listRetainedAfterRevocation() async {
    final rows =
        await (_db.select(_db.expenses)
              ..where((t) => t.scopeRevokedAt.isNotNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.scopeRevokedAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  /// Everything this device holds for a business unit's contributions in one period.
  ///
  /// Reads `expense_period_allocations` and nothing else — the one reporting source
  /// (D-060). A caller cannot accidentally add line amounts to contribution amounts here,
  /// because line amounts are not in the result.
  Future<Money> contributionTotal({
    required String periodKey,
    String? businessUnitId,
  }) async {
    final query =
        _db.select(_db.expensePeriodAllocations).join([
          innerJoin(
            _db.expenses,
            _db.expenses.id.equalsExp(_db.expensePeriodAllocations.expenseId),
          ),
        ])..where(
          _db.expensePeriodAllocations.pnlPeriodKey.equals(periodKey) &
              _db.expenses.voidedAt.isNull() &
              // A retained document contributes nothing to any figure. It is somebody's
              // unsent attempt over a property they no longer hold (D-068).
              _db.expenses.scopeRevokedAt.isNull(),
        );
    if (businessUnitId != null) {
      query.where(
        _db.expensePeriodAllocations.businessUnitId.equals(businessUnitId),
      );
    }
    final rows = await query.get();
    return Money.fromPaise(
      rows.fold<int>(
        0,
        (sum, r) => sum + r.readTable(_db.expensePeriodAllocations).amountMinor,
      ),
    );
  }
}

/// Convenience for a business date read back out of the local text column.
BusinessDate? parseLocalDate(String? iso) =>
    iso == null ? null : BusinessDate.tryParse(iso);
