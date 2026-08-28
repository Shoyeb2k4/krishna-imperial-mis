/// Vendors — deliberately the lightest master in the system.
///
/// "Local Vegetable Market" with nothing else filled in is a complete, valid vendor. The
/// suppliers these properties buy from are small and local; demanding a GSTIN or an
/// address would mean the field gets filled with rubbish or the vendor never gets
/// recorded at all. **Name is the only requirement.**
///
/// Vendors are searched during expense entry on a phone, often at speed, so lookup is
/// built for that from the start rather than retrofitted.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/masters/master_reference.dart';
import 'package:meta/meta.dart';

/// A vendor as the application uses it.
@immutable
final class Vendor {
  const Vendor({
    required this.id,
    required this.code,
    required this.name,
    this.phone,
    this.gstin,
    this.address,
    this.notes,
    this.defaultBusinessUnitId,
    this.defaultCategoryId,
    this.archivedAt,
  });

  final String id;

  /// Immutable once created, like every master (D-035).
  final String code;
  final String name;

  // Everything below is optional, and stays optional.
  final String? phone;
  final String? gstin;
  final String? address;
  final String? notes;
  final String? defaultBusinessUnitId;
  final String? defaultCategoryId;

  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  /// The default business unit *this user* may actually act on (D-049).
  ///
  /// [defaultBusinessUnitId] is canonical server data and an operational convenience —
  /// it pre-selects a property on the entry form. It is **not** ownership, visibility,
  /// authorisation or accounting scope: a grocery supplier serving both properties is
  /// one vendor, and which property happens to be pre-selected says nothing about who
  /// may see it.
  ///
  /// So the constraint is applied here, as a derivation over the caller's current
  /// scope, rather than by editing the record. Nothing is written, no row version
  /// moves, no audit event is raised, and when the scope comes back the configured
  /// default becomes usable again on its own.
  ///
  /// [scopedUnits] is null for an org-wide holder, for whom every default is reachable.
  String? effectiveDefaultBusinessUnitId(Set<String>? scopedUnits) {
    final configured = defaultBusinessUnitId;
    if (configured == null || scopedUnits == null) return configured;
    return scopedUnits.contains(configured) ? configured : null;
  }

  /// Whether this vendor carries a default the current user cannot use.
  ///
  /// Worth surfacing quietly on the detail panel — "the usual property for this
  /// supplier is one you do not have access to" is useful context, and silently
  /// showing no default at all would look like a data problem.
  bool hasUnreachableDefault(Set<String>? scopedUnits) =>
      defaultBusinessUnitId != null &&
      effectiveDefaultBusinessUnitId(scopedUnits) == null;

  /// Whether anything beyond the name was recorded. Drives whether the detail panel
  /// shows a contact block at all, rather than a column of empty labels.
  bool get hasContactDetails =>
      (phone?.isNotEmpty ?? false) ||
      (gstin?.isNotEmpty ?? false) ||
      (address?.isNotEmpty ?? false);

  MasterReference get reference =>
      MasterReference(id: id, code: code, labelSnapshot: name);
}

class VendorWriteRefused implements Exception {
  const VendorWriteRefused(this.message);
  final String message;

  @override
  String toString() => 'VendorWriteRefused: $message';
}

class VendorRepository {
  VendorRepository(this._db);

  final AppDatabase _db;

  Future<List<Vendor>> list({bool includeArchived = false}) async {
    final query = _db.select(_db.vendors)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    if (!includeArchived) {
      query.where((t) => t.archivedAt.isNull());
    }
    return (await query.get()).map(_toVendor).toList(growable: false);
  }

  Stream<List<Vendor>> watch({bool includeArchived = false}) {
    final query = _db.select(_db.vendors)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    if (!includeArchived) {
      query.where((t) => t.archivedAt.isNull());
    }
    return query.watch().map(
      (rows) => rows.map(_toVendor).toList(growable: false),
    );
  }

  /// Fast lookup for expense entry.
  ///
  /// Ranks prefix matches above contained matches, because someone typing "sha" wants
  /// "Sharma Traders" first, not "Krishna Sharma Provisions". Archived vendors are
  /// excluded — they must not be selectable for a new transaction.
  Future<List<Vendor>> search(String term, {int limit = 20}) async {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return list();

    final rows =
        await (_db.select(_db.vendors)..where(
              (t) => t.archivedAt.isNull() & t.name.lower().contains(needle),
            ))
            .get();

    final vendors = rows.map(_toVendor).toList()
      ..sort((a, b) {
        final aPrefix = a.name.toLowerCase().startsWith(needle);
        final bPrefix = b.name.toLowerCase().startsWith(needle);
        if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return vendors.take(limit).toList(growable: false);
  }

  Future<Vendor?> byId(String id) async {
    final row = await (_db.select(
      _db.vendors,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toVendor(row);
  }

  /// Creates a vendor. Only [name] is required.
  Future<void> create({
    required String id,
    required String orgId,
    required String code,
    required String name,
    required DateTime now,
    String? phone,
    String? gstin,
    String? address,
    String? notes,
    String? defaultBusinessUnitId,
    String? defaultCategoryId,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const VendorWriteRefused('A vendor name is required.');
    }

    final duplicate =
        await (_db.select(_db.vendors)
              ..where((t) => t.name.lower().equals(cleanName.toLowerCase())))
            .getSingleOrNull();
    if (duplicate != null) {
      throw VendorWriteRefused(
        duplicate.archivedAt == null
            ? 'A vendor called "${duplicate.name}" already exists.'
            : 'An archived vendor called "${duplicate.name}" already exists. '
                  'Restore it instead of creating a duplicate.',
      );
    }

    await _db
        .into(_db.vendors)
        .insert(
          VendorsCompanion.insert(
            id: id,
            orgId: orgId,
            code: code,
            name: cleanName,
            phone: Value(_orNull(phone)),
            gstin: Value(_orNull(gstin)),
            address: Value(_orNull(address)),
            notes: Value(_orNull(notes)),
            defaultBusinessUnitId: Value(_orNull(defaultBusinessUnitId)),
            defaultCategoryId: Value(_orNull(defaultCategoryId)),
            updatedAt: now,
          ),
        );
  }

  /// Updates the editable fields. The **code is not among them** — it is immutable, and
  /// there is deliberately no parameter for it.
  Future<void> update({
    required String id,
    required DateTime now,
    String? name,
    String? phone,
    String? gstin,
    String? address,
    String? notes,
    String? defaultBusinessUnitId,
    String? defaultCategoryId,
  }) async {
    if (name != null && name.trim().isEmpty) {
      throw const VendorWriteRefused('A vendor name is required.');
    }

    final current = await (_db.select(
      _db.vendors,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (current == null) {
      throw const VendorWriteRefused('That vendor does not exist.');
    }

    await (_db.update(_db.vendors)..where((t) => t.id.equals(id))).write(
      VendorsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        phone: Value(_orNull(phone)),
        gstin: Value(_orNull(gstin)),
        address: Value(_orNull(address)),
        notes: Value(_orNull(notes)),
        defaultBusinessUnitId: Value(_orNull(defaultBusinessUnitId)),
        defaultCategoryId: Value(_orNull(defaultCategoryId)),
        rowVersion: Value(current.rowVersion + 1),
        updatedAt: Value(now),
      ),
    );
  }

  /// Archives a vendor. **Never deletes.**
  ///
  /// A vendor referenced by financial records must remain resolvable forever, so every
  /// historical expense keeps showing who it was paid to. Archiving only removes the
  /// vendor from selection for *new* transactions.
  Future<void> archive({required String id, required DateTime now}) async {
    final updated =
        await (_db.update(_db.vendors)..where((t) => t.id.equals(id))).write(
          VendorsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
    if (updated == 0) {
      throw const VendorWriteRefused('That vendor does not exist.');
    }
  }

  Future<void> unarchive({required String id, required DateTime now}) async {
    final updated =
        await (_db.update(_db.vendors)..where((t) => t.id.equals(id))).write(
          const VendorsCompanion(
            archivedAt: Value(null),
          ).copyWith(updatedAt: Value(now)),
        );
    if (updated == 0) {
      throw const VendorWriteRefused('That vendor does not exist.');
    }
  }

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Vendor _toVendor(VendorRow row) => Vendor(
    id: row.id,
    code: row.code,
    name: row.name,
    phone: row.phone,
    gstin: row.gstin,
    address: row.address,
    notes: row.notes,
    defaultBusinessUnitId: row.defaultBusinessUnitId,
    defaultCategoryId: row.defaultCategoryId,
    archivedAt: row.archivedAt,
  );
}
