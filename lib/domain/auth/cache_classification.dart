/// Who owns each thing the device has stored, and therefore what may be removed when
/// authority changes (D-048 §3).
///
/// The classification is written down because the alternative is deciding it row by row
/// at the moment of a destructive operation, which is exactly when nobody should be
/// improvising. Five kinds, and the rules for each are absolute:
///
/// | Kind | On revocation of a business unit |
/// |---|---|
/// | Organisation-global server cache | Retained while the user still has organisation access |
/// | Business-unit scoped server cache | **Purged** for the revoked unit |
/// | Scoped financial history | **Purged** for the revoked unit, except rows carrying the actor's own unsynced work |
/// | User-local and outbox data | **Never** purged. Not for this, not for anything |
/// | Authentication / session | Separate lifecycle entirely (`ARCHITECTURE.md` §8.2) |
///
/// ## Why financial history moved (D-068, final policy)
///
/// The Phase 3 checkpoint retained synced financial documents through a revocation, on
/// the reading that the purge covered server-owned *reference* data and that "nothing a
/// person typed is ever in scope". That reading was put to the project lead as an open
/// question, because it is a retention decision about company financial data and not an
/// implementer's call. **He decided the other way**, and the reasoning is the one that
/// chose Option A for reference data in the first place: encryption at rest is not a
/// reason to keep newly unauthorised financial information in somebody's browsable
/// cache, and a revocation that leaves the numbers on the device has not revoked much.
///
/// The distinction that survives is not "typed versus downloaded". It is **canonical
/// server-owned read data versus the actor's own attempt**:
///
/// * A synced expense is a *projection of server state*. The server hands it straight
///   back if authority returns, exactly like a department does. It is purged.
/// * A queued, failed, rejected or conflicted intent — and the document rows needed to
///   inspect and reconcile it — exists nowhere else. It is the user's own work, it is
///   tied to `actor_user_id` (D-050), and losing access to a property is not a reason to
///   destroy it. It is **retained**, stamped `expenses.scope_revoked_at`, and taken out
///   of every canonical financial read so it can never be browsed as though it were
///   still authorised.
///
/// A partially revoked shared bill is the interesting case, and it is handled rather
/// than avoided: the revoked property's lines and contributions go, the retained
/// property's stay, and the header is **downgraded to `scoped` with its document total
/// nulled**. It has to be. A complete header beside one remaining line is
/// `total − own share`, which is precisely the other property's share — the exact
/// arithmetic `expense_tables.dart` exists to prevent. Attachments follow the predicate
/// they always have (D-063): complete-document-only, so a downgrade takes the attachment
/// rows and the staged bytes with it.
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

  /// Financial documents this device has synced: expenses, their allocation lines,
  /// their period contributions and their attachment records.
  ///
  /// **Purged** for a revoked unit, like [businessUnitScoped] — but kept as its own kind
  /// because it is not the same deletion. Reference data for a revoked unit goes
  /// unconditionally. A financial document goes *unless it still carries the actor's own
  /// unsynced intent*, in which case it is retained and marked, because that intent
  /// exists nowhere else (D-068).
  ///
  /// Filing these under [businessUnitScoped] would lose exactly that exception; filing
  /// them under [organizationGlobal] would be untrue. The difference is two lines long
  /// and it is the whole policy, so it gets its own name.
  scopedFinancialHistory,
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

  /// Whether a confirmed revocation removes rows of this table for the revoked unit.
  bool get isPurgedOnRevocation =>
      ownership == CacheOwnership.businessUnitScoped ||
      ownership == CacheOwnership.scopedFinancialHistory;

  /// Whether that removal must spare rows carrying the actor's own unsynced work.
  ///
  /// True only for financial documents. Reference data has no such exception: there is
  /// no sense in which a cached department is somebody's unsent attempt.
  bool get retainsUnsyncedWork =>
      ownership == CacheOwnership.scopedFinancialHistory;
}

abstract final class CacheClassification {
  /// Every local table, in an order that is safe to delete top to bottom.
  ///
  /// Children come before parents, so a purge never leaves an orphan and never trips a
  /// foreign key on the way through (D-048 §4). `revenue_tax_rates` precedes
  /// `revenue_categories` for the same reason.
  static const List<CachedTable> tables = [
    // ── Business-unit scoped: removed when that unit is revoked ──────────────
    // Revenue reference configuration, reached through its revenue category exactly as
    // `revenue_tax_rates` is. Purged with the unit, and the components that used them
    // keep their own snapshots, so a retained entry stays explainable after the rule row
    // it named is gone (D-070 §11).
    CachedTable(
      'revenue_value_bands',
      CacheOwnership.businessUnitScoped,
      unitColumn: null,
    ),
    CachedTable(
      'revenue_supply_subtypes',
      CacheOwnership.businessUnitScoped,
      unitColumn: null,
    ),
    CachedTable(
      'business_unit_tax_statuses',
      CacheOwnership.businessUnitScoped,
      unitColumn: 'business_unit_id',
    ),
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

    // ── Scoped financial history: purged, sparing unsynced work ─────
    //
    // Present here because a table absent from this list is a table nobody has decided
    // anything about. All four were missing until the Phase 3 acceptance found sign-out
    // throwing a foreign-key error on a device that had synced an expense: the guard
    // "every table must be classified" was written down but never run against the real
    // schema, so Phase 3 added four tables and nothing objected. It is enforced now
    // against `AppDatabase.allTables`, in both directions.
    //
    // They are **purged** for a revoked unit (D-068, the project lead's final policy),
    // except where a document still carries the actor's own queued, failed, rejected or
    // conflicted intent — see the library comment for why the line falls there.
    //
    // Deletion order below is children before parents, with `expenses` last, so no step
    // ever leaves an orphan and the cascade never has to be relied on. Their
    // `business_unit_id` stays a soft pointer: a retained row may outlive the cached
    // unit it names, and on the retention path above it does exactly that.
    CachedTable('expense_attachments', CacheOwnership.scopedFinancialHistory),
    CachedTable(
      'expense_period_allocations',
      CacheOwnership.scopedFinancialHistory,
    ),
    CachedTable(
      'expense_allocations',
      CacheOwnership.scopedFinancialHistory,
      unitColumn: 'business_unit_id',
    ),
    CachedTable('expenses', CacheOwnership.scopedFinancialHistory),

    // Revenue, on the same policy and for the same reasons (Phase 4 Slice 3). Components
    // before entries, so no step leaves an orphan. A revenue entry belongs to exactly one
    // business unit, so unlike an expense allocation the unit is named on the header.
    CachedTable('revenue_components', CacheOwnership.scopedFinancialHistory),
    CachedTable(
      'revenue_entries',
      CacheOwnership.scopedFinancialHistory,
      unitColumn: 'business_unit_id',
    ),

    // ── User-local: never purged for any authority reason ────────────────────
    CachedTable('sync_outbox', CacheOwnership.userLocal),
    CachedTable('app_meta', CacheOwnership.userLocal),
  ];

  /// The tables a revocation removes rows from, in safe deletion order.
  static List<CachedTable> get purgedOnRevocation => [
    for (final table in tables)
      if (table.isPurgedOnRevocation) table,
  ];

  /// Tables no revocation removes a row from, for any unit. Asserted by the tests,
  /// because "we did not mean to delete that" is not a property anybody should be
  /// trusting to review.
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
