/// Recording revenue: eligibility, one atomic local write, and the queued intent.
///
/// The shape is the expense engine's, deliberately (D-060, D-072a): a document and its
/// parts and the outbox entry all go in **one** Drift transaction, so there is no moment
/// at which a financial record exists without the intent to send it, or the reverse.
///
/// ## The one real departure from expenses, and why
///
/// An expense always saves locally. Its correctness does not depend on configuration the
/// device might lack — an amount, a vendor and a category are facts the operator supplies.
/// A revenue figure's correctness does: the tax comes from configured rules, and a device
/// that cannot resolve them cannot produce a defensible number.
///
/// So revenue is checked **before** anything is written (D-086). A queued entry whose tax
/// could not be computed would be refused by the server anyway, and a rejected revenue
/// entry sitting in somebody's outbox is worse than being told at the time that it cannot
/// yet be recorded.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Why a revenue entry may not be recorded, in terms a person can act on.
///
/// Each value names a **different** thing to do about it, which is the whole reason there
/// are this many. "Cannot save" tells an operator nothing, and a raw exception tells them
/// something they cannot act on and should not see.
enum RevenueRefusalReason {
  /// The device holds no confirmed authority for this user at all.
  notAuthenticated,

  /// Authority is held, and does not cover this property.
  notAuthorisedForUnit,

  /// The period this business date falls in is closed.
  periodClosed,

  /// The category is unknown here, or does not belong to that property.
  invalidCategory,

  /// This device has never received the configuration for this scope.
  configurationNeverSynchronised,

  /// It was received and the authority to hold it was withdrawn (D-070).
  configurationRevoked,

  /// Some datasets arrived and others did not.
  configurationIncomplete,

  /// Older than D-112's window for creating **new** revenue offline.
  configurationExpired,

  /// The device clock cannot measure the configuration's age.
  clockUnreliable,

  /// No rule covers these facts on this date. A gap in configuration, not a zero rate.
  noApplicableRule,

  /// A rule matched and cannot be used — no input basis, typically (A1).
  incompleteRule,

  /// More than one rule matched. A configuration defect, never tiebroken (D-094).
  ambiguousConfiguration,

  /// A room value band is required and was not chosen.
  missingValueBand,

  /// A supply subtype is required and was not chosen.
  missingSupplySubtype,

  /// A premises tax status is required and none is configured.
  missingPremisesStatus,

  /// The document carries no components.
  noComponents,

  /// The components do not sum to what the document claims.
  totalsDoNotReconcile,
}

/// A structured refusal: what stopped it, and what to say.
final class RevenueRefusal {
  const RevenueRefusal(this.reason, this.message, {this.detail});

  final RevenueRefusalReason reason;

  /// Plain language aimed at the person who hit it. Never contains an exception, a SQL
  /// state, a table name or an internal identifier.
  final String message;

  /// Optional structured context for a screen that wants to say something specific.
  final Map<String, Object?>? detail;

  /// Whether refreshing the configuration could change this answer.
  ///
  /// Used to decide whether to offer a refresh before presenting the refusal — the
  /// difference between "connect and try again" and "this needs somebody to fix the
  /// configuration".
  bool get refreshMayResolve => const {
    RevenueRefusalReason.configurationNeverSynchronised,
    RevenueRefusalReason.configurationIncomplete,
    RevenueRefusalReason.configurationExpired,
    RevenueRefusalReason.configurationRevoked,
  }.contains(reason);

  @override
  String toString() => 'RevenueRefusal(${reason.name}: $message)';
}

/// The outcome of asking whether a draft may be recorded.
sealed class RevenueCreateDecision {
  const RevenueCreateDecision();
}

/// Permitted, with the resolved rule for each component in the order given.
final class RevenueCreatePermitted extends RevenueCreateDecision {
  const RevenueCreatePermitted(this.resolutions);

  final List<RevenueTaxResolved> resolutions;
}

final class RevenueCreateRefused extends RevenueCreateDecision {
  const RevenueCreateRefused(this.refusal);

  final RevenueRefusal refusal;
}

/// What the server said when it accepted an entry.
final class RevenueAcceptance {
  const RevenueAcceptance({
    required this.entryId,
    required this.rowVersion,
    this.txnNumber,
    this.financialYear,
    this.serverUpdatedAt,
  });

  /// Builds one from an RPC answer, or null if the answer does not carry what is needed.
  ///
  /// Returns null rather than guessing: a replayed older result or an unrecognised shape
  /// must send the caller to re-read the server's own copy, not to invent a reconciliation.
  static RevenueAcceptance? fromResult(
    String entryId,
    Map<String, dynamic>? payload,
  ) {
    if (payload == null) return null;
    final version = payload['row_version'];
    if (version is! int) return null;
    return RevenueAcceptance(
      entryId: entryId,
      rowVersion: version,
      txnNumber: payload['txn_number'] as String?,
      financialYear: payload['financial_year']?.toString(),
      serverUpdatedAt: DateTime.tryParse('${payload['updated_at']}')?.toUtc(),
    );
  }

  final String entryId;
  final int rowVersion;
  final String? txnNumber;
  final String? financialYear;
  final DateTime? serverUpdatedAt;
}

/// A revenue entry as the local read model holds it, with its sync state.
final class RevenueLedgerRow {
  const RevenueLedgerRow({
    required this.id,
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.businessDate,
    required this.gross,
    required this.tax,
    required this.net,
    required this.componentCount,
    required this.syncState,
    this.txnNumber,
    this.voidedAt,
  });

  final String id;

  /// Null until the server has accepted the entry and issued one (spec §8.4).
  final String? txnNumber;

  final String businessUnitId;
  final String revenueCategoryId;
  final BusinessDate businessDate;

  /// Derived from the components. There is no stored header total to drift (D-078).
  final Money gross;
  final Money tax;
  final Money net;

  final int componentCount;
  final SyncState syncState;
  final DateTime? voidedAt;
}

class RevenueRepository {
  RevenueRepository(this._db, {RevenueTaxRepository? tax})
    : _tax = tax ?? RevenueTaxRepository(_db);

  final AppDatabase _db;
  final RevenueTaxRepository _tax;

  /// Everything that must be true before a draft may be written (§4).
  ///
  /// Checked **in full, before anything is persisted**. A half-created document that turns
  /// out to be ineligible is worse than a refusal, because somebody has to decide what to
  /// do with it afterwards and the schema cannot say what it was for.
  ///
  /// The client's opinion is not the boundary. Every rule here is re-decided server-side
  /// and the server's answer is final (D-037); this exists so the refusal is immediate,
  /// offline, and says something true.
  Future<RevenueCreateDecision> evaluate(
    RevenueEntryDraft draft, {
    required AuthoritySnapshot? authority,
    DateTime? now,
  }) async {
    RevenueCreateDecision refuse(
      RevenueRefusalReason reason,
      String message, {
      Map<String, Object?>? detail,
    }) => RevenueCreateRefused(RevenueRefusal(reason, message, detail: detail));

    // 1 · Somebody, confirmed. `Principal.anonymous` holds nothing, so a screen that
    // forgot to check the session still lands here (D-051).
    if (authority == null) {
      return refuse(
        RevenueRefusalReason.notAuthenticated,
        'Sign in before recording revenue.',
      );
    }

    // 2 · Authority for this property specifically. An org-wide holder covers every unit
    // by construction (D-025), so the two are asked as one question.
    final permitted = authority.grants.any(
      (g) => g.covers(Capability.revenueCreate, draft.businessUnitId),
    );
    if (!permitted) {
      return refuse(
        RevenueRefusalReason.notAuthorisedForUnit,
        'You do not have permission to record revenue for this property.',
      );
    }

    // 3 · At least one component, before anything else looks at them.
    if (draft.components.isEmpty) {
      return refuse(
        RevenueRefusalReason.noComponents,
        'Enter at least one amount.',
      );
    }

    // 4 · The category exists here and belongs to that property. The composite check
    // matters: a category id that is real but under the other unit is exactly what the
    // server's own ladder refuses (D-040).
    final category = await (_db.select(
      _db.revenueCategories,
    )..where((c) => c.id.equals(draft.revenueCategoryId))).getSingleOrNull();
    if (category == null ||
        category.businessUnitId != draft.businessUnitId ||
        category.archivedAt != null) {
      return refuse(
        RevenueRefusalReason.invalidCategory,
        'That revenue category is not available for this property.',
      );
    }

    // 5 · The period. A closed period rejects every write server-side and says so with
    // its own reason; predicting it here means the operator is told before they type.
    final lock =
        await (_db.select(_db.periodLocks)..where(
              (l) =>
                  l.businessUnitId.equals(draft.businessUnitId) &
                  l.periodKey.equals(draft.businessDate.periodKey),
            ))
            .getSingleOrNull();
    if (lock != null && lock.state == 'closed') {
      return refuse(
        RevenueRefusalReason.periodClosed,
        'That period is closed. Ask the Owner to reopen it before recording revenue '
        'in it.',
        detail: {'period': draft.businessDate.periodKey},
      );
    }

    // 6 · Configuration completeness and D-112 freshness, then 7 · exactly one rule per
    // component. Both come from the resolver, which is the same code the server's own
    // arithmetic is proven equal to (D-105).
    final eligibility = await _tax.eligibilityFor(
      userId: authority.userId,
      businessUnitId: draft.businessUnitId,
      revenueCategoryId: draft.revenueCategoryId,
      businessDate: draft.businessDate,
      components: [for (final c in draft.components) draft.factsFor(c)],
      now: now,
    );

    if (!eligibility.isAllowed) {
      return RevenueCreateRefused(_refusalFor(eligibility.refusal!));
    }

    return RevenueCreatePermitted(eligibility.resolutions);
  }

  /// Translates a resolution outcome into a refusal a person can act on (§5).
  static RevenueRefusal _refusalFor(
    RevenueTaxResolution outcome,
  ) => switch (outcome) {
    RevenueConfigurationUnavailable(:final gap) => RevenueRefusal(switch (gap) {
      RevenueConfigurationGap.neverSynchronised =>
        RevenueRefusalReason.configurationNeverSynchronised,
      RevenueConfigurationGap.revoked =>
        RevenueRefusalReason.configurationRevoked,
      RevenueConfigurationGap.expired =>
        RevenueRefusalReason.configurationExpired,
      RevenueConfigurationGap.clockUnreliable =>
        RevenueRefusalReason.clockUnreliable,
      RevenueConfigurationGap.partial =>
        RevenueRefusalReason.configurationIncomplete,
    }, outcome.message),
    RevenueTaxNoApplicableRule() => RevenueRefusal(
      RevenueRefusalReason.noApplicableRule,
      outcome.message,
    ),
    RevenueTaxIncompleteRule() => RevenueRefusal(
      RevenueRefusalReason.incompleteRule,
      outcome.message,
    ),
    RevenueTaxAmbiguous(:final candidates) => RevenueRefusal(
      RevenueRefusalReason.ambiguousConfiguration,
      outcome.message,
      detail: {
        'candidates': [for (final c in candidates) c.id],
      },
    ),
    RevenueTaxMissingFact(:final dimension) => RevenueRefusal(
      switch (dimension) {
        RevenueTaxDimension.valueBand => RevenueRefusalReason.missingValueBand,
        RevenueTaxDimension.supplySubtype =>
          RevenueRefusalReason.missingSupplySubtype,
        RevenueTaxDimension.premisesStatus =>
          RevenueRefusalReason.missingPremisesStatus,
        _ => RevenueRefusalReason.noComponents,
      },
      outcome.message,
    ),
    RevenueTaxResolved() => const RevenueRefusal(
      RevenueRefusalReason.noApplicableRule,
      'Unable to determine the tax for this entry.',
    ),
  };

  /// Writes an evaluated draft and its queued intent, atomically (§6).
  ///
  /// [resolutions] comes from [evaluate] and is not re-derived here: re-resolving between
  /// the check and the write would open a window in which the configuration changed and
  /// the entry was recorded under a rule nobody was shown.
  ///
  /// Throws if the two disagree in length, because that would mean the caller assembled a
  /// document from one check and a different set of components.
  Future<RevenueEntry> createLocally(
    RevenueEntryDraft draft, {
    required List<RevenueTaxResolved> resolutions,
    required String actorUserId,
    required String orgId,
    required String mutationId,
    required DateTime now,
  }) async {
    if (resolutions.length != draft.components.length) {
      throw ArgumentError(
        'a resolution is required for each component: '
        '${draft.components.length} components, ${resolutions.length} resolutions',
      );
    }

    // The components, with their financial explanation attached. Built before the
    // transaction so a failure to compute cannot leave a partial document behind.
    final components = <RevenueComponent>[];
    for (var i = 0; i < draft.components.length; i++) {
      final part = draft.components[i];
      final rule = resolutions[i].rule;
      final computed = rule.compute(part.enteredAmount);
      components.add(
        RevenueComponent(
          id: part.id,
          enteredAmount: part.enteredAmount,
          // Snapshotted from the rule, not from the draft: the basis says which number
          // was typed, and only the rule knows that (D-088).
          enteredBasis: rule.inputBasis!,
          gross: computed.gross,
          tax: computed.tax,
          net: computed.net,
          taxRuleId: rule.id,
          taxRateBasisPoints: rule.rateBasisPoints,
          taxTreatment: rule.treatment,
          valueBandId: rule.valueBandId,
          valueBandLabel: rule.valueBandLabel,
          valueBandFloor: rule.valueBandFloor,
          valueBandCeiling: rule.valueBandCeiling,
          supplySubtypeId: rule.supplySubtypeId,
          premisesStatusCode: rule.premisesStatusCode,
        ),
      );
    }

    final entry = RevenueEntry(
      id: draft.id,
      businessUnitId: draft.businessUnitId,
      revenueCategoryId: draft.revenueCategoryId,
      businessDate: draft.businessDate,
      capturedAt: draft.capturedAt,
      components: components,
      entryKind: draft.entryKind,
      sourceReference: draft.sourceReference,
      notes: draft.notes,
      createdBy: actorUserId,
    );

    await _db.transaction(() async {
      await _db
          .into(_db.revenueEntries)
          .insert(
            RevenueEntriesCompanion.insert(
              id: entry.id,
              orgId: orgId,
              businessUnitId: entry.businessUnitId,
              revenueCategoryId: entry.revenueCategoryId,
              businessDate: entry.businessDate.iso,
              pnlPeriodKey: entry.businessDate.periodKey,
              capturedAt: entry.capturedAt,
              entryKind: Value(entry.entryKind.wireName),
              sourceReference: Value(entry.sourceReference),
              notes: Value(entry.notes),
              createdBy: actorUserId,
              // No transaction number. The server issues it on acceptance, and inventing
              // one here would be a permanent-looking reference two offline devices could
              // both claim (spec §8.4).
              pendingMutationId: Value(mutationId),
              updatedAt: now,
            ),
          );

      for (final component in components) {
        await _db
            .into(_db.revenueComponents)
            .insert(
              RevenueComponentsCompanion.insert(
                id: component.id,
                orgId: orgId,
                revenueEntryId: entry.id,
                enteredAmountMinor: component.enteredAmount.paise,
                enteredBasis: component.enteredBasis.wireName,
                grossAmountMinor: component.gross.paise,
                taxAmountMinor: component.tax.paise,
                netAmountMinor: component.net.paise,
                taxRuleId: component.taxRuleId,
                taxRateBasisPoints: component.taxRateBasisPoints,
                taxTreatment: component.taxTreatment.name,
                valueBandId: Value(component.valueBandId),
                valueBandLabel: Value(component.valueBandLabel),
                valueBandFloorMinor: Value(component.valueBandFloor?.paise),
                valueBandCeilingMinor: Value(component.valueBandCeiling?.paise),
                supplySubtypeId: Value(component.supplySubtypeId),
                premisesStatusCode: Value(component.premisesStatusCode),
              ),
            );
      }

      // The queue entry, in the same transaction. This is the point of the method: there
      // is no ordering in which a revenue document exists without the intent to send it,
      // or an intent points at a document that was never written.
      await _db
          .into(_db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              mutationId: mutationId,
              // D-050/D-074: whose intent this is. Never null, so no restore path can
              // ever be based on business-unit scope alone.
              actorUserId: Value(actorUserId),
              entityType: revenueEntityType,
              entityId: entry.id,
              op: MutationOp.create.name,
              payload: jsonEncode(createPayload(entry)),
              nextAttemptAt: now,
              status: OutboxStatus.pending.name,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });

    return entry;
  }

  /// The canonical document, in the shape `revenue_create` takes.
  ///
  /// Captured at save time and stored verbatim, so what is delivered is what the operator
  /// intended when they pressed save. A retry sends these same facts — it does not
  /// re-resolve them against configuration that has since arrived (§7).
  ///
  /// **The rate and the tax are not sent as instructions.** `declared_*` is what the
  /// operator was shown; the server computes its own and refuses on disagreement (KM030),
  /// so a rule that changed in between surfaces as a mismatch a person reviews rather than
  /// as a document quietly holding different money.
  static Map<String, Object?> createPayload(RevenueEntry entry) => {
    'p_id': entry.id,
    'p_business_unit_id': entry.businessUnitId,
    'p_revenue_category_id': entry.revenueCategoryId,
    'p_business_date': entry.businessDate.iso,
    'p_entry_kind': entry.entryKind.wireName,
    'p_source_reference': entry.sourceReference,
    'p_notes': entry.notes,
    'p_captured_at': entry.capturedAt.toIso8601String(),
    'p_components': [
      for (final c in entry.components)
        {
          'id': c.id,
          'entered_amount_minor': c.enteredAmount.paise,
          'value_band_id': c.valueBandId,
          'supply_subtype_id': c.supplySubtypeId,
          'premises_status_code': c.premisesStatusCode,
          'declared_gross_minor': c.gross.paise,
          'declared_tax_minor': c.tax.paise,
          'declared_net_minor': c.net.paise,
        },
    ],
  };

  /// Applies the server's answer to the local row.
  ///
  /// **Only the fields the server actually restated.** D-072a records what happens
  /// otherwise: writing every field back erased the server-issued transaction number on
  /// every edit, because the update RPC returns only a row version. A field the server did
  /// not mention is left alone.
  Future<void> reconcileAcceptance(RevenueAcceptance acceptance) =>
      _db.transaction(() async {
        await (_db.update(
          _db.revenueEntries,
        )..where((e) => e.id.equals(acceptance.entryId))).write(
          RevenueEntriesCompanion(
            rowVersion: Value(acceptance.rowVersion),
            txnNumber: acceptance.txnNumber == null
                ? const Value.absent()
                : Value(acceptance.txnNumber),
            financialYear: acceptance.financialYear == null
                ? const Value.absent()
                : Value(acceptance.financialYear),
            serverUpdatedAt: acceptance.serverUpdatedAt == null
                ? const Value.absent()
                : Value(acceptance.serverUpdatedAt),
            // The intent is delivered; the row is no longer waiting on one.
            pendingMutationId: const Value(null),
          ),
        );
      });

  /// The entries this actor may browse (§21).
  ///
  /// Excludes anything stamped `scope_revoked_at`: retained work is reachable only through
  /// the dedicated pending/rejected workflow, never through the ordinary ledger (D-070).
  Future<List<RevenueLedgerRow>> list({
    Set<String>? businessUnitIds,
    bool includeVoided = false,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT e.id, e.txn_number, e.business_unit_id, e.revenue_category_id, '
          '       e.business_date, e.voided_at, e.pending_mutation_id, '
          '       COUNT(c.id) AS components, '
          '       COALESCE(SUM(c.gross_amount_minor), 0) AS gross, '
          '       COALESCE(SUM(c.tax_amount_minor), 0) AS tax, '
          '       COALESCE(SUM(c.net_amount_minor), 0) AS net, '
          '       o.status AS outbox_status '
          '  FROM revenue_entries e '
          '  LEFT JOIN revenue_components c ON c.revenue_entry_id = e.id '
          '  LEFT JOIN sync_outbox o ON o.entity_id = e.id '
          "                        AND o.entity_type = '$revenueEntityType' "
          "                        AND o.status <> 'done' "
          ' WHERE e.scope_revoked_at IS NULL '
          '${includeVoided ? '' : '   AND e.voided_at IS NULL '}'
          ' GROUP BY e.id '
          ' ORDER BY e.business_date DESC, e.captured_at DESC',
        )
        .get();

    return [
      for (final row in rows)
        if (businessUnitIds == null ||
            businessUnitIds.contains(row.data['business_unit_id']))
          RevenueLedgerRow(
            id: row.data['id']! as String,
            txnNumber: row.data['txn_number'] as String?,
            businessUnitId: row.data['business_unit_id']! as String,
            revenueCategoryId: row.data['revenue_category_id']! as String,
            businessDate: _date(row.data['business_date']! as String),
            gross: Money.fromPaise(row.data['gross']! as int),
            tax: Money.fromPaise(row.data['tax']! as int),
            net: Money.fromPaise(row.data['net']! as int),
            componentCount: row.data['components']! as int,
            voidedAt: row.data['voided_at'] == null
                ? null
                : DateTime.tryParse('${row.data['voided_at']}'),
            syncState: _stateOf(
              row.data['outbox_status'] as String?,
              row.data['txn_number'] as String?,
            ),
          ),
    ];
  }

  /// One entry with its components, for a detail surface.
  Future<RevenueEntry?> load(String id) async {
    final header = await (_db.select(
      _db.revenueEntries,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    if (header == null) return null;

    final rows = await (_db.select(
      _db.revenueComponents,
    )..where((c) => c.revenueEntryId.equals(id))).get();
    if (rows.isEmpty) return null;

    return RevenueEntry(
      id: header.id,
      txnNumber: header.txnNumber,
      businessUnitId: header.businessUnitId,
      revenueCategoryId: header.revenueCategoryId,
      businessDate: _date(header.businessDate),
      capturedAt: header.capturedAt,
      entryKind: RevenueEntryKind.fromName(header.entryKind),
      sourceReference: header.sourceReference,
      notes: header.notes,
      createdBy: header.createdBy,
      rowVersion: header.rowVersion,
      voidedAt: header.voidedAt,
      voidReason: header.voidReason,
      components: [
        for (final c in rows)
          RevenueComponent(
            id: c.id,
            enteredAmount: Money.fromPaise(c.enteredAmountMinor),
            enteredBasis: EnteredBasis.fromName(c.enteredBasis),
            gross: Money.fromPaise(c.grossAmountMinor),
            tax: Money.fromPaise(c.taxAmountMinor),
            net: Money.fromPaise(c.netAmountMinor),
            taxRuleId: c.taxRuleId,
            taxRateBasisPoints: c.taxRateBasisPoints,
            taxTreatment: TaxTreatment.fromName(c.taxTreatment),
            valueBandId: c.valueBandId,
            valueBandLabel: c.valueBandLabel,
            valueBandFloor: c.valueBandFloorMinor == null
                ? null
                : Money.fromPaise(c.valueBandFloorMinor!),
            valueBandCeiling: c.valueBandCeilingMinor == null
                ? null
                : Money.fromPaise(c.valueBandCeilingMinor!),
            supplySubtypeId: c.supplySubtypeId,
            premisesStatusCode: c.premisesStatusCode,
          ),
      ],
    );
  }

  /// Entries kept through a confirmed revocation because this actor still has unsent work
  /// on them (D-070, D-074). Never part of the ordinary ledger.
  Future<List<String>> listRetainedAfterRevocation(String actorUserId) async {
    final rows = await _db
        .customSelect(
          'SELECT e.id FROM revenue_entries e '
          ' WHERE e.scope_revoked_at IS NOT NULL '
          '   AND EXISTS (SELECT 1 FROM sync_outbox o '
          "               WHERE o.entity_type = '$revenueEntityType' "
          '                 AND o.entity_id = e.id '
          "                 AND o.status <> 'done' "
          '                 AND o.actor_user_id = ?)',
          variables: [Variable<String>(actorUserId)],
        )
        .get();
    return [for (final row in rows) row.data['id']! as String];
  }

  /// Sync state, read from the outbox rather than from a column.
  ///
  /// Delegates to [OutboxStatus.userVisibleState], which is the project's one mapping
  /// from queue status to what a person is shown. A second copy here — even one that
  /// agreed today — is how two surfaces start describing the same entry differently, and
  /// the first version of this method was exactly that: it mapped `blocked` to a failure
  /// where the canonical mapping calls it pending, because a paused queue has not failed
  /// at anything.
  ///
  /// A row with no queued intent and a server-issued number is synced. One whose intent
  /// has vanished without being reconciled is reported as pending rather than quietly
  /// called synced, because something went wrong and saying "sent" would be a guess.
  static SyncState _stateOf(String? outboxStatus, String? txnNumber) {
    if (outboxStatus == null) {
      return txnNumber == null ? SyncState.pendingSync : SyncState.synced;
    }
    return OutboxStatus.fromName(outboxStatus).userVisibleState;
  }

  static BusinessDate _date(String iso) {
    final parts = iso.split('-').map(int.parse).toList();
    return BusinessDate.of(parts[0], parts[1], parts[2]);
  }
}

/// The outbox `entity_type` revenue intents carry.
///
/// Named once, here, because the routing endpoint, the repository, the browse query and
/// the retention predicate must all agree — and a string spelled four times is a string
/// that will one day be spelled three ways.
const revenueEntityType = 'revenue_entry';
