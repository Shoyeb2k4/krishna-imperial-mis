/// The phone P&L's one export control: share the P&L as a PDF (Phase 7 Slice 8; D-293).
///
/// It sits in the Android Reports header beside Refresh, and it is offered only when the
/// report on screen is complete and the person holds view authority **and**
/// `reports.export` for its scope — the same decision the pipeline takes. Holding the app,
/// or reading the P&L, is not enough.
///
/// It shares what the screen already shows, from the device, with no synchronisation, so it
/// works offline whenever the report is complete here. There is no Android Excel, no
/// Android printing and no Android analysis export (D-293).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/features/export/export_centre_page.dart'
    show exportActionMessage;
import 'package:krishna_mis/features/export/export_pipeline.dart';
import 'package:krishna_mis/features/export/export_providers.dart';
import 'package:krishna_mis/features/export/export_share.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

class PnlShareAction extends ConsumerStatefulWidget {
  const PnlShareAction({super.key});

  @override
  ConsumerState<PnlShareAction> createState() => _PnlShareActionState();
}

class _PnlShareActionState extends ConsumerState<PnlShareAction> {
  @override
  void initState() {
    super.initState();
    // A file an earlier share left in the private cache goes when the P&L is opened.
    ref
        .read(exportShareCacheRootProvider.future)
        .then(removeEarlierShares, onError: (Object _) => 0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(exportActionProvider, (previous, next) {
      final last = next.last;
      if (last == null ||
          last.report != ExportReport.profitAndLoss ||
          identical(previous?.last, last)) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          key: const Key('pnl-share-outcome'),
          content: Text(exportActionMessage(last.result)),
        ),
      );
    });

    final principal = ref.watch(principalProvider);
    final source = exportSourceFrom(
      report: ExportReport.profitAndLoss,
      principal: principal,
      rules: ref.watch(businessDayRulesProvider).value ?? const {},
      pnl: ref.watch(pnlViewProvider),
      pnlPeriod: ref.watch(pnlSelectionProvider.select((s) => s.period)),
      dashboard: const AsyncValue.loading(),
    );
    final offered =
        source != null &&
        source.isComputed &&
        ExportPipeline.decide(
              principal,
              action: ExportAction.export,
              report: ExportReport.profitAndLoss,
              source: source,
            )
            is ExportPermitted;
    if (!offered) return const SizedBox.shrink();

    final running = ref.watch(exportActionProvider).isRunning;
    return IconButton(
      key: const Key('pnl-share-pdf'),
      tooltip: 'Share as PDF',
      onPressed: running
          ? null
          : () => ref
                .read(exportActionProvider.notifier)
                .share(ExportReport.profitAndLoss),
      icon: running
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share_outlined),
    );
  }
}
