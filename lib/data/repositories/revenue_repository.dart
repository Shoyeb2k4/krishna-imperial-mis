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
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
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

  /// A void was attempted with no reason, or with only whitespace.
  ///
  /// Its own reason rather than a generic refusal, because the thing to do about it is
  /// specific: type why. The server refuses it too (KM008); this exists so the operator
  /// is told at the button rather than after a sync.
  voidReasonRequired,

  /// The sale has been voided, and a voided document is immutable (spec §14, D-006).
  alreadyVoided,

  /// A void was attempted on a sale whose create is still queued.
  ///
  /// There is nothing on the server to void, and cancelling the create instead is a
  /// different decision — one this layer does not get to take on somebody's behalf.
  notYetOnTheServer,

  /// The components do not sum to what the document claims.
  totalsDoNotReconcile,

  /// Attaching this file would take the sale past the approved count or size limit.
  ///
  /// The same numbers as an expense, because they are the product's attachment policy
  /// and not a per-document decision. The server enforces them again where a modified
  /// client cannot skip them.
  attachmentLimit,
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
    this.businessDateSource,
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
      // Both write paths state it. Null means an older stored result that predates the
      // field, and the reconciler leaves the local value alone rather than guessing —
      // the same reason this whole type returns null rather than inventing a
      // reconciliation it cannot support.
      businessDateSource: payload['business_date_source'] is String
          ? BusinessDateSource.fromWire(
              payload['business_date_source'] as String,
            )
          : null,
    );
  }

  final String entryId;
  final int rowVersion;
  final String? txnNumber;
  final String? financialYear;
  final DateTime? serverUpdatedAt;

  /// The canonical provenance of the entry's business date, as the server stated it.
  ///
  /// Null only when the answer did not carry one, which is an older stored result being
  /// replayed. Never derived on this side (spec §9).
  final BusinessDateSource? businessDateSource;
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
    required this.entryKind,
    required this.createdBy,
    required this.rowVersion,
    this.txnNumber,
    this.sourceReference,
    this.notes,
    this.updatedAt,
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

  final RevenueEntryKind entryKind;
  final String? sourceReference;
  final String? notes;

  /// The actor who recorded it. Resolved to a name by the presentation layer where one is
  /// known; the id itself is diagnostic detail, not something to put in a column.
  final String createdBy;

  final int rowVersion;
  final DateTime? updatedAt;
  final DateTime? voidedAt;

  /// What to show where a reference belongs.
  ///
  /// Deliberately not a fabricated `KI-REV-...`: a permanent-looking reference that later
  /// changes is worse than an honest pending state (spec 8.4).
  String get displayReference =>
      txnNumber ?? 'Pending number - ${id.substring(0, 8).toUpperCase()}';
}

/// What the revenue ledger is being asked for.
///
/// An interface rather than a concrete type so the data layer does not depend on the
/// feature layer - the presentation's `RevenueFilter` implements it, and the repository
/// never learns that a filter bar exists.
abstract interface class RevenueQuery {
  /// `YYYY-MM-DD`, inclusive, against the **business date** (D-067).
  String? get from;
  String? get to;

  String? get businessUnitId;
  String? get revenueCategoryId;
  RevenueEntryKind? get entryKind;
  String? get enteredByUserId;
  SyncState? get syncState;
  String? get search;
  bool get includeVoided;

  /// The units this reader may see at all, independent of what they filtered on.
  ///
  /// Distinct from [businessUnitId], which is a choice. This is authority, and applying
  /// it in SQL rather than in Dart is what stops a paging window from being computed over
  /// rows the reader may not have.
  Set<String>? get businessUnitIds;
}

/// The unfiltered ledger, for callers that only want everything they may see.
final class _AllRevenue implements RevenueQuery {
  const _AllRevenue({required this.includeVoided, Set<String>? units})
    : businessUnitIds = units;

  @override
  final bool includeVoided;
  @override
  final Set<String>? businessUnitIds;

  @override
  String? get from => null;
  @override
  String? get to => null;
  @override
  String? get businessUnitId => null;
  @override
  String? get revenueCategoryId => null;
  @override
  RevenueEntryKind? get entryKind => null;
  @override
  String? get enteredByUserId => null;
  @override
  SyncState? get syncState => null;
  @override
  String? get search => null;
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
              // A freshly recorded sale's trading day was derived by the cut-off rule.
              // Stated rather than left to the column default, so the create path says
              // what it means — and the server states the same thing and returns it, so
              // reconciliation overwrites this with the canonical answer rather than
              // trusting the two sides to agree on a constant.
              businessDateSource: Value(BusinessDateSource.derived.wireName),
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

  /// The correction, in the shape `revenue_update` takes.
  ///
  /// Carries no rate and no tax as instructions. `declared_*` is what the operator was
  /// shown; the server resolves against the entry's category and the **new** business
  /// date and refuses on disagreement (KM030), so a rule that changed between opening the
  /// form and saving surfaces as a conflict a person resolves rather than as a document
  /// quietly holding different money (D-114).
  ///
  /// The business unit, the category and the transaction number are absent on purpose.
  /// The number belongs to the document's identity and survives every correction; the
  /// other two are not editable, because an edit that moved revenue between properties
  /// would be a scope transfer wearing a correction's clothes.
  ///
  /// [correctionReason] is sent only when the correction moves the business date, which
  /// the server decides for itself from canonical state (spec §9). It rides in the
  /// durable payload, so an authorised correction queued offline still carries its reason
  /// when it is finally delivered.
  static Map<String, Object?> updatePayload(
    RevenueEntry entry, {
    String? correctionReason,
  }) => {
    'p_id': entry.id,
    'p_business_date': entry.businessDate.iso,
    if (correctionReason != null && correctionReason.trim().isNotEmpty)
      'p_correction_reason': correctionReason.trim(),
    'p_entry_kind': entry.entryKind.wireName,
    'p_source_reference': entry.sourceReference,
    'p_notes': entry.notes,
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

  /// Applies a correction locally and queues it, in one transaction.
  ///
  /// ## At most one queued mutation per document
  ///
  /// This is the part that differs from the expense engine, and it is deliberate.
  ///
  /// An expense edit queues a **new** update intent with a fresh mutation id every time.
  /// That leaves two failure modes, both reachable and neither theoretical:
  ///
  ///  * **A correction to a sale that has not been accepted yet.** The create and the
  ///    update sit in one batch. If the create fails transiently, the update still
  ///    reaches the server, finds no such document, and is refused `KM015` — terminal.
  ///    A legitimate correction becomes a rejection, and the operator is told the entry
  ///    does not exist.
  ///  * **Two corrections before either syncs.** Both carry the same
  ///    `base_row_version`, because both were based on the same local state. The first
  ///    is applied and the second conflicts with a version the operator never saw.
  ///
  /// So a revenue document has **at most one queued intent at a time**, and a correction
  /// rewrites it in place:
  ///
  /// ```
  ///   queued create  + edit  ->  the create's payload becomes the corrected one
  ///   queued update  + edit  ->  the update's payload becomes the corrected one
  ///   nothing queued + edit  ->  a new update intent, based on the current row version
  /// ```
  ///
  /// Nothing is deleted and no actor is lost: the entry keeps its own mutation id, its
  /// `actor_user_id` and its creation time, so idempotency, ownership (D-050, D-074) and
  /// the audit of who intended what all survive. What changes is the payload — which is
  /// the operator's current intent, and is what they would expect to be sent.
  ///
  /// The server's audit is unaffected either way: it records what it accepted, and it
  /// accepts one document with the values the operator settled on.
  Future<RevenueEntry> updateLocally(
    RevenueEntryDraft draft, {
    required List<RevenueTaxResolved> resolutions,
    required String actorUserId,
    required String orgId,
    required int baseRowVersion,
    required String mutationId,
    required DateTime now,
    String? correctionReason,
  }) async {
    if (resolutions.length != draft.components.length) {
      throw ArgumentError(
        'a resolution is required for each component: '
        '${draft.components.length} components, ${resolutions.length} resolutions',
      );
    }

    final existing = await (_db.select(
      _db.revenueEntries,
    )..where((e) => e.id.equals(draft.id))).getSingleOrNull();
    if (existing == null) {
      throw StateError('revenue ${draft.id} is not in the local ledger');
    }
    if (existing.voidedAt != null) {
      throw StateError('revenue ${draft.id} is voided and cannot be corrected');
    }

    final components = <RevenueComponent>[];
    for (var i = 0; i < draft.components.length; i++) {
      final part = draft.components[i];
      final rule = resolutions[i].rule;
      final computed = rule.compute(part.enteredAmount);
      components.add(
        RevenueComponent(
          id: part.id,
          enteredAmount: part.enteredAmount,
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
      // The number is the document's, not the correction's. Carried through so the
      // payload and every local read keep it — the defect D-072a records for expenses,
      // where reconciliation wrote every field back and erased it on each edit.
      txnNumber: existing.txnNumber,
      businessUnitId: existing.businessUnitId,
      revenueCategoryId: existing.revenueCategoryId,
      businessDate: draft.businessDate,
      capturedAt: existing.capturedAt,
      components: components,
      entryKind: draft.entryKind,
      sourceReference: draft.sourceReference,
      notes: draft.notes,
      createdBy: existing.createdBy,
      rowVersion: existing.rowVersion,
    );

    await _db.transaction(() async {
      await (_db.update(
        _db.revenueEntries,
      )..where((e) => e.id.equals(entry.id))).write(
        // `businessDateSource` is deliberately absent. A local correction is an
        // *attempt*: the server decides whether the date really moved, whether this
        // actor may move it, and whether the period allows it — and only then is the
        // provenance `corrected`. Writing it here would let a refused correction leave a
        // device claiming a trading day had been corrected when it had not. It arrives
        // with the acceptance (spec §9, D-037).
        RevenueEntriesCompanion(
          businessDate: Value(entry.businessDate.iso),
          pnlPeriodKey: Value(entry.businessDate.periodKey),
          entryKind: Value(entry.entryKind.wireName),
          sourceReference: Value(entry.sourceReference),
          notes: Value(entry.notes),
          updatedAt: Value(now),
        ),
      );

      await (_db.delete(
        _db.revenueComponents,
      )..where((c) => c.revenueEntryId.equals(entry.id))).go();

      for (final component in components) {
        await _db
            .into(_db.revenueComponents)
            .insert(_companionFor(component, entry.id, orgId));
      }

      // The queued intent this correction belongs to, if there already is one.
      final queued =
          await (_db.select(_db.syncOutbox)
                ..where(
                  (o) =>
                      o.entityId.equals(entry.id) &
                      o.entityType.equals(revenueEntityType) &
                      o.status.isNotIn(const ['done']),
                )
                ..orderBy([(o) => OrderingTerm.asc(o.createdAt)])
                ..limit(1))
              .getSingleOrNull();

      if (queued == null) {
        await _db
            .into(_db.syncOutbox)
            .insert(
              SyncOutboxCompanion.insert(
                mutationId: mutationId,
                actorUserId: Value(actorUserId),
                entityType: revenueEntityType,
                entityId: entry.id,
                op: MutationOp.update.name,
                payload: jsonEncode(
                  updatePayload(entry, correctionReason: correctionReason),
                ),
                // Captured when the form was opened, and never re-based here. A
                // background pull that moved the row must make this a conflict rather
                // than silently retarget somebody's correction (D-021, §4).
                baseRowVersion: Value(baseRowVersion),
                nextAttemptAt: now,
                status: OutboxStatus.pending.name,
                createdAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      } else {
        // Rewrite the intent that is already queued, keeping its identity.
        //
        // A create stays a create — the server has never seen this document, and
        // sending an update for it would be asking to correct something that does not
        // exist.
        //
        // An update carries **the base version this correction was made against**, which
        // is not always the one the queued intent already held. An earlier draft kept the
        // queued value on the reasoning that "it is still the version the server holds";
        // that is true only while the intent has not been refused. Once it comes back a
        // conflict and the operator has reviewed the latest, their new correction is based
        // on the *current* version — and re-sending the old one refuses it as stale for
        // ever, which makes the conflict unresolvable through the shipped path. Found by
        // the two-client acceptance and by nothing below it.
        //
        // This is not the silent rebase §4 forbids. The value comes from the draft the
        // form opened on, which `copyWith` cannot move; it is the version the operator
        // actually saw, never one re-read at save time.
        final isCreate = queued.op == MutationOp.create.name;
        await (_db.update(
          _db.syncOutbox,
        )..where((o) => o.mutationId.equals(queued.mutationId))).write(
          SyncOutboxCompanion(
            payload: Value(
              jsonEncode(
                isCreate
                    ? createPayload(entry)
                    : updatePayload(entry, correctionReason: correctionReason),
              ),
            ),
            // A rewritten intent is due again immediately: the operator has just
            // acted, and making them wait out a backoff earned by an earlier attempt
            // would be punishing them for the network.
            status: const Value('pending'),
            nextAttemptAt: Value(now),
            lastError: const Value(null),
            baseRowVersion: isCreate
                ? const Value(null)
                : Value(baseRowVersion),
          ),
        );
      }

      // The row points at whichever intent now carries it, so every read derives the
      // same sync state from the same place.
      await (_db.update(
        _db.revenueEntries,
      )..where((e) => e.id.equals(entry.id))).write(
        RevenueEntriesCompanion(
          pendingMutationId: Value(queued?.mutationId ?? mutationId),
        ),
      );
    });

    return entry;
  }

  RevenueComponentsCompanion _companionFor(
    RevenueComponent component,
    String entryId,
    String orgId,
  ) => RevenueComponentsCompanion.insert(
    id: component.id,
    orgId: orgId,
    revenueEntryId: entryId,
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
  );

  /// Applies the server's answer to the local row.
  ///
  /// **Only the fields the server actually restated.** D-072a records what happens
  /// otherwise: writing every field back erased the server-issued transaction number on
  /// every edit, because the update RPC returns only a row version. A field the server did
  /// not mention is left alone.
  Future<void> reconcileAcceptance(
    RevenueAcceptance acceptance,
  ) => _db.transaction(() async {
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
        // The canonical provenance, carried from the server rather than derived here
        // (spec §9). A correction that moved the date comes back `corrected`; every
        // other acceptance comes back with whatever the row already had, so an
        // ordinary edit cannot reset it. Absent only when the answer did not state
        // one — an older stored result being replayed — and then the local value is
        // left alone rather than guessed at.
        businessDateSource: acceptance.businessDateSource == null
            ? const Value.absent()
            : Value(acceptance.businessDateSource!.wireName),
        // The intent is delivered; the row is no longer waiting on one.
        pendingMutationId: const Value(null),
      ),
    );
  });

  /// Replaces the local copy of one entry with the server's, from the authorised
  /// projection.
  ///
  /// The conflict path's whole purpose, and its one legitimate destructive act: the local
  /// row currently holds **the operator's refused attempt**, and the point of Review
  /// latest is to see what the record actually says now. So the caller captures the
  /// attempt first, and this writes the server's version over it.
  ///
  /// **It refuses to run while an intent may still be delivered.** A `pending`,
  /// `inFlight` or `blocked` entry is work on its way to the server, and replacing the
  /// row underneath it would show somebody the server's figures while their own are
  /// still about to be applied to them.
  ///
  /// A `conflict` or `rejected` entry is different, and is exactly the case this exists
  /// for: it will not be retried on its own, and **the attempt is preserved in the
  /// intent's own payload**, so overwriting the row destroys no evidence. Nothing in the
  /// outbox is deleted here — the intent stays inspectable, which is what D-048 §2
  /// protects.
  ///
  /// Nothing about tax is recomputed here. The server's snapshot is copied as it stands,
  /// because that snapshot is the explanation of the server's own figures and re-deriving
  /// it locally would be this device deciding what the server meant.
  Future<void> applyServerDocument({
    required Map<String, dynamic> header,
    required List<Map<String, dynamic>> components,
    required String orgId,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final id = header['id']! as String;
    if (components.isEmpty) {
      throw StateError('revenue $id came back with no components');
    }

    final queued =
        await (_db.select(_db.syncOutbox)
              ..where(
                (o) =>
                    o.entityId.equals(id) &
                    o.entityType.equals(revenueEntityType) &
                    // Stated as an exclusion so a status added later lands on the
                    // refusing side by default, rather than silently becoming a case
                    // in which the local row may be overwritten.
                    o.status.isNotIn(const ['conflict', 'rejected', 'done']),
              )
              ..limit(1))
            .getSingleOrNull();
    if (queued != null) {
      throw StateError(
        'revenue $id still has an intent that may be delivered; it cannot be '
        'replaced by the server copy yet',
      );
    }

    await _db.transaction(() async {
      await (_db.update(
        _db.revenueEntries,
      )..where((e) => e.id.equals(id))).write(
        RevenueEntriesCompanion(
          txnNumber: Value(header['txn_number'] as String?),
          financialYear: Value(header['financial_year']?.toString()),
          businessDate: Value('${header['business_date']}'),
          pnlPeriodKey: Value('${header['pnl_period_key']}'),
          entryKind: Value('${header['entry_kind']}'),
          sourceReference: Value(header['source_reference'] as String?),
          notes: Value(header['notes'] as String?),
          businessDateSource: Value(
            // The projection carries it. A row read back from the server states its own
            // provenance; nothing here re-derives it.
            '${header['business_date_source'] ?? BusinessDateSource.derived.wireName}',
          ),
          rowVersion: Value(header['row_version']! as int),
          voidedAt: Value(
            header['voided_at'] == null
                ? null
                : DateTime.tryParse('${header['voided_at']}')?.toUtc(),
          ),
          voidReason: Value(header['void_reason'] as String?),
          serverUpdatedAt: Value(
            DateTime.tryParse('${header['updated_at']}')?.toUtc(),
          ),
          pendingMutationId: const Value(null),
        ),
      );

      await (_db.delete(
        _db.revenueComponents,
      )..where((c) => c.revenueEntryId.equals(id))).go();

      for (final c in components) {
        await _db
            .into(_db.revenueComponents)
            .insert(
              RevenueComponentsCompanion.insert(
                id: c['id']! as String,
                orgId: orgId,
                revenueEntryId: id,
                enteredAmountMinor: c['entered_amount_minor']! as int,
                enteredBasis: '${c['entered_basis']}',
                grossAmountMinor: c['gross_amount_minor']! as int,
                taxAmountMinor: c['tax_amount_minor']! as int,
                netAmountMinor: c['net_amount_minor']! as int,
                taxRuleId: c['tax_rule_id']! as String,
                taxRateBasisPoints: c['tax_rate_bp']! as int,
                taxTreatment: '${c['tax_treatment']}',
                valueBandId: Value(c['value_band_id'] as String?),
                valueBandLabel: Value(c['value_band_label'] as String?),
                valueBandFloorMinor: Value(c['value_band_floor_minor'] as int?),
                valueBandCeilingMinor: Value(
                  c['value_band_ceiling_minor'] as int?,
                ),
                supplySubtypeId: Value(c['supply_subtype_id'] as String?),
                premisesStatusCode: Value(c['premises_status_code'] as String?),
              ),
            );
      }

      // Evidence is **merged, never replaced**. Components are the document's own
      // figures and the server's set is authoritative; attachments are not. A file this
      // device staged and has not managed to upload yet exists nowhere else, and the
      // server has no way to know about it - deleting the local rows the way the
      // components are deleted would destroy exactly the work D-070 exists to keep.
      //
      // So a canonical row is written or refreshed, and a local row the server has never
      // heard of is left alone with its own upload state.
      for (final a in attachments) {
        await _db
            .into(_db.revenueAttachments)
            .insertOnConflictUpdate(
              RevenueAttachmentsCompanion.insert(
                id: a['id']! as String,
                orgId: orgId,
                revenueEntryId: id,
                fileName: '${a['file_name']}',
                contentType: '${a['content_type']}',
                byteSize: a['byte_size']! as int,
                contentHash: '${a['content_hash']}',
                uploadState: const Value('uploaded'),
                storagePath: Value(a['storage_path'] as String?),
                uploadedAt: Value(
                  DateTime.tryParse('${a['uploaded_at']}')?.toUtc(),
                ),
                uploadedBy: '${a['uploaded_by']}',
                createdAt: DateTime.now().toUtc(),
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      }
    });
  }

  /// The entries this actor may browse (§21).
  ///
  /// Excludes anything stamped `scope_revoked_at`: retained work is reachable only through
  /// the dedicated pending/rejected workflow, never through the ordinary ledger (D-070).
  Future<List<RevenueLedgerRow>> list({
    Set<String>? businessUnitIds,
    bool includeVoided = false,
  }) =>
      query(_AllRevenue(includeVoided: includeVoided, units: businessUnitIds));

  /// The same, delivered as a stream, for a surface that must follow the queue
  /// rather than a snapshot of it (D-160).
  Stream<List<RevenueLedgerRow>> watchList({
    Set<String>? businessUnitIds,
    bool includeVoided = false,
  }) => watchQuery(
    _AllRevenue(includeVoided: includeVoided, units: businessUnitIds),
  );

  /// Marks a sale voided locally and queues the void.
  ///
  /// Queued, not applied. A void is a financial state change that the server decides:
  /// it needs `revenue.void` for that property, an open period and a matching row
  /// version, and any of the three may refuse. So the local row is stamped as *this
  /// actor's intent to void* — visible, reversible only by the server's answer — and the
  /// canonical void is what comes back.
  ///
  /// **Nothing is deleted.** Pressing Void never removes a pending sale, and a refusal
  /// leaves the document exactly as it was (spec §14, D-006).
  ///
  /// The same one-intent-per-document discipline as [updateLocally]: a void replaces a
  /// queued correction, because voiding is the operator's later and more decisive
  /// intent, and sending both would ask the server to correct a document and then throw
  /// it away. The queue entry keeps its own id and actor.
  /// Returns null when the void was queued, or the reason it was not.
  ///
  /// Structured rather than thrown, for the same reason [evaluate] is: a person pressing
  /// Void needs a sentence they can act on, and an exception reaching a widget becomes
  /// either a crash or a message nobody can do anything about.
  Future<RevenueRefusal?> voidLocally({
    required String entryId,
    required String reason,
    required String actorUserId,
    required int baseRowVersion,
    required String mutationId,
    required DateTime now,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      return const RevenueRefusal(
        RevenueRefusalReason.voidReasonRequired,
        'Say why this sale is being voided. The reason is kept with it.',
      );
    }

    final existing = await (_db.select(
      _db.revenueEntries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();
    if (existing == null) {
      throw StateError('revenue $entryId is not in the local ledger');
    }
    if (existing.voidedAt != null) {
      // Not an error and not a second void. Voiding twice would queue a second mutation
      // against a document already recorded as voided, and the second reason would
      // silently replace the first one somebody wrote.
      return const RevenueRefusal(
        RevenueRefusalReason.alreadyVoided,
        'This sale has already been voided.',
      );
    }

    RevenueRefusal? refusal;
    await _db.transaction(() async {
      final queued =
          await (_db.select(_db.syncOutbox)
                ..where(
                  (o) =>
                      o.entityId.equals(entryId) &
                      o.entityType.equals(revenueEntityType) &
                      o.status.isNotIn(const ['done']),
                )
                ..orderBy([(o) => OrderingTerm.asc(o.createdAt)])
                ..limit(1))
              .getSingleOrNull();

      final payload = jsonEncode({'p_reason': trimmed});

      // A queued **create** is the one case a void cannot replace: the server has never
      // seen this document, so there is nothing to void. Voiding an unsent sale is
      // simply the create never being sent — which is a decision this method does not
      // get to take on somebody's behalf, so it refuses and says why.
      if (queued != null && queued.op == MutationOp.create.name) {
        refusal = const RevenueRefusal(
          RevenueRefusalReason.notYetOnTheServer,
          'This sale has not reached the office yet, so there is nothing to '
          'void. Wait for it to sync, or correct it instead.',
        );
        return;
      }

      if (queued == null) {
        await _db
            .into(_db.syncOutbox)
            .insert(
              SyncOutboxCompanion.insert(
                mutationId: mutationId,
                actorUserId: Value(actorUserId),
                entityType: revenueEntityType,
                entityId: entryId,
                op: MutationOp.void_.name,
                payload: payload,
                baseRowVersion: Value(baseRowVersion),
                nextAttemptAt: now,
                status: OutboxStatus.pending.name,
                createdAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      } else {
        await (_db.update(
          _db.syncOutbox,
        )..where((o) => o.mutationId.equals(queued.mutationId))).write(
          SyncOutboxCompanion(
            op: Value(MutationOp.void_.name),
            payload: Value(payload),
            baseRowVersion: Value(queued.baseRowVersion ?? baseRowVersion),
            status: const Value('pending'),
            nextAttemptAt: Value(now),
            lastError: const Value(null),
          ),
        );
      }

      // Stamped as **this actor's intent to void**, exactly as an expense is. The local
      // write always succeeds and the server decides: it needs `revenue.void` for the
      // property, an open period and a matching row version, and any of the three may
      // refuse — at which point the intent becomes terminal `Rejected` and is kept for
      // a person to see rather than quietly reversed.
      await (_db.update(
        _db.revenueEntries,
      )..where((e) => e.id.equals(entryId))).write(
        RevenueEntriesCompanion(
          voidedAt: Value(now),
          voidedBy: Value(actorUserId),
          voidReason: Value(trimmed),
          pendingMutationId: Value(queued?.mutationId ?? mutationId),
          updatedAt: Value(now),
        ),
      );
    });
    return refusal;
  }

  /// The ledger, filtered, ordered and paged **in SQL**.
  ///
  /// Nothing here fetches every sale and narrows it in Dart. At a year of history that is
  /// the difference between a ledger that opens and one that does not (spec 27), and it
  /// is the shape the expense ledger already proved.
  ///
  /// Ordering is `business_date desc, captured_at desc, id desc`. The third term is not
  /// decoration: two sales recorded in the same second on the same day would otherwise
  /// have no defined order, and an undefined order across a page boundary is how a row
  /// gets shown twice or skipped entirely.
  Future<List<RevenueLedgerRow>> query(
    RevenueQuery filter, {
    int limit = 100,
    int offset = 0,
  }) async => _mapLedger(
    await _ledgerSelect(filter, limit: limit, offset: offset).get(),
    filter,
  );

  /// The same page, delivered as a stream.
  ///
  /// **The ledger's sync state arrives from the sync worker, which invalidates no
  /// provider and knows about no screen.** A one-shot read therefore keeps whatever
  /// state it saw when the query last ran, so a corrected sale that has since been
  /// accepted goes on reading `Syncing` until something else happens to refresh the
  /// surface. That is D-131 exactly: it was fixed for the detail panel and left
  /// standing here, where a weak acceptance assertion hid it (D-160).
  ///
  /// Drift re-runs the statement whenever any of the three tables it reads changes,
  /// so there is one derivation and it is pushed rather than polled.
  Stream<List<RevenueLedgerRow>> watchQuery(
    RevenueQuery filter, {
    int limit = 100,
    int offset = 0,
  }) => _ledgerSelect(
    filter,
    limit: limit,
    offset: offset,
  ).watch().map((rows) => _mapLedger(rows, filter));

  Selectable<QueryRow> _ledgerSelect(
    RevenueQuery filter, {
    required int limit,
    required int offset,
  }) {
    final where = <String>[
      // D-070: never browsable, whatever the filter asks for. First predicate rather
      // than last, so a future branch cannot be written that forgets it.
      'e.scope_revoked_at IS NULL',
    ];
    final variables = <Variable<Object>>[];

    if (!filter.includeVoided) where.add('e.voided_at IS NULL');

    // Business **date**, never a device timestamp. A sale recorded at 02:00 belongs to
    // the previous trading day under D-067, and filtering on `captured_at` because it is
    // convenient for SQL would put it in the wrong month of somebody's report.
    if (filter.from case final from? when from.isNotEmpty) {
      where.add('e.business_date >= ?');
      variables.add(Variable<String>(from));
    }
    if (filter.to case final to? when to.isNotEmpty) {
      where.add('e.business_date <= ?');
      variables.add(Variable<String>(to));
    }
    if (filter.businessUnitId case final unit?) {
      where.add('e.business_unit_id = ?');
      variables.add(Variable<String>(unit));
    }
    if (filter.revenueCategoryId case final category?) {
      where.add('e.revenue_category_id = ?');
      variables.add(Variable<String>(category));
    }
    if (filter.entryKind case final kind?) {
      where.add('e.entry_kind = ?');
      variables.add(Variable<String>(kind.wireName));
    }
    if (filter.enteredByUserId case final actor?) {
      where.add('e.created_by = ?');
      variables.add(Variable<String>(actor));
    }
    if (filter.search case final term? when term.trim().isNotEmpty) {
      // Business identifiers a person would actually type - the KI-REV number, the till
      // reference, the note. **Not the UUID**: that is an identity, not something anybody
      // reads off a screen and searches for.
      where.add(
        '(e.txn_number LIKE ? OR e.source_reference LIKE ? OR e.notes LIKE ?)',
      );
      final needle = '%${term.trim()}%';
      variables
        ..add(Variable<String>(needle))
        ..add(Variable<String>(needle))
        ..add(Variable<String>(needle));
    }
    if (filter.businessUnitIds case final scope? when scope.isNotEmpty) {
      final places = List.filled(scope.length, '?').join(', ');
      where.add('e.business_unit_id IN ($places)');
      variables.addAll(scope.map(Variable<String>.new));
    }

    return _db.customSelect(
      'SELECT e.id, e.txn_number, e.business_unit_id, e.revenue_category_id, '
      '       e.business_date, e.entry_kind, e.source_reference, e.notes, '
      '       e.created_by, e.voided_at, e.updated_at, e.row_version, '
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
      ' WHERE ${where.join(' AND ')} '
      ' GROUP BY e.id '
      ' ORDER BY e.business_date DESC, e.captured_at DESC, e.id DESC '
      ' LIMIT ? OFFSET ?',
      variables: [...variables, Variable<int>(limit), Variable<int>(offset)],
      // What the statement reads, so Drift knows when to re-run it.
      readsFrom: {_db.revenueEntries, _db.revenueComponents, _db.syncOutbox},
    );
  }

  List<RevenueLedgerRow> _mapLedger(List<QueryRow> rows, RevenueQuery filter) {
    final loaded = <RevenueLedgerRow>[];
    for (final row in rows) {
      final entry = RevenueLedgerRow(
        id: row.data['id']! as String,
        txnNumber: row.data['txn_number'] as String?,
        businessUnitId: row.data['business_unit_id']! as String,
        revenueCategoryId: row.data['revenue_category_id']! as String,
        businessDate: _date(row.data['business_date']! as String),
        entryKind: RevenueEntryKind.fromName(row.data['entry_kind']! as String),
        sourceReference: row.data['source_reference'] as String?,
        notes: row.data['notes'] as String?,
        createdBy: row.data['created_by']! as String,
        rowVersion: row.data['row_version']! as int,
        updatedAt: DateTime.tryParse('${row.data['updated_at']}'),
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
      );

      // Sync state is derived from the outbox, so it cannot be a SQL predicate without
      // duplicating it into a column that could then disagree. The window is already
      // bounded above, so filtering it here costs nothing meaningful - the same trade
      // the expense ledger makes, for the same reason.
      if (filter.syncState != null && entry.syncState != filter.syncState) {
        continue;
      }
      loaded.add(entry);
    }
    return loaded;
  }

  /// Where one sale stands in the sync lifecycle.
  ///
  /// Derived from the outbox, never from a column on the entry, so there is one place
  /// the answer comes from and no second copy to drift (D-119). Needed on its own
  /// because a detail surface is reachable without a ledger query having run — the phone
  /// has no ledger at all — and reading the state out of whichever list happened to be
  /// loaded is how a screen shows `Synced` for an entry that is nothing of the kind.
  Future<SyncState> syncStateOf(String entryId) =>
      watchSyncState(entryId).first;

  /// Where one sale stands, as a stream that re-emits whenever the outbox moves.
  ///
  /// A snapshot is not enough here, and the Windows acceptance is what showed it. A
  /// conflict is delivered by the **sync worker**, which invalidates no provider and
  /// knows about no screen; so a detail surface holding a cached "Synced" went on saying
  /// it after the server had refused the correction — the operator's one signal that
  /// their work needs attention, absent, on the surface that exists to show it.
  ///
  /// Streaming removes the staleness by construction rather than by remembering to
  /// invalidate from every place that could change it, which is the same reasoning D-119
  /// applied to having one mapping instead of two.
  ///
  /// It joins the outbox **the way the ledger does** — on the document's id, taking any
  /// entry that is not `done` — and not through `revenue_entries.pending_mutation_id`.
  /// That pointer is a denormalised convenience that something else can leave stale, and
  /// an earlier version of this method read it: on the real Windows executable it was
  /// null on a document whose correction had just been refused, so the panel reported
  /// `Synced` for a sale in conflict while the ledger beside it knew better. Two
  /// derivations of one fact is the defect; this is the ledger's.
  Stream<SyncState> watchSyncState(String entryId) {
    final query = _db.customSelect(
      'SELECT e.txn_number AS txn_number, o.status AS outbox_status '
      '  FROM revenue_entries e '
      '  LEFT JOIN sync_outbox o ON o.entity_id = e.id '
      "                        AND o.entity_type = '$revenueEntityType' "
      "                        AND o.status <> 'done' "
      ' WHERE e.id = ?',
      variables: [Variable<String>(entryId)],
      readsFrom: {_db.revenueEntries, _db.syncOutbox},
    );
    return query.watch().map((rows) {
      if (rows.isEmpty) return SyncState.pendingSync;
      final row = rows.first;
      final status = row.data['outbox_status'] as String?;
      return _stateOf(
        status == null || status == 'done' ? null : status,
        row.data['txn_number'] as String?,
      );
    });
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

    final files = await attachmentsOf(id);

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
      voidedBy: header.voidedBy,
      voidReason: header.voidReason,
      businessDateSource: BusinessDateSource.fromWire(
        header.businessDateSource,
      ),
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
      attachments: files,
    );
  }

  /// The evidence attached to one sale, oldest first.
  ///
  /// Ordered by when it was attached rather than by name, so the list a person sees does
  /// not reshuffle when a file is renamed on the way in by image optimisation.
  Future<List<DocumentAttachment>> attachmentsOf(String entryId) async {
    final rows =
        await (_db.select(_db.revenueAttachments)
              ..where((a) => a.revenueEntryId.equals(entryId))
              ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
            .get();
    return [
      for (final a in rows)
        DocumentAttachment(
          id: a.id,
          fileName: a.fileName,
          contentType: a.contentType,
          byteSize: a.byteSize,
          contentHash: a.contentHash,
          uploadState: AttachmentUploadState.fromName(a.uploadState),
          storagePath: a.storagePath,
          localStagingPath: a.localPath,
        ),
    ];
  }

  /// Attaches already-staged evidence to a sale that exists locally.
  ///
  /// **This is not a financial mutation and deliberately does not behave like one.** It
  /// queues no outbox intent, takes no `base_row_version`, does not advance the entry's
  /// row version, and changes no amount, tax figure, business date or transaction number.
  /// Evidence travels on the attachment pipeline's own clock (D-073), and a correction
  /// queued against this sale is unaffected - the attachment belongs to the document's
  /// identity, not to any one mutation.
  ///
  /// The row is written `waitingForExpense` - the shared lifecycle's name for "the parent
  /// has not been accepted yet" - unless the sale is already numbered and has nothing
  /// queued, in which case it is ready to upload at once. The worker promotes the former
  /// when the server issues a KI-REV number, and not before: the Storage write policy
  /// requires the entry to exist canonically, so an earlier attempt would be refused for
  /// a reason that reads like a permission problem (D-073 section 2).
  Future<RevenueRefusal?> attachLocally({
    required String entryId,
    required List<DocumentAttachment> staged,
    required String actorUserId,
    required String orgId,
    required DateTime now,
  }) async {
    if (staged.isEmpty) return null;

    final header = await (_db.select(
      _db.revenueEntries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();
    if (header == null) {
      throw StateError('revenue $entryId is not in the local ledger');
    }

    // A voided document keeps the evidence it has and gains none - the rule
    // `revenue_attachment_register` enforces server-side, said here so the operator is
    // told at the button rather than after a sync (D-006).
    if (header.voidedAt != null) {
      return const RevenueRefusal(
        RevenueRefusalReason.alreadyVoided,
        'This sale has been voided. Its existing attachments remain, but nothing '
        'further can be added.',
      );
    }

    final existing = await attachmentsOf(entryId);

    // The caller may hand back the whole collection a form was showing, most of which is
    // already recorded. Only what is genuinely new is written, and only it counts towards
    // the limits — otherwise saving an edit twice would refuse a document for exceeding a
    // count it never reached. Identity is the client-generated attachment id (D-008).
    final known = {for (final a in existing) a.id};
    final additions = [
      for (final file in staged)
        if (!known.contains(file.id)) file,
    ];
    if (additions.isEmpty) return null;

    if (existing.length + additions.length > AttachmentPolicy.maxPerDocument) {
      return RevenueRefusal(
        RevenueRefusalReason.attachmentLimit,
        'A sale can carry at most ${AttachmentPolicy.maxPerDocument} '
        'attachments.',
      );
    }
    final total =
        existing.fold<int>(0, (sum, a) => sum + a.byteSize) +
        additions.fold<int>(0, (sum, a) => sum + a.byteSize);
    if (total > AttachmentPolicy.maxTotalBytesPerDocument) {
      return RevenueRefusal(
        RevenueRefusalReason.attachmentLimit,
        'Together the attachments on one sale may be up to '
        '${AttachmentPolicy.maxTotalBytesPerDocument ~/ (1024 * 1024)} MB.',
      );
    }

    // The initial state is decided from the parent, not passed in: a sale the server has
    // already numbered is ready to upload at once, and one that is still queued has to
    // wait for it.
    final state = header.txnNumber != null && header.pendingMutationId == null
        ? AttachmentUploadState.pendingUpload
        : AttachmentUploadState.waitingForExpense;

    await _db.transaction(() async {
      for (final file in additions) {
        await _db
            .into(_db.revenueAttachments)
            .insert(
              RevenueAttachmentsCompanion.insert(
                id: file.id,
                orgId: orgId,
                revenueEntryId: entryId,
                fileName: file.fileName,
                contentType: file.contentType,
                byteSize: file.byteSize,
                contentHash: file.contentHash,
                localPath: Value(file.localStagingPath),
                uploadState: Value(state.name),
                storagePath: Value(file.storagePath),
                nextAttemptAt: Value(now),
                uploadedBy: actorUserId,
                createdAt: now,
                updatedAt: now,
              ),
              // The attachment id is the client-generated identity, so a repeated write
              // of the same file is the same row rather than a second one (D-008).
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
    return null;
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

  // ── Reporting contributions (Phase 4 Slice 12, D-087, D-157) ───────────────
  //
  // The local half of the reporting interface. It reads `revenue_period_contributions`
  // and nothing else, so a caller cannot accidentally add entry-level figures to
  // component-level ones and count the same money twice — the reason D-060 gave the
  // expense side one named projection to sum.
  //
  // **Everything is decided in SQL.** Filtering, scoping and the aggregate itself, so a
  // month of a property's revenue is one row off the database rather than every component
  // folded in Dart (spec §27). The expense side folds; that is the older pattern and this
  // is the one Phase 5 will need at scale.
  //
  // Three predicates are not filters and are applied before any of them:
  //
  //   * `voided_at IS NULL`      — a voided sale contributes nothing (D-006)
  //   * `scope_revoked_at IS NULL` — a retained unsent attempt over a property this user
  //                                 no longer holds is nobody's revenue (D-070)
  //   * `txn_number IS NOT NULL` — **canonical only.** A sale the server has not accepted
  //                                is an attempt, not revenue, and putting it in an
  //                                authoritative total would report money the business
  //                                does not yet have. Phase 5 may add an explicitly
  //                                labelled provisional figure; Slice 12 does not invent
  //                                one (D-158).

  /// Every contribution this device holds for [query], newest business date first.
  Future<List<RevenueContribution>> contributions(
    RevenueContributionQuery query,
  ) async {
    final (where, variables) = _contributionPredicate(query);
    final rows = await _db
        .customSelect(
          'SELECT * FROM revenue_period_contributions WHERE $where '
          'ORDER BY business_date DESC, revenue_entry_id DESC, id DESC',
          variables: variables,
        )
        .get();
    return [for (final row in rows) _contributionOf(row)];
  }

  /// Summed paise for [query]. One row off the database, exact, no folding.
  Future<RevenueTotals> contributionTotals(
    RevenueContributionQuery query,
  ) async {
    final (where, variables) = _contributionPredicate(query);
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(gross_minor), 0) AS g, '
          '       COALESCE(SUM(tax_minor), 0)   AS t, '
          '       COALESCE(SUM(net_minor), 0)   AS n, '
          '       COUNT(*)                      AS c '
          '  FROM revenue_period_contributions WHERE $where',
          variables: variables,
        )
        .getSingle();
    return RevenueTotals(
      gross: Money.fromPaise(row.read<int>('g')),
      tax: Money.fromPaise(row.read<int>('t')),
      net: Money.fromPaise(row.read<int>('n')),
      contributions: row.read<int>('c'),
    );
  }

  /// The same, grouped by property and revenue category — the grain spec §10's target
  /// report shape needs: revenue lines by category, then Gross Sales, less GST, Net Sales.
  ///
  /// Restaurant and Nandbhog come back as two rows even though they currently share a
  /// treatment, because they are two categories and a report that merged them would be
  /// answering a question nobody asked (D-089).
  Future<List<RevenueCategoryTotals>> contributionTotalsByCategory(
    RevenueContributionQuery query,
  ) async {
    final (where, variables) = _contributionPredicate(query);
    final rows = await _db
        .customSelect(
          'SELECT business_unit_id AS u, revenue_category_id AS r, '
          '       COALESCE(SUM(gross_minor), 0) AS g, '
          '       COALESCE(SUM(tax_minor), 0)   AS t, '
          '       COALESCE(SUM(net_minor), 0)   AS n, '
          '       COUNT(*)                      AS c, '
          // `none` and a configured 0% both give zero tax and are different facts, so the
          // treatment is carried; a group spanning two of them is described by neither and
          // collapses to null rather than to whichever row came first (D-091).
          '       CASE WHEN COUNT(DISTINCT tax_treatment) = 1 '
          '            THEN MIN(tax_treatment) ELSE NULL END AS tr '
          '  FROM revenue_period_contributions WHERE $where '
          ' GROUP BY business_unit_id, revenue_category_id '
          ' ORDER BY business_unit_id, revenue_category_id',
          variables: variables,
        )
        .get();
    return [
      for (final row in rows)
        RevenueCategoryTotals(
          businessUnitId: row.read<String>('u'),
          revenueCategoryId: row.read<String>('r'),
          treatment: switch (row.read<String?>('tr')) {
            final String name => TaxTreatment.fromName(name),
            null => null,
          },
          totals: RevenueTotals(
            gross: Money.fromPaise(row.read<int>('g')),
            tax: Money.fromPaise(row.read<int>('t')),
            net: Money.fromPaise(row.read<int>('n')),
            contributions: row.read<int>('c'),
          ),
        ),
    ];
  }

  /// The predicate every reporting read shares, so the three exclusions above cannot be
  /// present in one query and forgotten in the next.
  (String, List<Variable<Object>>) _contributionPredicate(
    RevenueContributionQuery query,
  ) {
    final clauses = <String>[
      'voided_at IS NULL',
      'scope_revoked_at IS NULL',
      'txn_number IS NOT NULL',
    ];
    final variables = <Variable<Object>>[];

    // Authority first, and never removable by a filter (D-121). An unscoped grant is
    // `null` by construction (D-025) and restricts nothing.
    final scope = query.businessUnitIds;
    if (scope != null) {
      if (scope.isEmpty) return ('0 = 1', const []);
      clauses.add(
        'business_unit_id IN (${List.filled(scope.length, '?').join(', ')})',
      );
      variables.addAll(scope.map(Variable<String>.new));
    }

    if (query.periodKey != null) {
      clauses.add('pnl_period_key = ?');
      variables.add(Variable<String>(query.periodKey!));
    }
    // Ranges are over the **P&L date**, never the capture instant: a sale rung up at 02:00
    // belongs to the previous trading day (D-067). For revenue `pnl_date` *is* the business
    // date — the projection aliases it — and naming the reporting column rather than the
    // underlying one is what lets both engines be filtered by one vocabulary, which is
    // what Slice 3's range mapping depends on.
    if (query.from != null) {
      clauses.add('pnl_date >= ?');
      variables.add(Variable<String>(query.from!.iso));
    }
    if (query.to != null) {
      clauses.add('pnl_date <= ?');
      variables.add(Variable<String>(query.to!.iso));
    }
    if (query.businessUnitId != null) {
      clauses.add('business_unit_id = ?');
      variables.add(Variable<String>(query.businessUnitId!));
    }
    if (query.revenueCategoryId != null) {
      clauses.add('revenue_category_id = ?');
      variables.add(Variable<String>(query.revenueCategoryId!));
    }
    return (clauses.join(' AND '), variables);
  }

  RevenueContribution _contributionOf(QueryRow row) => RevenueContribution(
    componentId: row.read<String>('id'),
    revenueEntryId: row.read<String>('revenue_entry_id'),
    orgId: row.read<String>('org_id'),
    businessUnitId: row.read<String>('business_unit_id'),
    revenueCategoryId: row.read<String>('revenue_category_id'),
    businessDate: _date(row.read<String>('business_date')),
    pnlPeriodKey: row.read<String>('pnl_period_key'),
    gross: Money.fromPaise(row.read<int>('gross_minor')),
    tax: Money.fromPaise(row.read<int>('tax_minor')),
    net: Money.fromPaise(row.read<int>('net_minor')),
    taxRuleId: row.read<String>('tax_rule_id'),
    taxRateBasisPoints: row.read<int>('tax_rate_bp'),
    taxTreatment: TaxTreatment.fromName(row.read<String>('tax_treatment')),
    enteredBasis: EnteredBasis.fromName(row.read<String>('entered_basis')),
    entryKind: RevenueEntryKind.fromName(row.read<String>('entry_kind')),
    businessDateSource: BusinessDateSource.fromWire(
      row.read<String>('business_date_source'),
    ),
    supplySubtypeId: row.read<String?>('supply_subtype_id'),
    valueBandId: row.read<String?>('value_band_id'),
    valueBandMinMinor: row.read<int?>('value_band_min_minor'),
    valueBandMaxMinor: row.read<int?>('value_band_max_minor'),
    premisesStatusCode: row.read<String?>('premises_status_code'),
    txnNumber: row.read<String?>('txn_number'),
    voidedAt: row.read<DateTime?>('voided_at'),
  );

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
