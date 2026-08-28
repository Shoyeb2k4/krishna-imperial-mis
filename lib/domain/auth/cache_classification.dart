/// Who owns each thing the device has stored, and therefore what may be removed when
/// authority changes (D-048 §3).
///
/// The classification is written down because the alternative is deciding it row by row
/// at the moment of a destructive operation, which is exactly when nobody should be
/// improvising. Four kinds, and the rules for each are absolute:
///
/// | Kind | On revocation of a business unit |
/// |---|---|
/// | Organisation-global server cache | Retained while the user still has organisation access |
/// | Business-unit scoped server cache | **Purged** for the revoked unit |
/// | User-local and outbox data | **Never** purged. Not for this, not for anything |
/// | Authentication / session | Separate lifecycle entirely (`ARCHITECTURE.md` §8.2) |
///
/// The purge is safe precisely because of what it is limited to: server-owned reference
/// data, which the server will hand back the moment authority is restored. Nothing a
/// person typed is ever in scope.
library;

/// What owns a piece of locally cached data.
enum CacheOwnership {
  /// Reference data belonging to the organisation as a whole. A supplier serves the
  /// company; a payment method is how the company pays. Losing one property does not
  /// make these unreadable, and the server goes on returning them.
  organizationGlobal,

  /// Reference data belonging to exactly one business unit. The composite foreign-key
  /// ladder (D-040) means every one of these has precisely one owning property — there
  /// is no shared case to adjudicate, which is what makes the purge decidable.
  businessUnitScoped,

  /// Anything the user created or queued: the outbox, conflicts, rejections, attention
  /// state. **Never** removed by a cache purge, under any circumstances (D-048 §2).
  userLocal,

  /// Tokens and the database key. Governed by the sign-out and key-loss rules, not by
  /// this policy.
  session,
}

/// One locally cached table and what owns it.
///
/// Listed explicitly rather than inferred, so adding a table forces a decision about it
/// instead of letting it default into whichever behaviour happens to be convenient. The
/// purge asserts that every table it knows about appears here.
final class CachedTable {
  const CachedTable(this.name, this.ownership, {this.unitColumn});

  final String name;
  final CacheOwnership ownership;

  /// The column naming the owning business unit, for [CacheOwnership.businessUnitScoped].
  final String? unitColumn;

  bool get isPurgedOnRevocation =>
      ownership == CacheOwnership.businessUnitScoped;
}

abstract final class CacheClassification {
  /// Every local table, in an order that is safe to delete top to bottom.
  ///
  /// Children come before parents, so a purge never leaves an orphan and never trips a
  /// foreign key on the way through (D-048 §4). `revenue_tax_rates` precedes
  /// `revenue_categories` for the same reason.
  static const List<CachedTable> tables = [
    // ── Business-unit scoped: removed when that unit is revoked ──────────────
    CachedTable(
      'revenue_tax_rates',
      CacheOwnership.businessUnitScoped,
      // Reached through its revenue category; resolved by the purge, which walks the
      // hierarchy rather than trusting a denormalised column the local schema lacks.
      unitColumn: null,
    ),
    CachedTable(
      'expense_categories',
      CacheOwnership.businessUnitScoped,
      unitColumn: null,
    ),
    CachedTable(
      'sections',
      CacheOwnership.businessUnitScoped,
      unitColumn: null,
    ),
    CachedTable(
      'departments',
      CacheOwnership.businessUnitScoped,
      unitColumn: 'business_unit_id',
    ),
    CachedTable(
      'revenue_categories',
      CacheOwnership.businessUnitScoped,
      unitColumn: 'business_unit_id',
    ),
    CachedTable(
      'period_locks',
      CacheOwnership.businessUnitScoped,
      unitColumn: 'business_unit_id',
    ),
    CachedTable(
      'business_units',
      CacheOwnership.businessUnitScoped,
      unitColumn: 'id',
    ),

    // ── Organisation-global: retained ───────────────────────────────────────
    //
    // Vendors sit here deliberately, and the reasoning is worth stating because D-048
    // lists "scoped Vendors" among the things to purge.
    //
    // A vendor is a supplier of the *company*. Server-side, `vendors_read` is
    // organisation-level: a manager who loses Crystal Canopy but keeps Hotel Krishna is
    // still returned every vendor. Purging one locally would therefore delete a row the
    // very next pull puts straight back — churn, not security. `default_business_unit_id`
    // is a pre-selection for the entry form, not ownership, and treating a UI convenience
    // as a tenancy boundary is how a company-wide supplier list quietly fragments.
    //
    // D-048 §4 asks for the classification to be fixed rather than for exceptions to be
    // bolted on, so it is fixed here rather than special-cased in the purge. If vendors
    // should genuinely become unit-scoped, that is a change to `vendors_read` and to the
    // vendor model, on both sides — not a client-only deletion rule.
    CachedTable('vendors', CacheOwnership.organizationGlobal),
    CachedTable('payment_methods', CacheOwnership.organizationGlobal),
    CachedTable('period_lock_events', CacheOwnership.organizationGlobal),

    // ── User-local: never purged for any authority reason ────────────────────
    CachedTable('sync_outbox', CacheOwnership.userLocal),
    CachedTable('app_meta', CacheOwnership.userLocal),
  ];

  /// The tables a revocation removes rows from, in safe deletion order.
  static List<CachedTable> get purgedOnRevocation => [
    for (final table in tables)
      if (table.isPurgedOnRevocation) table,
  ];

  /// Tables that must survive a purge untouched. Asserted by the tests, because "we did
  /// not mean to delete that" is not a property anybody should be trusting to review.
  static List<CachedTable> get neverPurged => [
    for (final table in tables)
      if (!table.isPurgedOnRevocation) table,
  ];

  static CacheOwnership ownershipOf(String tableName) => tables
      .firstWhere(
        (t) => t.name == tableName,
        orElse: () => throw ArgumentError.value(
          tableName,
          'tableName',
          'unclassified local table — every table must be given an owner before it can '
              'be cached, so that authority changes have a defined effect on it',
        ),
      )
      .ownership;
}
