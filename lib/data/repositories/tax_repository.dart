/// Reads and writes date-effective tax configuration.
///
/// The one rule this file exists to defend: **two active rules must never both claim the
/// same date for the same revenue category.** SQLite cannot express that as a constraint,
/// so it is enforced here inside a transaction — checked and written atomically, never
/// checked-then-written. Postgres will additionally enforce it with an exclusion
/// constraint over a `daterange`, and that one is the guarantee (D-037).
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

class TaxRepository {
  TaxRepository(this._db);

  final AppDatabase _db;

  Future<TaxRuleSet> rulesFor(String revenueCategoryId) async {
    final rows = await (_db.select(
      _db.revenueTaxRates,
    )..where((t) => t.revenueCategoryId.equals(revenueCategoryId))).get();
    return TaxRuleSet(rows.map(_toRule));
  }

  /// Every category's rules, keyed by category id. One query for the whole tax screen.
  Future<Map<String, TaxRuleSet>> allRules() async {
    final rows = await _db.select(_db.revenueTaxRates).get();
    final grouped = <String, List<TaxRule>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.revenueCategoryId, () => []).add(_toRule(row));
    }
    return {
      for (final entry in grouped.entries) entry.key: TaxRuleSet(entry.value),
    };
  }

  Stream<Map<String, TaxRuleSet>> watchAllRules() =>
      _db.select(_db.revenueTaxRates).watch().map((rows) {
        final grouped = <String, List<TaxRule>>{};
        for (final row in rows) {
          grouped
              .putIfAbsent(row.revenueCategoryId, () => [])
              .add(_toRule(row));
        }
        return {
          for (final entry in grouped.entries)
            entry.key: TaxRuleSet(entry.value),
        };
      });

  /// The rule that governed a business date.
  ///
  /// Historical reports call this with the transaction's own business date, so a report
  /// re-run next year resolves the rule that was in force *then* — not today's.
  Future<TaxRule?> resolveFor({
    required String revenueCategoryId,
    required BusinessDate businessDate,
  }) async => (await rulesFor(revenueCategoryId)).ruleFor(businessDate);

  /// Adds a rule, refusing anything that would overlap an existing active period.
  ///
  /// The read and the write share one transaction, so two rules cannot slip past each
  /// other's check.
  Future<void> addRule({
    required String id,
    required String orgId,
    required String revenueCategoryId,
    required int rateBasisPoints,
    required TaxTreatment treatment,
    required BusinessDate effectiveFrom,
    required String createdBy,
    required DateTime now,
    BusinessDate? effectiveTo,
    String? note,
  }) async {
    final candidate = TaxRule(
      id: id,
      revenueCategoryId: revenueCategoryId,
      rateBasisPoints: rateBasisPoints,
      treatment: treatment,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
      note: note,
    );

    await _db.transaction(() async {
      final category = await (_db.select(
        _db.revenueCategories,
      )..where((t) => t.id.equals(revenueCategoryId))).getSingleOrNull();
      if (category == null) {
        throw const TaxRuleRejected(TaxRuleRefusal.categoryMissing);
      }

      final existing = await rulesFor(revenueCategoryId);
      final refusal = existing.refusalFor(candidate);
      if (refusal != null) throw TaxRuleRejected(refusal);

      await _db
          .into(_db.revenueTaxRates)
          .insert(
            RevenueTaxRatesCompanion.insert(
              id: id,
              orgId: orgId,
              revenueCategoryId: revenueCategoryId,
              rateBasisPoints: rateBasisPoints,
              treatment: treatment.name,
              effectiveFrom: effectiveFrom.iso,
              effectiveTo: Value(effectiveTo?.iso),
              note: Value(note),
              createdBy: createdBy,
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  /// Supersedes an open-ended rule with a new one from [changeoverDate].
  ///
  /// This is the correct way to change a rate: the old period is *closed* at the
  /// changeover and the new one begins there. The historical treatment is untouched, so
  /// last year's Net Sales cannot move. Both writes share one transaction — a rate change
  /// must never leave a gap or an overlap even for an instant.
  Future<void> supersede({
    required String currentRuleId,
    required String newRuleId,
    required String orgId,
    required String revenueCategoryId,
    required int newRateBasisPoints,
    required TaxTreatment newTreatment,
    required BusinessDate changeoverDate,
    required String createdBy,
    required DateTime now,
    String? note,
  }) async {
    await _db.transaction(() async {
      final current = await (_db.select(
        _db.revenueTaxRates,
      )..where((t) => t.id.equals(currentRuleId))).getSingleOrNull();
      if (current == null) {
        throw const TaxRuleRejected(TaxRuleRefusal.categoryMissing);
      }
      final currentFrom = BusinessDate.tryParse(current.effectiveFrom);
      if (currentFrom == null || changeoverDate <= currentFrom) {
        throw const TaxRuleRejected(TaxRuleRefusal.endsBeforeItStarts);
      }

      await (_db.update(
        _db.revenueTaxRates,
      )..where((t) => t.id.equals(currentRuleId))).write(
        RevenueTaxRatesCompanion(
          effectiveTo: Value(changeoverDate.iso),
          rowVersion: Value(current.rowVersion + 1),
          updatedAt: Value(now),
        ),
      );

      await _db
          .into(_db.revenueTaxRates)
          .insert(
            RevenueTaxRatesCompanion.insert(
              id: newRuleId,
              orgId: orgId,
              revenueCategoryId: revenueCategoryId,
              rateBasisPoints: newRateBasisPoints,
              treatment: newTreatment.name,
              effectiveFrom: changeoverDate.iso,
              note: Value(note),
              createdBy: createdBy,
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  /// Archives a rule. Never deletes — a rate that governed real revenue stays on record.
  Future<void> archiveRule({required String id, required DateTime now}) async {
    final updated =
        await (_db.update(
          _db.revenueTaxRates,
        )..where((t) => t.id.equals(id))).write(
          RevenueTaxRatesCompanion(
            archivedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    if (updated == 0) {
      throw const TaxRuleRejected(TaxRuleRefusal.categoryMissing);
    }
  }

  TaxRule _toRule(RevenueTaxRateRow row) => TaxRule(
    id: row.id,
    revenueCategoryId: row.revenueCategoryId,
    rateBasisPoints: row.rateBasisPoints,
    treatment: TaxTreatment.fromName(row.treatment),
    effectiveFrom: BusinessDate.tryParse(row.effectiveFrom)!,
    effectiveTo: row.effectiveTo == null
        ? null
        : BusinessDate.tryParse(row.effectiveTo!),
    archivedAt: row.archivedAt,
    note: row.note,
  );
}
