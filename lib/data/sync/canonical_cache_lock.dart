/// One serialisation boundary for the canonical caches (D-227, D-188).
///
/// Phase 5 Slice 11. A report is several cache reads, and a synchronisation is a server
/// answer followed by one writing transaction. Each is internally consistent on its own. A
/// write landing **between two reads** of the same report is not: the report then pairs
/// figures from one snapshot with figures from another, and every number still reconciles.
///
/// Slice 8 closed that for the P&L surface with a lock that lived in the P&L feature. The
/// settlement preview and the settlement refresh were built afterwards and never took part,
/// and Slice 11 reproduced both mixes deterministically. The boundary therefore lives here,
/// in the data layer, and every reader and writer of the canonical reporting and owner
/// caches takes the same one:
///
///  * P&L report reads, drill-down reads and the P&L synchronisation;
///  * the settlement preview's reads, as one span;
///  * the settlement refresh, as one span.
///
/// It is in-process and not re-entrant. Nothing that runs while holding it may ask for it
/// again.
library;

import 'dart:async';

final class CanonicalCacheLock {
  Future<void> _tail = Future<void>.value();

  /// Runs [action] after every action already queued, and before any queued after it.
  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return previous.then((_) => action()).whenComplete(released.complete);
  }
}
