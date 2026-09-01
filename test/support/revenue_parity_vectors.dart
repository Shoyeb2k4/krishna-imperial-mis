/// One fixture set, three engines (B9).
///
/// The same vectors drive the pure Dart resolver, the Drift-backed repository, and the
/// live Postgres resolver. That is the point: three implementations of one specification
/// agree because they are checked against the same numbers, not because they were written
/// carefully.
///
/// Synthetic bands and subtypes appear here freely. **None of them is ever seeded into
/// the dev baseline** — the fixtures build their own configuration and tear it down.
library;

import 'dart:io';

import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// Stable ids, so the same vector addresses the same thing in every engine.
const vCategoryRestaurant = 'cat-restaurant';
const vCategoryNandbhog = 'cat-nandbhog';
const vCategoryRoom = 'cat-room';
const vCategoryBanquet = 'cat-banquet';
const vBandLower = 'band-room-lower';
const vBandUpper = 'band-room-upper';
const vSubtypeHall = 'subtype-hall';
const vStatusA = 'STATUS_A';

BusinessDate vDate(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return BusinessDate.of(parts[0], parts[1], parts[2]);
}

/// One configured rule, as every engine will hold it.
class RuleVector {
  const RuleVector({
    required this.id,
    required this.category,
    required this.rateBp,
    required this.treatment,
    required this.basis,
    this.from = '2026-04-01',
    this.to,
    this.bandId,
    this.bandFloor,
    this.bandCeiling,
    this.subtypeId,
    this.premisesStatus,
  });

  final String id;
  final String category;
  final int rateBp;
  final TaxTreatment treatment;

  /// Null models a legacy rule the server would now refuse to create (A1), kept as a
  /// vector because a **cache** can still hold one and must say `incompleteRule`.
  final EnteredBasis? basis;

  final String from;
  final String? to;
  final String? bandId;
  final int? bandFloor;
  final int? bandCeiling;
  final String? subtypeId;
  final String? premisesStatus;
}

/// The four verified V1 rules, exactly as the committed baseline installs them (B11).
const verifiedBaseline = <RuleVector>[
  RuleVector(
    id: 'rule-restaurant',
    category: vCategoryRestaurant,
    rateBp: 500,
    treatment: TaxTreatment.inclusive,
    basis: EnteredBasis.inclusiveTotal,
  ),
  // Independent of Restaurant: its own row, referencing nothing of it (D-089).
  RuleVector(
    id: 'rule-nandbhog',
    category: vCategoryNandbhog,
    rateBp: 500,
    treatment: TaxTreatment.inclusive,
    basis: EnteredBasis.inclusiveTotal,
  ),
  // Generic: no band, because no tariff threshold has been verified (D-096).
  RuleVector(
    id: 'rule-room',
    category: vCategoryRoom,
    rateBp: 500,
    treatment: TaxTreatment.inclusive,
    basis: EnteredBasis.inclusiveTotal,
  ),
  RuleVector(
    id: 'rule-banquet',
    category: vCategoryBanquet,
    rateBp: 0,
    treatment: TaxTreatment.none,
    basis: EnteredBasis.inclusiveTotal,
  ),
];

/// A synthetic configured 0% — a real rule, and financially different from no rule.
const zeroRateVector = RuleVector(
  id: 'rule-zero',
  category: vCategoryRestaurant,
  rateBp: 0,
  treatment: TaxTreatment.inclusive,
  basis: EnteredBasis.inclusiveTotal,
);

/// A legacy incomplete rule: no basis, so unusable and honest about it.
const incompleteVector = RuleVector(
  id: 'rule-legacy',
  category: vCategoryRestaurant,
  rateBp: 500,
  treatment: TaxTreatment.inclusive,
  basis: null,
);

/// Two disjoint Room bands — the configuration D-093 exists to permit.
const roomBandVectors = <RuleVector>[
  RuleVector(
    id: 'rule-room-lower',
    category: vCategoryRoom,
    rateBp: 500,
    treatment: TaxTreatment.inclusive,
    basis: EnteredBasis.inclusiveTotal,
    bandId: vBandLower,
    bandFloor: 0,
    bandCeiling: 750000,
  ),
  RuleVector(
    id: 'rule-room-upper',
    category: vCategoryRoom,
    rateBp: 1200,
    treatment: TaxTreatment.inclusive,
    basis: EnteredBasis.inclusiveTotal,
    bandId: vBandUpper,
    bandFloor: 750000,
    bandCeiling: null,
  ),
];

const subtypeVector = RuleVector(
  id: 'rule-banquet-hall',
  category: vCategoryBanquet,
  rateBp: 1800,
  treatment: TaxTreatment.inclusive,
  basis: EnteredBasis.inclusiveTotal,
  subtypeId: vSubtypeHall,
);

const premisesVector = RuleVector(
  id: 'rule-restaurant-status',
  category: vCategoryRestaurant,
  rateBp: 500,
  treatment: TaxTreatment.inclusive,
  basis: EnteredBasis.inclusiveTotal,
  premisesStatus: vStatusA,
);

/// One row of the migration's assertion table (B9, B10).
///
/// **Not declared here.** The vectors live once, in
/// `20260901144002_revenue_arithmetic_parity.sql`, where the database asserts them on
/// every deploy. This side reads that same table so Dart cannot be edited to agree with
/// itself — the pattern `business_date_server_parity_test.dart` already uses for the
/// business-date rule that D-067 paid for.
class ArithmeticVector {
  const ArithmeticVector({
    required this.entered,
    required this.rateBp,
    required this.treatment,
    required this.gross,
    required this.tax,
    required this.net,
    required this.why,
  });

  final int entered;
  final int rateBp;
  final TaxTreatment treatment;
  final int gross;
  final int tax;
  final int net;
  final String why;

  @override
  String toString() => '$entered p @ $rateBp bp ${treatment.name} — $why';
}

const revenueParityMigration =
    'supabase/migrations/20260901144002_revenue_arithmetic_parity.sql';

/// Parses the migration's `values (...)` table.
///
/// Deliberately strict: an unparseable file, or one with no rows, throws rather than
/// yielding an empty list. A parity suite that silently checks nothing is worse than no
/// parity suite, because it reports success.
List<ArithmeticVector> readArithmeticVectors() {
  final sql = File(revenueParityMigration).readAsStringSync();
  final row = RegExp(
    r"\(\s*(\d+)::bigint,\s*(\d+),\s*'(\w+)',\s*"
    r"(\d+)::bigint,\s*(\d+)::bigint,\s*(\d+)::bigint,\s*'([^']*)'\s*\)",
  );
  final vectors = [
    for (final m in row.allMatches(sql))
      ArithmeticVector(
        entered: int.parse(m.group(1)!),
        rateBp: int.parse(m.group(2)!),
        treatment: TaxTreatment.fromName(m.group(3)!),
        gross: int.parse(m.group(4)!),
        tax: int.parse(m.group(5)!),
        net: int.parse(m.group(6)!),
        why: m.group(7)!,
      ),
  ];
  if (vectors.length < 10) {
    throw StateError(
      'only ${vectors.length} parity vectors were parsed from '
      '$revenueParityMigration — the table moved or the format changed, and a parity '
      'suite that checks nothing reports success',
    );
  }
  return vectors;
}
