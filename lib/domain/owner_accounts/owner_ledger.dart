/// The Owner Ledger: the movements that make up an owner's current account.
///
/// Phase 5 OA-1. Pure domain — integer paise only, no `double`, no storage, no network.
///
/// ## What this is, and what OA-3 owns
///
/// This file models **movements** and sums them exactly. It does **not** compute profit
/// entitlement, opening balances from history, or a closing balance — those need a
/// `PnlResult` and the ownership shares together, and that calculator is OA-3's. What is
/// here is the foundation OA-3 will read: the types, the direction rule, and totals that
/// can distinguish one kind of movement from another (§37, §42).
///
/// ## Amounts are positive; direction comes from the movement
///
/// A stored amount is always positive and the **movement type** decides whether it takes
/// from the owner's account or adds to it (§43). The alternative — signed amounts — allows
/// a negative withdrawal, which is not a thing that happens, and makes every aggregate
/// depend on remembering a sign convention that nothing enforces. Two representations of
/// one event is the shape that eventually produces two different answers.
///
/// Two types genuinely need to go both ways, and they say so rather than being special
/// cases: an [OwnerMovementType.openingBalance] may open a position that is owed *to* the
/// owner or *recoverable from* them, and an [OwnerMovementType.manualAdjustment] is
/// meaningless without a stated direction. Everything else has a fixed direction and a
/// database CHECK holds it there.
///
/// ## The sign convention, stated once
///
/// The balance is **what the business owes the owner**.
///
/// ```
///     credit  (+)   the owner is owed more     opening credit, adjustment in their favour
///     debit   (−)   the owner has taken value  withdrawal, NC, settlement paid
/// ```
///
/// So `withdrawal`, `nc_consumption` and `settlement_paid` are all debits. They differ in
/// *meaning*, not in direction, and OA-D4 is the reason they are three types rather than
/// one: money drawn during a period and a formal payment against a computed balance are
/// different business acts, and an annexure that called them both "withdrawal" would be
/// unreadable at exactly the moment somebody needed it.
library;

import 'package:meta/meta.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Which way a movement moves the owner's current account.
enum OwnerLedgerDirection {
  /// Increases what the business owes the owner.
  credit('credit'),

  /// Reduces it. The owner has taken value out.
  debit('debit');

  const OwnerLedgerDirection(this.wireName);

  /// The exact string both databases store.
  ///
  /// Stated explicitly rather than taken from [name], for the reason D-104 records: the
  /// two happen to agree today, and relying on that coincidence is how a value becomes
  /// unparseable the moment somebody renames a constant.
  final String wireName;

  /// `+1` for a credit, `−1` for a debit. The only place the sign is decided.
  int get signum => this == credit ? 1 : -1;

  static OwnerLedgerDirection fromWire(String value) => values.firstWhere(
    (d) => d.wireName == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'unknown owner ledger direction',
    ),
  );
}

/// The V1 movement types (OA-1 §8).
///
/// Five, and deliberately no more. Capital accounts, interest, partner salary and loan
/// accounts are **not** here: this is a management Owner Current Account, not partnership
/// accounting, and nothing in the repository or the approved spec requires them.
enum OwnerMovementType {
  /// The position the account starts from at an agreed inception date (OA-D3).
  ///
  /// Explicit and auditable. Nothing infers one from prior withdrawals, and **no zero is
  /// seeded**: a fabricated ₹0 opening would be a financial claim nobody made. Direction
  /// is stated, because an account may open either owed or overdrawn.
  openingBalance('opening_balance'),

  /// Money the owner drew from the business during the period.
  withdrawal('withdrawal'),

  /// Non-chargeable consumption by the owner or a linked family member, at the full
  /// printed bill value (OA-D6).
  ncConsumption('nc_consumption'),

  /// A payment made to settle a previously computed owner position (OA-D4).
  ///
  /// Kept distinct from [withdrawal] because the accounting meaning differs, and because
  /// without it a balance that has actually been paid would show as payable for ever —
  /// with the only way to clear it being to record a withdrawal that never happened.
  settlementPaid('settlement_paid'),

  /// A deliberate correction to the account that is not one of the above (§16).
  ///
  /// Direction is stated, a meaningful reason is mandatory, and it sits behind its own
  /// capability rather than the ordinary entry one. It is **not** an escape hatch for
  /// unsupported accounting: a movement that needs a new meaning should get a new type
  /// and a decision, not be smuggled through here.
  manualAdjustment('manual_adjustment');

  const OwnerMovementType(this.wireName);

  final String wireName;

  static OwnerMovementType fromWire(String value) => values.firstWhere(
    (t) => t.wireName == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'unknown owner movement type',
    ),
  );

  /// The direction this type always takes, or **null** where the movement must state one.
  ///
  /// Null for exactly two types, and both for the same reason: they genuinely occur in
  /// both directions, so a fixed answer would be wrong half the time.
  OwnerLedgerDirection? get fixedDirection => switch (this) {
    withdrawal => OwnerLedgerDirection.debit,
    ncConsumption => OwnerLedgerDirection.debit,
    settlementPaid => OwnerLedgerDirection.debit,
    openingBalance => null,
    manualAdjustment => null,
  };

  /// Whether a person recording this must state a direction.
  bool get requiresStatedDirection => fixedDirection == null;

  /// Whether this movement names the person who consumed.
  ///
  /// True only for NC. A withdrawal has a *collector*, which is a different fact and is
  /// never an attribution (§13).
  bool get namesConsumer => this == ncConsumption;

  /// Whether this movement carries a mandatory reason.
  ///
  /// A manual adjustment does, because it is the one type whose meaning is not carried by
  /// the type itself. The other four are self-describing; their **corrections and voids**
  /// still state a reason, which is a separate rule and belongs to every financial
  /// document in this system (spec §14.1).
  bool get requiresReason => this == manualAdjustment;

  String get label => switch (this) {
    openingBalance => 'Opening balance',
    withdrawal => 'Withdrawal',
    ncConsumption => 'Non-chargeable consumption',
    settlementPaid => 'Settlement payment',
    manualAdjustment => 'Adjustment',
  };
}

/// One accepted movement on an owner's account.
///
/// Every field that decides money is stored on the row, including the **resolved owner**
/// (§12). Reporting never re-joins the family mapping, so reassigning a family member
/// later cannot restate an accepted attribution.
@immutable
final class OwnerLedgerEntry {
  OwnerLedgerEntry({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.businessUnitId,
    required this.businessDate,
    required this.movementType,
    required this.direction,
    required this.amount,
    required this.createdByUserId,
    required this.capturedAt,
    this.txnNumber,
    this.financialYear,
    this.businessDateSource = BusinessDateSource.derived,
    this.familyMemberId,
    this.collectedByFamilyMemberId,
    this.ncBillReference,
    this.paymentMethodId,
    this.referenceNumber,
    this.remarks,
    this.reason,
    this.rowVersion = 1,
    this.voidedAt,
    this.voidReason,
    this.scopeRevokedAt,
  }) {
    if (amount.isNegative) {
      throw ArgumentError.value(
        amount,
        'amount',
        'an owner ledger amount is always positive; the movement type and direction '
            'decide which way it moves the account (§43)',
      );
    }
    final fixed = movementType.fixedDirection;
    if (fixed != null && direction != fixed) {
      throw ArgumentError.value(
        direction,
        'direction',
        'a ${movementType.wireName} is always a ${fixed.wireName}; storing it the other '
            'way would make one event representable two ways',
      );
    }
    if (movementType.requiresReason &&
        (reason == null || reason!.trim().isEmpty)) {
      throw ArgumentError.value(
        reason,
        'reason',
        'a ${movementType.wireName} states why, and whitespace is not a reason '
            '(spec §14.1)',
      );
    }
    if (!movementType.namesConsumer && familyMemberId != null) {
      throw ArgumentError.value(
        familyMemberId,
        'familyMemberId',
        'only a consumption names the person who consumed; a collector is a different '
            'fact and is never an attribution',
      );
    }
  }

  final String id;
  final String orgId;

  /// The owner this movement debits or credits. **Resolved at acceptance and stored**,
  /// never derived at read time (§12).
  final String ownerId;

  /// Where the movement happened — a withdrawal from Hotel Krishna, an NC bill at
  /// Crystal Canopy (§10). Source attribution for audit and reporting; it does **not**
  /// decide the profit share, which is organisation-wide.
  final String businessUnitId;

  /// Derived under the property's timezone and cut-off, then persisted (D-019, D-067).
  final BusinessDate businessDate;

  /// How the current [businessDate] came to be. `derived`, or `corrected` afterwards by a
  /// privileged user. Server-owned, like revenue's (D-143).
  final BusinessDateSource businessDateSource;

  final OwnerMovementType movementType;
  final OwnerLedgerDirection direction;

  /// Always positive.
  final Money amount;

  /// `KI-OWN-26-27-000001`, server-issued on acceptance. Null until then, and never
  /// fabricated locally: two offline devices would both invent the same number (D-085).
  final String? txnNumber;
  final String? financialYear;

  /// Who consumed, for an NC movement.
  final String? familyMemberId;

  /// Who physically collected a withdrawal. **Metadata.** The financial debit remains
  /// [ownerId] and no aggregate ever groups by this (§13).
  final String? collectedByFamilyMemberId;

  final String? ncBillReference;
  final String? paymentMethodId;
  final String? referenceNumber;
  final String? remarks;

  /// Mandatory for a manual adjustment; optional otherwise.
  final String? reason;

  final String createdByUserId;

  /// The device instant. Forensic only; never authoritative (spec §9).
  final DateTime capturedAt;

  final int rowVersion;
  final DateTime? voidedAt;
  final String? voidReason;

  /// Set when a confirmed revocation kept this row because it still carries its own
  /// unsent work (D-070, D-074).
  final DateTime? scopeRevokedAt;

  bool get isVoided => voidedAt != null;
  bool get isAccepted => txnNumber != null;

  /// Whether this movement contributes to a canonical Owner Settlement.
  ///
  /// The **same** rule the P&L uses on both engines: server-accepted, not voided, not
  /// scope-revoked (D-168, §17). Stated once here so no query has to remember it.
  bool get isCanonical =>
      isAccepted && voidedAt == null && scopeRevokedAt == null;

  /// The effect on the owner's balance: positive for a credit, negative for a debit.
  Money get signedEffect => Money.fromPaise(amount.paise * direction.signum);

  @override
  String toString() =>
      'OwnerLedgerEntry(${movementType.wireName} ${direction.wireName} '
      '$amount, owner: $ownerId, ${businessDate.iso})';
}

/// Exact totals for one owner over one range, kept apart by movement type.
///
/// Per type rather than one net figure, because §42 is right that the foundation must be
/// able to *distinguish* them: a statement that showed a single "movements" number could
/// not tell an owner who drew ₹50,000 from one who ate ₹50,000, and those are not the
/// same conversation.
@immutable
final class OwnerLedgerTotals {
  const OwnerLedgerTotals({
    required this.ownerId,
    required this.byType,
    required this.movementCount,
  });

  /// Sums the canonical movements of one owner.
  ///
  /// Non-canonical rows contribute **zero** and are not counted — a pending withdrawal is
  /// somebody's intent, not a change to the account (§17, D-167).
  factory OwnerLedgerTotals.of(
    String ownerId,
    Iterable<OwnerLedgerEntry> entries,
  ) {
    final byType = <OwnerMovementType, Money>{};
    var count = 0;
    for (final entry in entries) {
      if (entry.ownerId != ownerId || !entry.isCanonical) continue;
      byType[entry.movementType] =
          (byType[entry.movementType] ?? Money.zero) + entry.signedEffect;
      count++;
    }
    return OwnerLedgerTotals(
      ownerId: ownerId,
      byType: Map.unmodifiable(byType),
      movementCount: count,
    );
  }

  final String ownerId;

  /// Signed net effect per type. A debit type sums negative, which is what makes
  /// [netMovement] a plain sum rather than a subtraction somebody has to get right.
  final Map<OwnerMovementType, Money> byType;

  final int movementCount;

  Money of(OwnerMovementType type) => byType[type] ?? Money.zero;

  Money get openingBalance => of(OwnerMovementType.openingBalance);

  /// Positive magnitudes, for a statement that prints "Withdrawals ₹50,000" rather than
  /// "−₹50,000" under a heading that already says what it is.
  Money get withdrawals => of(OwnerMovementType.withdrawal).absolute;
  Money get ncConsumption => of(OwnerMovementType.ncConsumption).absolute;
  Money get settlementPaid => of(OwnerMovementType.settlementPaid).absolute;
  Money get manualAdjustment => of(OwnerMovementType.manualAdjustment);

  /// Every movement's signed effect, **including** the opening balance.
  Money get netMovement => Money.sum(byType.values);

  /// The signed effect of everything except the opening balance — what happened *during*
  /// the period, which is what a period statement's movement section shows.
  Money get netMovementExcludingOpening => netMovement - openingBalance;

  @override
  String toString() =>
      'OwnerLedgerTotals($ownerId, $movementCount movements, '
      'net: $netMovement)';
}
