/// The remote reporting engine: the authoritative server's answer to the same question.
///
/// Phase 5 Slice 5, and the second of the two engines `ARCHITECTURE.md` §6.1 draws. It is
/// [ReportingEngine] over [RemoteReportingSource], and the reasoning for that sharing is in
/// `reporting_engine.dart`: an engine performs no business arithmetic (spec §21.2), so the
/// only thing two engines can differ about is the rows they sum — which is precisely what
/// the D-020 parity suite exists to pin down.
///
/// ## What it is for
///
///   * **Verification.** It is the authoritative comparison point: given the same scope and
///     the same `ReportRange`, does the synchronised offline cache mean the same thing as
///     the server?
///   * **Ranges outside local retention.** Retention keeps the current and previous
///     financial year (D-170); an older range the device has never fetched is
///     `notDownloaded` locally and answerable here, online. That difference is **not** a
///     parity failure and the parity harness says so explicitly.
///
/// ## What it is not for
///
/// It is **not** a fallback the local engine reaches for, and the local engine does not
/// know it exists. Reporting is never gated on connectivity (spec §21.4), so a screen reads
/// the cache and shows what the cache can stand behind.
///
/// It **never writes**. It fills no cache, moves no coverage marker and touches no local
/// row — that is `ReportingSync`'s job, and a remote read that synchronised on the way past
/// would make the two sources agree by overwriting one of them (§30). Retry is therefore
/// free: the query is read-only, `stable` on the server, and a repeated call returns the
/// same primitives and changes nothing.
library;

import 'package:krishna_mis/data/remote/remote_reporting_source.dart';
import 'package:krishna_mis/data/reporting/reporting_engine.dart';

export 'package:krishna_mis/data/reporting/reporting_engine.dart'
    show ReportEnvelope, ReportingEngine;

/// Reads the authoritative server primitives and produces a P&L.
final class RemoteReportingEngine extends ReportingEngine {
  const RemoteReportingEngine(RemoteReportingSource super.source);
}
