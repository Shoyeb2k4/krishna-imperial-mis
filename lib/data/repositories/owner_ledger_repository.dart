/// The Owner Ledger read model and its write path.
///
/// Phase 5 OA-1. Built on the transport the expense and revenue engines already proved —
/// one outbox, one worker, one backoff clock, one actor filter — rather than a second
/// synchronisation philosophy (§18, §25).
///
/// ## Everything below the surface is the shape revenue settled on
///
/// * a local write and its outbox intent commit in **one transaction**, so there is no
///   ordering in which a movement exists without the intent to send it;
/// * `mutation_id` answers *"have I already applied this exact intent"* and
///   `base_row_version` answers *"is it still based on current state"* — two mechanisms,
///   never conflated (D-021);
/// * a document has **at most one queued intent**, and a correction rewrites it in place
///   (D-125). The expense shape — a fresh intent per edit — has two reachable failure
///   modes, and both of them apply here for the same reasons;
/// * a rewritten *update* carries the base version of the correction being written, so a
///   correction re-applied after a conflict is not refused on the version it was already
///   refused on (D-130);
/// * no transaction number is ever invented locally.
///
/// ## What this file deliberately does not do
///
/// It computes **no balance and no entitlement**. Owner Settlement is OA-3's, and a
/// repository that quietly produced a closing balance would be the second definition of
/// one (OA-D2). It also writes to no expense or revenue table — asserted by a structural
/// guard rather than argued, because §40 and §41 are the invariants this whole slice is
/// judged against.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_family.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_ledger.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// The outbox entity type for an owner movement.
const String ownerMovementEntityType = 'owner_ledger_entry';

// ── Refusals ────────────────────────────────────────────────────────────────

/// Why an owner movement could not be recorded or changed.
///
/// Structured rather than a bare "cannot save", and each value names a different thing to
/// do about it — the discipline D-113 established for revenue. A test asserts no message
/// carries an exception, a SQL state, a table name or a refusal code.
enum OwnerLedgerRefusalReason {
  /// The device holds no confirmed authority for this user at all.
  notAuthenticated,

  /// Authority is held and does not cover this property for this kind of movement.
  notAuthorisedForUnit,

  /// The period this business date falls in is closed.
  periodClosed,

  /// No owner was named, or the one named is unknown here.
  unknownOwner,

  /// No consumer was named on a consumption, or the person is unknown on that date.
  unknownConsumer,

  /// The person is known and is not approved for non-chargeable consumption.
  consumerNotApprovedForNc,

  /// The owner shown to the operator is not the one the mapping resolves to.
  ///
  /// A **conflict of fact**, not a permission problem: the operator approved a statement
  /// about one owner and the canonical mapping says another (§12).
  attributionMismatch,

  /// A movement whose type states its own direction was recorded without one.
  directionRequired,

  /// A manual adjustment with no reason, or only whitespace.
  reasonRequired,

  /// A void with no reason, or only whitespace.
  voidReasonRequired,

  /// A negative amount. The type decides the sign; an amount never carries it (§43).
  negativeAmount,

  /// The movement has been voided, and a voided record is immutable (D-006).
  alreadyVoided,

  /// A void was attempted on a movement whose create is still queued.
  ///
  /// There is nothing on the server to void, and cancelling the create instead is a
  /// different decision — one this layer does not take on somebody's behalf (D-125).
  notYetOnTheServer,

  /// The movement is not in this device's ledger at all.
  unknownMovement,
}

/// A structured refusal: what stopped it, and what to say.
final class OwnerLedgerRefusal {
  const OwnerLedgerRefusal(this.reason, this.message, {this.detail});

  final OwnerLedgerRefusalReason reason;

  /// Plain language aimed at the person who hit it. Never an exception, a SQL state, a
  /// table name or an internal identifier.
  final String message;

  final Map<String, Object?>? detail;

  @override
  String toString() => 'OwnerLedgerRefusal(${reason.name}: $message)';
}

/// The outcome of asking whether a movement may be recorded.
sealed class OwnerMovementDecision {
  const OwnerMovementDecision();
}

/// Permitted, with the owner the server will be asked to agree with.
final class OwnerMovementPermitted extends OwnerMovementDecision {
  const OwnerMovementPermitted({
    required this.ownerId,
    required this.direction,
  });
  final String ownerId;
  final OwnerLedgerDirection direction;
}

final class OwnerMovementRefused extends OwnerMovementDecision {
  const OwnerMovementRefused(this.refusal);
  final OwnerLedgerRefusal refusal;
}

/// What a person is about to record.
final class OwnerMovementDraft {
  const OwnerMovementDraft({
    required this.id,
    required this.businessUnitId,
    required this.businessDate,
    required this.movementType,
    required this.amount,
    required this.capturedAt,
    this.ownerId,
    this.direction,
    this.familyMemberId,
    this.collectedByFamilyMemberId,
    this.ncBillReference,
    this.paymentMethodId,
    this.referenceNumber,
    this.remarks,
    this.reason,
  });

  final String id;
  final String businessUnitId;
  final BusinessDate businessDate;
  final OwnerMovementType movementType;
  final Money amount;
  final DateTime capturedAt;

  /// Named for every type except a consumption, where it is **derived** from the person
  /// (§12) and must not be chosen.
  final String? ownerId;

  /// Required where the type does not fix one.
  final OwnerLedgerDirection? direction;

  final String? familyMemberId;
  final String? collectedByFamilyMemberId;
  final String? ncBillReference;
  final String? paymentMethodId;
  final String? referenceNumber;
  final String? remarks;
  final String? reason;
}

/// What the server said when it accepted a movement.
final class OwnerMovementAcceptance {
  const OwnerMovementAcceptance({
    required this.entryId,
    required this.rowVersion,
    this.txnNumber,
    this.financialYear,
    this.ownerId,
    this.businessDateSource,
  });

  /// Builds one from an RPC answer, or **null** when the answer does not carry what is
  /// needed.
  ///
  /// Null rather than a guess: a replayed older result or an unrecognised shape must send
  /// the caller to re-read the server's own copy, not to invent a reconciliation.
  static OwnerMovementAcceptance? fromResult(Map<String, Object?> result) {
    final id = result['id'];
    final rowVersion = result['row_version'];
    if (id is! String || rowVersion is! int) return null;
    return OwnerMovementAcceptance(
      entryId: id,
      rowVersion: rowVersion,
      txnNumber: result['txn_number'] as String?,
      financialYear: result['financial_year'] as String?,
      ownerId: result['owner_id'] as String?,
      businessDateSource: result['business_date_source'] as String?,
    );
  }

  final String entryId;
  final int rowVersion;
  final String? txnNumber;
  final String? financialYear;
  final String? ownerId;
  final String? businessDateSource;
}

/// A query over the operational owner ledger.
///
/// An interface the presentation implements, so the data layer never learns that a filter
/// bar exists — the shape D-121 settled on for the revenue ledger.
abstract interface class OwnerLedgerQuery {
  /// Authority, not a filter. `Clear filters` cannot drop it.
  Set<String>? get businessUnitIds;

  String? get ownerId;
  String? get businessUnitId;
  OwnerMovementType? get movementType;
  BusinessDate? get from;
  BusinessDate? get to;
  bool get includeVoided;
  int get limit;
  int get offset;
}

// ── The repository ──────────────────────────────────────────────────────────

class OwnerLedgerRepository {
  OwnerLedgerRepository(this._db);

  final AppDatabase _db;

  // ── Reference reads ───────────────────────────────────────────────────────

  Future<List<Owner>> owners({bool includeArchived = false}) async {
    final rows =
        await (_db.select(_db.owners)
              ..where((o) => includeArchived ? const Constant(true) : o.active)
              ..orderBy([(o) => OrderingTerm.asc(o.displayName)]))
            .get();
    return [
      for (final row in rows)
        Owner(
          id: row.id,
          orgId: row.orgId,
          code: row.code,
          displayName: row.displayName,
          active: row.active,
          archivedAt: row.archivedAt,
        ),
    ];
  }

  /// The configured shares, as the domain reads them.
  Future<OwnershipShareSet> ownershipShares() async {
    final rows = await _db.select(_db.ownershipShares).get();
    return OwnershipShareSet([
      for (final row in rows)
        OwnershipShare(
          id: row.id,
          ownerId: row.ownerId,
          shareBasisPoints: row.shareBasisPoints,
          effectiveFrom: BusinessDate.tryParse(row.effectiveFrom)!,
          effectiveTo: row.effectiveTo == null
              ? null
              : BusinessDate.tryParse(row.effectiveTo!),
        ),
    ]);
  }

  /// The family links, as the domain reads them.
  Future<FamilyOwnerMapping> familyMapping() async {
    final rows = await _db.select(_db.ownerFamilyMembers).get();
    return FamilyOwnerMapping([
      for (final row in rows)
        OwnerFamilyMember(
          id: row.id,
          orgId: row.orgId,
          ownerId: row.ownerId,
          displayName: row.displayName,
          relationshipLabel: row.relationshipLabel,
          isSelf: row.isSelf,
          mayUseNc: row.mayUseNc,
          effectiveFrom: BusinessDate.tryParse(row.effectiveFrom)!,
          effectiveTo: row.effectiveTo == null
              ? null
              : BusinessDate.tryParse(row.effectiveTo!),
          active: row.active,
        ),
    ]);
  }

  // ── Eligibility ───────────────────────────────────────────────────────────

  /// Whether a draft may be recorded, and against which owner.
  ///
  /// Evaluated **before** anything is written, so nothing half-created is left behind for
  /// somebody to deal with later — the discipline D-113 established for revenue, and it
  /// applies here for a related reason: a consumption's owner comes from configured
  /// reference data, so a device that cannot resolve it cannot produce a defensible
  /// attribution.
  ///
  /// The server re-decides every one of these and its answer is final (D-037). This exists
  /// so the operator is told at the button rather than after a sync.
  Future<OwnerMovementDecision> evaluate(
    OwnerMovementDraft draft, {
    required bool periodOpen,
    required bool authorisedForUnit,
    required bool authenticated,
  }) async {
    if (!authenticated) {
      return const OwnerMovementRefused(
        OwnerLedgerRefusal(
          OwnerLedgerRefusalReason.notAuthenticated,
          'Sign in before recording anything against an owner account.',
        ),
      );
    }
    if (!authorisedForUnit) {
      return const OwnerMovementRefused(
        OwnerLedgerRefusal(
          OwnerLedgerRefusalReason.notAuthorisedForUnit,
          'You do not have permission to record this at this property.',
        ),
      );
    }
    if (draft.amount.isNegative) {
      return const OwnerMovementRefused(
        OwnerLedgerRefusal(
          OwnerLedgerRefusalReason.negativeAmount,
          'An amount cannot be negative. Choose the kind of movement instead — '
          'that is what decides whether it adds to or reduces the account.',
        ),
      );
    }
    if (!periodOpen) {
      return OwnerMovementRefused(
        OwnerLedgerRefusal(
          OwnerLedgerRefusalReason.periodClosed,
          'This period has been closed. It has to be reopened before anything '
          'can be recorded in it.',
          detail: {'period_key': draft.businessDate.periodKey},
        ),
      );
    }

    final fixed = draft.movementType.fixedDirection;
    final direction = fixed ?? draft.direction;
    if (direction == null) {
      return OwnerMovementRefused(
        OwnerLedgerRefusal(
          OwnerLedgerRefusalReason.directionRequired,
          'Say whether this adds to or reduces the owner account.',
          detail: {'movement_type': draft.movementType.wireName},
        ),
      );
    }

    if (draft.movementType.requiresReason &&
        (draft.reason == null || draft.reason!.trim().isEmpty)) {
      return const OwnerMovementRefused(
        OwnerLedgerRefusal(
          OwnerLedgerRefusalReason.reasonRequired,
          'An adjustment states why it was made.',
        ),
      );
    }

    // ── Who it belongs to ───────────────────────────────────────────────────
    if (draft.movementType.namesConsumer) {
      if (draft.familyMemberId == null) {
        return const OwnerMovementRefused(
          OwnerLedgerRefusal(
            OwnerLedgerRefusalReason.unknownConsumer,
            'Choose who consumed this.',
          ),
        );
      }
      final mapping = await familyMapping();
      final attribution = mapping.attribute(
        draft.familyMemberId!,
        draft.businessDate,
        // What the surface displayed, compared and never used (§12, D-114).
        declaredOwnerId: draft.ownerId,
      );
      return switch (attribution) {
        FamilyAttributed(:final ownerId) => OwnerMovementPermitted(
          ownerId: ownerId,
          direction: direction,
        ),
        FamilyAttributionRefused(refusal: final r) => OwnerMovementRefused(
          switch (r) {
            FamilyAttributionRefusal.unknownPerson => const OwnerLedgerRefusal(
              OwnerLedgerRefusalReason.unknownConsumer,
              'That person was not an approved family member on this date.',
            ),
            FamilyAttributionRefusal.notApprovedForNc =>
              const OwnerLedgerRefusal(
                OwnerLedgerRefusalReason.consumerNotApprovedForNc,
                'That person is not approved for non-chargeable consumption.',
              ),
            FamilyAttributionRefusal.ambiguousMapping =>
              const OwnerLedgerRefusal(
                OwnerLedgerRefusalReason.unknownConsumer,
                'This person is linked to more than one owner on that date. '
                'Somebody has to correct the family list before this can be '
                'recorded.',
              ),
            FamilyAttributionRefusal.declaredOwnerMismatch =>
              const OwnerLedgerRefusal(
                OwnerLedgerRefusalReason.attributionMismatch,
                'This bill belongs to a different owner than the one on screen. '
                'Open it again to see the current attribution.',
              ),
          },
        ),
      };
    }

    if (draft.ownerId == null) {
      return const OwnerMovementRefused(
        OwnerLedgerRefusal(
          OwnerLedgerRefusalReason.unknownOwner,
          'Choose which owner this belongs to.',
        ),
      );
    }
    final known = await (_db.select(
      _db.owners,
    )..where((o) => o.id.equals(draft.ownerId!))).getSingleOrNull();
    if (known == null) {
      return const OwnerMovementRefused(
        OwnerLedgerRefusal(
          OwnerLedgerRefusalReason.unknownOwner,
          'That owner is not on this device. Connect to the internet so the '
          'owner list can be brought up to date.',
        ),
      );
    }

    return OwnerMovementPermitted(
      ownerId: draft.ownerId!,
      direction: direction,
    );
  }

  // ── Create ────────────────────────────────────────────────────────────────

  /// Writes the movement and its outbox intent in **one transaction**.
  ///
  /// The point of the method: there is no ordering in which a movement exists without the
  /// intent to send it, or an intent points at a movement that was never written.
  Future<OwnerLedgerEntry> createLocally(
    OwnerMovementDraft draft, {
    required String ownerId,
    required OwnerLedgerDirection direction,
    required String actorUserId,
    required String orgId,
    required String mutationId,
    required DateTime now,
  }) async {
    final entry = OwnerLedgerEntry(
      id: draft.id,
      orgId: orgId,
      ownerId: ownerId,
      businessUnitId: draft.businessUnitId,
      businessDate: draft.businessDate,
      movementType: draft.movementType,
      direction: direction,
      amount: draft.amount,
      createdByUserId: actorUserId,
      capturedAt: draft.capturedAt,
      familyMemberId: draft.familyMemberId,
      collectedByFamilyMemberId: draft.collectedByFamilyMemberId,
      ncBillReference: draft.ncBillReference,
      paymentMethodId: draft.paymentMethodId,
      referenceNumber: draft.referenceNumber,
      remarks: draft.remarks,
      reason: draft.reason?.trim(),
    );

    await _db.transaction(() async {
      await _db
          .into(_db.ownerLedgerEntries)
          .insert(
            OwnerLedgerEntriesCompanion.insert(
              id: entry.id,
              orgId: orgId,
              ownerId: entry.ownerId,
              businessUnitId: entry.businessUnitId,
              businessDate: entry.businessDate.iso,
              pnlPeriodKey: entry.businessDate.periodKey,
              // A freshly recorded movement's trading day was derived by the cut-off
              // rule. Stated rather than left to the column default, and overwritten by
              // the canonical answer on reconciliation rather than the two sides being
              // trusted to agree on a constant (D-143).
              businessDateSource: Value(BusinessDateSource.derived.wireName),
              movementType: entry.movementType.wireName,
              direction: entry.direction.wireName,
              amountMinor: entry.amount.paise,
              familyMemberId: Value(entry.familyMemberId),
              collectedByFamilyMemberId: Value(entry.collectedByFamilyMemberId),
              ncBillReference: Value(entry.ncBillReference),
              paymentMethodId: Value(entry.paymentMethodId),
              referenceNumber: Value(entry.referenceNumber),
              remarks: Value(entry.remarks),
              reason: Value(entry.reason),
              createdBy: actorUserId,
              capturedAt: entry.capturedAt,
              // No transaction number. The server issues it on acceptance; inventing one
              // here would be a permanent-looking reference two offline devices could
              // both claim (D-085).
              pendingMutationId: Value(mutationId),
              updatedAt: now,
            ),
          );

      await _db
          .into(_db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              mutationId: mutationId,
              // D-050 / D-074: whose intent this is. Never null, so no restore path can
              // be based on business-unit scope alone.
              actorUserId: Value(actorUserId),
              entityType: ownerMovementEntityType,
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

  /// The canonical movement, in the shape `owner_movement_create` takes.
  ///
  /// Captured at save time and stored verbatim, so what is delivered is what the operator
  /// intended when they pressed save.
  ///
  /// `p_declared_owner_id` is sent for a consumption and is **compared, never used**: the
  /// server resolves the mapping itself and refuses on disagreement, so a link that
  /// changed between opening the form and pressing save surfaces as something a person
  /// reviews rather than as a bill quietly landing on the wrong account (§12, D-114).
  static Map<String, Object?> createPayload(OwnerLedgerEntry entry) => {
    'p_id': entry.id,
    'p_business_unit_id': entry.businessUnitId,
    'p_business_date': entry.businessDate.iso,
    'p_movement_type': entry.movementType.wireName,
    'p_amount_minor': entry.amount.paise,
    'p_direction': entry.direction.wireName,
    'p_family_member_id': entry.familyMemberId,
    'p_declared_owner_id': entry.movementType.namesConsumer
        ? entry.ownerId
        : null,
    'p_owner_id': entry.movementType.namesConsumer ? null : entry.ownerId,
    'p_collected_by_family_member_id': entry.collectedByFamilyMemberId,
    'p_nc_bill_reference': entry.ncBillReference,
    'p_payment_method_id': entry.paymentMethodId,
    'p_reference_number': entry.referenceNumber,
    'p_remarks': entry.remarks,
    'p_reason': entry.reason,
    'p_captured_at': entry.capturedAt.toIso8601String(),
  };

  static Map<String, Object?> updatePayload(
    OwnerLedgerEntry entry, {
    required int baseRowVersion,
    String? correctionReason,
  }) => {
    'p_id': entry.id,
    'p_base_row_version': baseRowVersion,
    'p_business_date': entry.businessDate.iso,
    'p_amount_minor': entry.amount.paise,
    'p_direction': entry.direction.wireName,
    'p_collected_by_family_member_id': entry.collectedByFamilyMemberId,
    'p_nc_bill_reference': entry.ncBillReference,
    'p_payment_method_id': entry.paymentMethodId,
    'p_reference_number': entry.referenceNumber,
    'p_remarks': entry.remarks,
    'p_reason': entry.reason,
    'p_correction_reason': correctionReason,
  };

  static Map<String, Object?> voidPayload(
    String entryId, {
    required String reason,
    required int baseRowVersion,
  }) => {
    'p_id': entryId,
    'p_reason': reason,
    'p_base_row_version': baseRowVersion,
  };

  // ── Correction ────────────────────────────────────────────────────────────

  /// Applies a correction locally and rewrites whatever intent is already queued.
  ///
  /// **One queued intent per document** (D-125). The expense shape — a fresh update intent
  /// per edit — has two failure modes that are reachable rather than theoretical, and both
  /// apply here: a correction to a movement whose create then fails transiently arrives
  /// first, finds no document and is refused terminally; and two corrections before either
  /// syncs share one base version, so the second conflicts with a version its author never
  /// saw.
  ///
  /// A create stays a create — the server has never seen this movement, and sending an
  /// update for it would be asking to correct something that does not exist.
  Future<OwnerLedgerRefusal?> updateLocally(
    String entryId, {
    required Money amount,
    required BusinessDate businessDate,
    required String actorUserId,
    required int baseRowVersion,
    required String mutationId,
    required DateTime now,
    OwnerLedgerDirection? direction,
    String? collectedByFamilyMemberId,
    String? ncBillReference,
    String? paymentMethodId,
    String? referenceNumber,
    String? remarks,
    String? reason,
    String? correctionReason,
  }) async {
    final row = await (_db.select(
      _db.ownerLedgerEntries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();
    if (row == null) {
      return const OwnerLedgerRefusal(
        OwnerLedgerRefusalReason.unknownMovement,
        'That movement is not on this device.',
      );
    }
    if (row.voidedAt != null) {
      return const OwnerLedgerRefusal(
        OwnerLedgerRefusalReason.alreadyVoided,
        'This movement has been voided. Record a new one instead of changing it.',
      );
    }
    if (amount.isNegative) {
      return const OwnerLedgerRefusal(
        OwnerLedgerRefusalReason.negativeAmount,
        'An amount cannot be negative.',
      );
    }

    final type = OwnerMovementType.fromWire(row.movementType);
    final resolvedDirection =
        type.fixedDirection ??
        direction ??
        OwnerLedgerDirection.fromWire(row.direction);

    if (type.requiresReason && (reason == null || reason.trim().isEmpty)) {
      return const OwnerLedgerRefusal(
        OwnerLedgerRefusalReason.reasonRequired,
        'An adjustment states why it was made.',
      );
    }

    final corrected = _toEntry(row).copyWith(
      amount: amount,
      businessDate: businessDate,
      direction: resolvedDirection,
      collectedByFamilyMemberId: collectedByFamilyMemberId,
      ncBillReference: ncBillReference,
      paymentMethodId: paymentMethodId,
      referenceNumber: referenceNumber,
      remarks: remarks,
      reason: reason?.trim(),
    );

    await _db.transaction(() async {
      await (_db.update(
        _db.ownerLedgerEntries,
      )..where((e) => e.id.equals(entryId))).write(
        OwnerLedgerEntriesCompanion(
          amountMinor: Value(amount.paise),
          direction: Value(resolvedDirection.wireName),
          businessDate: Value(businessDate.iso),
          pnlPeriodKey: Value(businessDate.periodKey),
          collectedByFamilyMemberId: Value(collectedByFamilyMemberId),
          ncBillReference: Value(ncBillReference),
          paymentMethodId: Value(paymentMethodId),
          referenceNumber: Value(referenceNumber),
          remarks: Value(remarks),
          reason: Value(reason?.trim()),
          updatedAt: Value(now),
        ),
      );

      final queued = await _queuedIntentFor(entryId);
      if (queued == null) {
        await _db
            .into(_db.syncOutbox)
            .insert(
              SyncOutboxCompanion.insert(
                mutationId: mutationId,
                actorUserId: Value(actorUserId),
                entityType: ownerMovementEntityType,
                entityId: entryId,
                op: MutationOp.update.name,
                payload: jsonEncode(
                  updatePayload(
                    corrected,
                    baseRowVersion: baseRowVersion,
                    correctionReason: correctionReason,
                  ),
                ),
                baseRowVersion: Value(baseRowVersion),
                nextAttemptAt: now,
                status: OutboxStatus.pending.name,
                createdAt: now,
              ),
            );
        await (_db.update(
          _db.ownerLedgerEntries,
        )..where((e) => e.id.equals(entryId))).write(
          OwnerLedgerEntriesCompanion(pendingMutationId: Value(mutationId)),
        );
        return;
      }

      // Rewrite the queued intent in place. Nothing is deleted and no attribution moves:
      // the entry keeps its own mutation id, its actor and its creation time, so
      // idempotency (D-004), ownership (D-050) and retention (D-074) all still key on the
      // same values. Only the payload changes, and the payload is the operator's current
      // intent.
      final isCreate = queued.op == MutationOp.create.name;
      await (_db.update(
        _db.syncOutbox,
      )..where((o) => o.mutationId.equals(queued.mutationId))).write(
        SyncOutboxCompanion(
          payload: Value(
            jsonEncode(
              isCreate
                  ? createPayload(corrected)
                  : updatePayload(
                      corrected,
                      // **The base version of the correction being written**, not the one
                      // the queued intent already carried. A correction re-applied after a
                      // conflict would otherwise be refused on the version it was already
                      // refused on, for ever (D-130).
                      baseRowVersion: baseRowVersion,
                      correctionReason: correctionReason,
                    ),
            ),
          ),
          baseRowVersion: isCreate ? const Value(null) : Value(baseRowVersion),
          // The operator has just acted; making them wait out a backoff earned by an
          // earlier attempt would punish them for the network.
          nextAttemptAt: Value(now),
          status: Value(OutboxStatus.pending.name),
          lastError: const Value(null),
        ),
      );
    });

    return null;
  }

  // ── Void ──────────────────────────────────────────────────────────────────

  /// Stamps the movement as the actor's intent to void, and queues it.
  ///
  /// **Refuses rather than throws** for everything a person can act on. An exception
  /// reaching a widget is either a crash or a message nobody can use (D-129).
  Future<OwnerLedgerRefusal?> voidLocally(
    String entryId, {
    required String reason,
    required String actorUserId,
    required int baseRowVersion,
    required String mutationId,
    required DateTime now,
  }) async {
    if (reason.trim().isEmpty) {
      return const OwnerLedgerRefusal(
        OwnerLedgerRefusalReason.voidReasonRequired,
        'Voiding a movement states why.',
      );
    }

    final row = await (_db.select(
      _db.ownerLedgerEntries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();
    if (row == null) {
      return const OwnerLedgerRefusal(
        OwnerLedgerRefusalReason.unknownMovement,
        'That movement is not on this device.',
      );
    }
    if (row.voidedAt != null) {
      return const OwnerLedgerRefusal(
        OwnerLedgerRefusalReason.alreadyVoided,
        'This movement has already been voided.',
      );
    }
    if (row.txnNumber == null) {
      return const OwnerLedgerRefusal(
        OwnerLedgerRefusalReason.notYetOnTheServer,
        'This movement has not reached the server yet, so there is nothing to '
        'void. Wait for it to sync, then void it.',
      );
    }

    await _db.transaction(() async {
      await (_db.update(
        _db.ownerLedgerEntries,
      )..where((e) => e.id.equals(entryId))).write(
        OwnerLedgerEntriesCompanion(
          voidedAt: Value(now),
          voidedBy: Value(actorUserId),
          voidReason: Value(reason.trim()),
          updatedAt: Value(now),
          pendingMutationId: Value(mutationId),
        ),
      );

      final queued = await _queuedIntentFor(entryId);
      final payload = jsonEncode(
        voidPayload(
          entryId,
          reason: reason.trim(),
          baseRowVersion: baseRowVersion,
        ),
      );

      if (queued == null) {
        await _db
            .into(_db.syncOutbox)
            .insert(
              SyncOutboxCompanion.insert(
                mutationId: mutationId,
                actorUserId: Value(actorUserId),
                entityType: ownerMovementEntityType,
                entityId: entryId,
                op: MutationOp.void_.name,
                payload: payload,
                baseRowVersion: Value(baseRowVersion),
                nextAttemptAt: now,
                status: OutboxStatus.pending.name,
                createdAt: now,
              ),
            );
      } else {
        // A void replaces whatever was queued: it is the operator's later and more
        // decisive intent, and sending both would ask the server to correct a movement
        // and then throw the correction away (D-125).
        await (_db.update(
          _db.syncOutbox,
        )..where((o) => o.mutationId.equals(queued.mutationId))).write(
          SyncOutboxCompanion(
            op: Value(MutationOp.void_.name),
            payload: Value(payload),
            baseRowVersion: Value(baseRowVersion),
            nextAttemptAt: Value(now),
            status: Value(OutboxStatus.pending.name),
            lastError: const Value(null),
          ),
        );
      }
    });

    return null;
  }

  // ── Reconciliation ────────────────────────────────────────────────────────

  /// Applies what the server said when it accepted a movement.
  ///
  /// **Only fields the server restated are written.** Writing them all back is what erased
  /// the transaction number on every expense edit until D-072a caught it.
  Future<void> reconcileAcceptance(OwnerMovementAcceptance acceptance) async {
    await (_db.update(
      _db.ownerLedgerEntries,
    )..where((e) => e.id.equals(acceptance.entryId))).write(
      OwnerLedgerEntriesCompanion(
        rowVersion: Value(acceptance.rowVersion),
        txnNumber: acceptance.txnNumber == null
            ? const Value.absent()
            : Value(acceptance.txnNumber),
        financialYear: acceptance.financialYear == null
            ? const Value.absent()
            : Value(acceptance.financialYear),
        ownerId: acceptance.ownerId == null
            ? const Value.absent()
            : Value(acceptance.ownerId!),
        businessDateSource: acceptance.businessDateSource == null
            ? const Value.absent()
            : Value(acceptance.businessDateSource!),
        pendingMutationId: const Value(null),
      ),
    );
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  Future<OwnerLedgerEntry?> load(String entryId) async {
    final row = await (_db.select(
      _db.ownerLedgerEntries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  /// The operational ledger, filtered, ordered and paged **in SQL**.
  ///
  /// Quarantined work is excluded by the **first** predicate, before any filter is
  /// considered, so no future branch can be written that forgets it (D-121).
  ///
  /// Ordering carries an `id` tie-break. Two movements recorded in the same second on the
  /// same day have no defined order without it, and an undefined order across a page
  /// boundary is exactly how a row gets shown twice or skipped.
  Future<List<OwnerLedgerEntry>> query(OwnerLedgerQuery q) async {
    final select = _db.select(_db.ownerLedgerEntries)
      ..where((e) => e.scopeRevokedAt.isNull());

    final units = q.businessUnitIds;
    if (units != null) {
      // Authority, applied in SQL and before paging. Applying it afterwards would compute
      // a window over rows the reader may not have.
      select.where((e) => e.businessUnitId.isIn(units.toList()));
    }
    if (q.businessUnitId != null) {
      select.where((e) => e.businessUnitId.equals(q.businessUnitId!));
    }
    if (q.ownerId != null) {
      select.where((e) => e.ownerId.equals(q.ownerId!));
    }
    if (q.movementType != null) {
      select.where((e) => e.movementType.equals(q.movementType!.wireName));
    }
    if (q.from != null) {
      select.where((e) => e.businessDate.isBiggerOrEqualValue(q.from!.iso));
    }
    if (q.to != null) {
      select.where((e) => e.businessDate.isSmallerOrEqualValue(q.to!.iso));
    }
    if (!q.includeVoided) {
      select.where((e) => e.voidedAt.isNull());
    }

    select
      ..orderBy([
        (e) => OrderingTerm.desc(e.businessDate),
        (e) => OrderingTerm.desc(e.capturedAt),
        (e) => OrderingTerm.desc(e.id),
      ])
      ..limit(q.limit, offset: q.offset);

    return [for (final row in await select.get()) _toEntry(row)];
  }

  /// Movements retained through a confirmed revocation because they still carry the
  /// actor's own unsent work (D-070), for that actor and nobody else (D-074).
  Future<List<OwnerLedgerEntry>> listRetainedAfterRevocation({
    required String actorUserId,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT e.* FROM owner_ledger_entries e '
          'JOIN sync_outbox o ON o.entity_id = e.id '
          "  AND o.entity_type = '$ownerMovementEntityType' "
          'WHERE e.scope_revoked_at IS NOT NULL '
          '  AND o.actor_user_id = ?1 '
          'ORDER BY e.business_date DESC, e.id DESC',
          variables: [Variable<String>(actorUserId)],
          readsFrom: {_db.ownerLedgerEntries, _db.syncOutbox},
        )
        .get();
    return [
      for (final row in rows) _toEntry(_db.ownerLedgerEntries.map(row.data)),
    ];
  }

  /// One movement's sync state, derived from the outbox.
  ///
  /// **Joined on the document's id**, which is the derivation the ledger uses, so the two
  /// surfaces cannot describe one movement differently — the duplication D-131 had to
  /// remove from the revenue surfaces after it reported `Synced` for a sale in conflict.
  Stream<SyncState> watchSyncState(String entryId) {
    return _db
        .customSelect(
          'SELECT o.status AS status FROM sync_outbox o '
          'WHERE o.entity_id = ?1 '
          "  AND o.entity_type = '$ownerMovementEntityType' "
          "  AND o.status <> 'done' "
          'ORDER BY o.created_at DESC LIMIT 1',
          variables: [Variable<String>(entryId)],
          readsFrom: {_db.syncOutbox, _db.ownerLedgerEntries},
        )
        .watch()
        .map((rows) {
          if (rows.isEmpty) return SyncState.synced;
          return OutboxStatus.values
              .firstWhere((s) => s.name == rows.first.read<String>('status'))
              .userVisibleState;
        });
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<SyncOutboxRow?> _queuedIntentFor(String entryId) =>
      (_db.select(_db.syncOutbox)
            ..where(
              (o) =>
                  o.entityId.equals(entryId) &
                  o.entityType.equals(ownerMovementEntityType) &
                  o.status.isNotValue(OutboxStatus.done.name),
            )
            ..orderBy([(o) => OrderingTerm.desc(o.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  OwnerLedgerEntry _toEntry(OwnerLedgerRow row) => OwnerLedgerEntry(
    id: row.id,
    orgId: row.orgId,
    ownerId: row.ownerId,
    businessUnitId: row.businessUnitId,
    businessDate: BusinessDate.tryParse(row.businessDate)!,
    businessDateSource: BusinessDateSource.fromWire(row.businessDateSource),
    movementType: OwnerMovementType.fromWire(row.movementType),
    direction: OwnerLedgerDirection.fromWire(row.direction),
    amount: Money.fromPaise(row.amountMinor),
    createdByUserId: row.createdBy,
    capturedAt: row.capturedAt,
    txnNumber: row.txnNumber,
    financialYear: row.financialYear,
    familyMemberId: row.familyMemberId,
    collectedByFamilyMemberId: row.collectedByFamilyMemberId,
    ncBillReference: row.ncBillReference,
    paymentMethodId: row.paymentMethodId,
    referenceNumber: row.referenceNumber,
    remarks: row.remarks,
    reason: row.reason,
    rowVersion: row.rowVersion,
    voidedAt: row.voidedAt,
    voidReason: row.voidReason,
    scopeRevokedAt: row.scopeRevokedAt,
  );
}

/// The one change a correction makes to a movement, so the payload can be built from the
/// corrected document rather than from a bag of parameters.
extension on OwnerLedgerEntry {
  OwnerLedgerEntry copyWith({
    Money? amount,
    BusinessDate? businessDate,
    OwnerLedgerDirection? direction,
    String? collectedByFamilyMemberId,
    String? ncBillReference,
    String? paymentMethodId,
    String? referenceNumber,
    String? remarks,
    String? reason,
  }) => OwnerLedgerEntry(
    id: id,
    orgId: orgId,
    ownerId: ownerId,
    businessUnitId: businessUnitId,
    businessDate: businessDate ?? this.businessDate,
    businessDateSource: businessDateSource,
    movementType: movementType,
    direction: direction ?? this.direction,
    amount: amount ?? this.amount,
    createdByUserId: createdByUserId,
    capturedAt: capturedAt,
    txnNumber: txnNumber,
    financialYear: financialYear,
    familyMemberId: familyMemberId,
    collectedByFamilyMemberId: collectedByFamilyMemberId,
    ncBillReference: ncBillReference,
    paymentMethodId: paymentMethodId,
    referenceNumber: referenceNumber,
    remarks: remarks,
    reason: reason,
    rowVersion: rowVersion,
    voidedAt: voidedAt,
    voidReason: voidReason,
    scopeRevokedAt: scopeRevokedAt,
  );
}
