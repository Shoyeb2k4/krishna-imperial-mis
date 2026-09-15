/// The drill-down beneath the phone P&L: a page per level, and a read-only document page
/// (Phase 5 Slice 10).
///
/// Pushed on the Reports branch, so Android back walks up one level at a time and the bottom
/// bar stays where it is. What a level holds and says is the shared drill-down view; this
/// file only arranges it for a phone.
///
/// A drill-down belongs to one report for one person. Signing in as somebody else, or
/// changing the property or period, returns to the P&L rather than leaving a page up for a
/// report that is no longer on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart'
    show pnlMobileNavigationClearance;
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_view.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

/// Returns to the P&L when the person, what they may read, the property or the period changes.
void _returnToReportOnReset(WidgetRef ref, BuildContext context) {
  void back() {
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  ref
    ..listen(sessionProvider.select((s) => PnlAuthority.readKey(s.principal)), (
      previous,
      next,
    ) {
      if (previous != next) back();
    })
    ..listen(pnlSelectionProvider, (previous, next) {
      if (!identical(previous, next)) back();
    });
}

/// Opens [location] as a page on top of the current one.
void pushPnlDrillLevel(BuildContext context, PnlDrillLocation location) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobilePnlDrillPage(location: location),
      ),
    );

class MobilePnlDrillPage extends ConsumerWidget {
  const MobilePnlDrillPage({required this.location, super.key});

  final PnlDrillLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _returnToReportOnReset(ref, context);
    final crumbs = pnlDrillCrumbs(
      location,
      ref.watch(masterGraphProvider).value,
    );

    return Scaffold(
      key: const Key('pnl-drill-page'),
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(crumbs.last.label, key: const Key('pnl-drill-title')),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              [for (final c in crumbs) c.label].join(' › '),
              key: const Key('pnl-drill-path'),
              style: AppTypography.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: PnlDrillLevelList(
              location: location,
              compact: false,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                pnlMobileNavigationClearance,
              ),
              onOpen: (next) => pushPnlDrillLevel(context, next),
              onSelect: (request) {
                // Each open asks the server again, never a copy held from before (D-239).
                ref.invalidate(pnlDocumentDetailProvider(request));
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MobilePnlDocumentPage(request: request),
                  ),
                );
              },
              onReportChanged: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ),
        ],
      ),
    );
  }
}

class MobilePnlDocumentPage extends ConsumerWidget {
  const MobilePnlDocumentPage({required this.request, super.key});

  final PnlDocumentRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _returnToReportOnReset(ref, context);
    return Scaffold(
      key: const Key('pnl-document-page'),
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(switch (request) {
          PnlRevenueDocumentRequest() => 'Sale',
          PnlExpenseDocumentRequest() => 'Expense',
        }),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      // Clear of the docked [ + ] action, so the last line is never behind it.
      body: Padding(
        padding: const EdgeInsets.only(bottom: pnlMobileNavigationClearance),
        child: PnlDocumentDetail(request: request),
      ),
    );
  }
}
