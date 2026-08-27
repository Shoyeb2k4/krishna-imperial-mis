/// How a transaction remembers which master it pointed at — and what that master was
/// *called at the time*.
///
/// Master spec §12: renaming a master must not silently corrupt the interpretation of
/// history. Three mechanisms, together:
///
/// 1. **Immutable `code`.** Assigned at creation, never edited. History and grants key
///    on it, so a rename can never break a join or a report grouping.
/// 2. **Stable `id`.** All aggregation groups by id, so totals are unaffected by any
///    display change whatsoever.
/// 3. **Label snapshot.** The transaction stores the name as it read on the day it was
///    recorded. Reports show the *current* name by default — that is what a manager
///    expects when a genuine typo is fixed — while the document detail and the audit
///    trail can always show what was actually on screen when the entry was made.
///
/// Re-purposing (renaming "Water" to "Diesel") remains prohibited: archive and create
/// new. That is a policy no schema can enforce on its own, so the system makes it
/// visible instead — every rename is audited, and the snapshot means history still
/// reads correctly even if someone does it anyway.
library;

import 'package:meta/meta.dart';

/// A pointer to a master record, plus what it was called when it was chosen.
@immutable
final class MasterReference {
  const MasterReference({
    required this.id,
    required this.code,
    required this.labelSnapshot,
  });

  /// Stable identity. Everything aggregates on this.
  final String id;

  /// Immutable business code, e.g. `KIRANA`, `CCR`, `ELECTRICITY`.
  final String code;

  /// The display name at the moment the transaction was recorded.
  final String labelSnapshot;

  /// What to show the user.
  ///
  /// [currentName] is the master's name today. When it differs from the snapshot the
  /// caller can surface both; by default the current name wins, because a corrected
  /// spelling should propagate and a stale label helps nobody on a summary screen.
  String displayName({String? currentName}) => currentName ?? labelSnapshot;

  /// True when the master has been renamed since this transaction was recorded.
  /// Surfaced on the transaction detail and in the audit view, never hidden.
  bool wasRenamedSince(String currentName) => currentName != labelSnapshot;

  @override
  bool operator ==(Object other) =>
      other is MasterReference &&
      other.id == id &&
      other.code == code &&
      other.labelSnapshot == labelSnapshot;

  @override
  int get hashCode => Object.hash(id, code, labelSnapshot);

  @override
  String toString() => 'MasterReference($code#$id "$labelSnapshot")';
}

/// Why a master may not be deleted.
///
/// There is no delete. Masters archive; `ON DELETE RESTRICT` makes orphaning impossible
/// at the database level (master spec §12, D-006).
enum ArchiveRefusal {
  /// Already archived — archiving again is a no-op, not an error.
  alreadyArchived,

  /// Has active children. Archive them first, so nobody is left with a live category
  /// hanging off a dead section.
  hasActiveChildren,
}

@immutable
final class ArchiveDecision {
  const ArchiveDecision.allowed() : refusal = null;
  const ArchiveDecision.refused(ArchiveRefusal reason) : refusal = reason;

  final ArchiveRefusal? refusal;

  bool get isAllowed => refusal == null;

  String? get message => switch (refusal) {
    null => null,
    ArchiveRefusal.alreadyArchived => 'This record is already archived.',
    ArchiveRefusal.hasActiveChildren =>
      'Archive the records underneath this one first.',
  };
}

abstract final class ArchivePolicy {
  /// Whether a master may be archived now.
  ///
  /// Referenced-by-history is deliberately **not** a refusal: archiving is exactly the
  /// right action for a master that has history, and the whole reason delete does not
  /// exist. Only live children block it.
  static ArchiveDecision evaluate({
    required bool isArchived,
    required int activeChildCount,
  }) {
    if (isArchived) {
      return const ArchiveDecision.refused(ArchiveRefusal.alreadyArchived);
    }
    if (activeChildCount > 0) {
      return const ArchiveDecision.refused(ArchiveRefusal.hasActiveChildren);
    }
    return const ArchiveDecision.allowed();
  }
}
