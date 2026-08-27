/// How much history a master already carries — and **how much that number can be
/// trusted**.
///
/// The distinction matters more than the count. This device holds a *cache*: current and
/// previous financial year by default, and only what has synced. A master untouched on
/// this phone may have three years of transactions on the server. Presenting a local
/// partial count as though it were the whole truth would let someone rename or archive a
/// master believing it unused (owner requirement §6).
///
/// So a count always travels with its source, the UI always says which it is, and
/// **archive eligibility is decided by the server** once one exists.
library;

import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:meta/meta.dart';

enum UsageSource {
  /// Counted from this device's local database. A **lower bound**, never authoritative.
  localCache,

  /// Counted by the server across all history. Authoritative.
  server,
}

/// The state of a usage figure.
@immutable
sealed class MasterUsage {
  const MasterUsage();

  /// Not yet determined — the query has not run, or the device is offline and no cached
  /// figure exists. Distinct from "zero", and shown as such.
  const factory MasterUsage.unknown({String reason}) = UsageUnknown;

  /// A figure from this device. Always a lower bound.
  const factory MasterUsage.local({
    required int transactionCount,
    BusinessDate? earliest,
    BusinessDate? latest,
  }) = UsageCounted.local;

  /// A figure from the server, covering all history.
  const factory MasterUsage.server({
    required int transactionCount,
    BusinessDate? earliest,
    BusinessDate? latest,
  }) = UsageCounted.server;

  /// Whether this figure may be relied on for a decision that must not be wrong —
  /// archiving, or telling a user their rename affects nothing.
  bool get isAuthoritative;

  /// Whether the master is *known* to carry history.
  ///
  /// A local count of zero returns false here but must never be read as "unused" — see
  /// [mayHaveMoreElsewhere].
  bool get hasKnownHistory;

  /// True whenever more transactions could exist beyond what this figure saw.
  bool get mayHaveMoreElsewhere;

  /// One line for the UI, honest about provenance.
  String get summary;
}

final class UsageUnknown extends MasterUsage {
  const UsageUnknown({this.reason = 'not checked yet'});

  final String reason;

  @override
  bool get isAuthoritative => false;
  @override
  bool get hasKnownHistory => false;
  @override
  bool get mayHaveMoreElsewhere => true;
  @override
  String get summary => 'Usage unknown — $reason';
}

final class UsageCounted extends MasterUsage {
  const UsageCounted.local({
    required this.transactionCount,
    this.earliest,
    this.latest,
  }) : source = UsageSource.localCache;

  const UsageCounted.server({
    required this.transactionCount,
    this.earliest,
    this.latest,
  }) : source = UsageSource.server;

  final UsageSource source;
  final int transactionCount;
  final BusinessDate? earliest;
  final BusinessDate? latest;

  @override
  bool get isAuthoritative => source == UsageSource.server;

  @override
  bool get hasKnownHistory => transactionCount > 0;

  @override
  bool get mayHaveMoreElsewhere => source == UsageSource.localCache;

  /// `12 Jun 2026 – 30 Jun 2026`, or a single date, or null.
  String? get period {
    if (earliest == null) return null;
    if (latest == null || latest == earliest) return earliest!.iso;
    return '${earliest!.iso} – ${latest!.iso}';
  }

  @override
  String get summary {
    final noun = transactionCount == 1 ? 'transaction' : 'transactions';
    final span = period == null ? '' : ' ($period)';
    return switch (source) {
      UsageSource.server => '$transactionCount $noun$span',
      UsageSource.localCache =>
        transactionCount == 0
            ? 'None on this device — the server has not been checked'
            : 'At least $transactionCount $noun$span on this device',
    };
  }
}

/// Reads usage figures. Implemented locally now, and by the remote data source once the
/// backend exists; the caller cannot confuse the two because the result says which.
abstract interface class MasterUsageReader {
  Future<MasterUsage> usageForMaster(String masterId);
  Future<MasterUsage> usageForVendor(String vendorId);
}
