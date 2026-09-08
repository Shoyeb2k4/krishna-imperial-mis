/// The local reporting engine: the P&L a device can produce with no network.
///
/// Phase 5 Slice 3, and the first of the two engines `ARCHITECTURE.md` §6.1 draws. Slice 5
/// lifted the orchestration into [ReportingEngine] so the remote engine is the same code
/// over a different source — the reasoning is there, and it is not a convenience: an engine
/// that performs no business arithmetic (spec §21.2) has nothing left to differ about
/// except the rows it sums.
///
/// **Local is the default on every screen and is never gated on the network** (spec §21.2,
/// §21.4, and `CLAUDE.md`'s hard constraints). It reads the synchronised canonical cache,
/// so it answers from what the server last told this device — and says so, per side,
/// through the coverage the source carries. It never consults [RemoteReportingEngine], and
/// nothing about its availability depends on the server being reachable.
library;

import 'package:krishna_mis/data/reporting/reporting_engine.dart';

export 'package:krishna_mis/data/reporting/reporting_engine.dart'
    show ReportEnvelope, ReportingEngine;

/// Reads canonical facts this device holds and produces a P&L.
final class LocalReportingEngine extends ReportingEngine {
  const LocalReportingEngine(super.source);
}
