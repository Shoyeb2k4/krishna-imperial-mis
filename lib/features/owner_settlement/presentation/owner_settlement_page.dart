/// The Owner Profit & Settlement Statement — **preview** (Phase 5 OA-3).
///
/// A separate screen from the P&L, on both platforms, because owner settlement is
/// owner-private financial information and must not be one tap away from an ordinary
/// report (OA-3 Q4). Reached only through a navigation entry shown to holders of
/// `owner_settlement.view` — and when reached any other way, it refuses, because the
/// decision is the preview service's and not this widget's.
///
/// ## What this file does and does not do
///
/// It **formats**. Every figure arrives computed by `OwnerSettlement.compute` (OA-2) from
/// the canonical Operating Profit in `domain/finance` (D-020); this file recomputes no
/// Operating Profit, no ownership percentage, no entitlement and no position, and a
/// structural guard fails the build if it starts to. It never reads a repository.
///
/// It is **a preview**, said on the screen in words. No finalize, reopen, lock, approval or
/// versioning exists in OA-3, by ruling (Q3).
///
/// The owner history and the P&L come from **two** authoritative snapshots, and each is
/// dated separately. No combined "as of" is shown, because none is proven (D-188).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/components/section_header.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_preview.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/owner_accounts/settlement/owner_settlement.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/owner_settlement/presentation/owner_settlement_providers.dart';
import 'package:timezone/timezone.dart' as tz;

class OwnerSettlementPage extends ConsumerStatefulWidget {
  const OwnerSettlementPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  ConsumerState<OwnerSettlementPage> createState() =>
      _OwnerSettlementPageState();
}

class _OwnerSettlementPageState extends ConsumerState<OwnerSettlementPage> {
  @override
  void initState() {
    super.initState();
    // OA-3 owns initiating both pulls. Once per session on opening; the Refresh control
    // repeats it on demand. The controller does nothing for a reader the settlement is
    // closed to, and nothing without a server.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sync = ref.read(ownerSettlementSyncProvider);
      if (sync.phase == OwnerSettlementSyncPhase.idle) {
        ref.read(ownerSettlementSyncProvider.notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final desktop = widget.shellKind == AppShellKind.desktop;
    final density = desktop ? AppDensity.compact : AppDensity.comfortable;
    final preview = ref.watch(ownerSettlementPreviewProvider);
    final sync = ref.watch(ownerSettlementSyncProvider);

    return ListView(
      key: const Key('owner-settlement-page'),
      padding: EdgeInsets.all(density.pagePadding),
      children: [
        SectionHeader(
          eyebrow: 'Owner accounts',
          title: 'Owner Profit & Settlement Statement',
          trailing: _RefreshControl(sync: sync),
        ),
        const _PreviewBanner(),
        const SizedBox(height: AppSpacing.md),
        const _MonthBar(),
        const SizedBox(height: AppSpacing.md),
        _SyncNotice(sync: sync, preview: preview.value),
        preview.when(
          loading: () => const _Loading(),
          error: (_, _) => _Message(
            key: const Key('owner-settlement-read-error'),
            icon: Icons.error_outline,
            title: 'The settlement could not be read on this device',
            message:
                'Nothing has been changed. Try again; if it persists, report it.',
            onRetry: () => ref.invalidate(ownerSettlementPreviewProvider),
          ),
          data: (value) => switch (value) {
            OwnerSettlementPreviewReady() => _Statement(
              ready: value,
              wide: desktop,
            ),
            OwnerSettlementPreviewUnavailable(:final reason) => _unavailable(
              reason,
              sync,
            ),
          },
        ),
      ],
    );
  }

  Widget _unavailable(
    OwnerSettlementUnavailableReason reason,
    OwnerSettlementSyncStatus sync,
  ) {
    final missingData =
        reason == OwnerSettlementUnavailableReason.ownerHistoryNotDownloaded ||
        reason == OwnerSettlementUnavailableReason.reportingNotDownloaded;

    // Still fetching what is missing: say so, rather than announcing a gap that may be
    // about to close.
    if (missingData && sync.phase == OwnerSettlementSyncPhase.synchronising) {
      return const _Message(
        key: Key('owner-settlement-synchronising'),
        icon: Icons.sync,
        title: 'Synchronising',
        message:
            'Bringing owner history and profit & loss up to date for this device.',
      );
    }

    // A pull was attempted and did not arrive, and the device holds nothing to show.
    // Never a zero: there is no figure (D-163).
    if (missingData && sync.phase == OwnerSettlementSyncPhase.failed) {
      return _Message(
        key: const Key('owner-settlement-sync-failed'),
        icon: Icons.cloud_off_outlined,
        title: 'Could not synchronise',
        message: sync.localFailure
            ? '${_reasonText(reason).message} This device could not prepare or record '
                  'the synchronisation, so nothing was asked of the server and nothing is '
                  'shown rather than an incomplete figure.'
            : '${_reasonText(reason).message} The server could not be reached, so '
                  'nothing is shown rather than an incomplete figure.',
        onRetry: () => ref.read(ownerSettlementSyncProvider.notifier).refresh(),
      );
    }

    final text = _reasonText(reason);
    return _Message(
      key: Key('owner-settlement-unavailable-${reason.name}'),
      icon: text.icon,
      title: text.title,
      message: text.message,
      onRetry: missingData
          ? () => ref.read(ownerSettlementSyncProvider.notifier).refresh()
          : null,
    );
  }
}

/// Plain sentences for each refusal. Never a code, an exception or a table name.
({IconData icon, String title, String message}) _reasonText(
  OwnerSettlementUnavailableReason reason,
) => switch (reason) {
  OwnerSettlementUnavailableReason.notAuthorised => (
    icon: Icons.lock_outline,
    title: 'Not available to your account',
    message:
        'The Owner Profit & Settlement Statement is visible only to people who hold '
        'owner settlement access.',
  ),
  OwnerSettlementUnavailableReason.reportingNotAuthorised => (
    icon: Icons.lock_outline,
    title: 'Combined profit & loss not available to your account',
    message:
        'The settlement is calculated from the combined profit & loss of both '
        'properties, which your account cannot read. A partial settlement is never shown.',
  ),
  OwnerSettlementUnavailableReason.ownerHistoryNotDownloaded => (
    icon: Icons.download_outlined,
    title: 'Owner history not downloaded',
    message: 'This device does not hold the complete owner history yet.',
  ),
  OwnerSettlementUnavailableReason.startDateNotConfigured => (
    icon: Icons.event_busy_outlined,
    title: 'Settlement start date not configured',
    message:
        'The date from which 50:50 ownership and owner settlement begin has not been '
        'set. No settlement is calculated until it is.',
  ),
  OwnerSettlementUnavailableReason.beforeStartDate => (
    icon: Icons.event_outlined,
    title: 'Before settlement begins',
    message:
        'Owner settlement had not begun in this month. Choose the month it begins or '
        'a later one.',
  ),
  OwnerSettlementUnavailableReason.reportingNotDownloaded => (
    icon: Icons.download_outlined,
    title: 'Profit & loss not downloaded',
    message:
        'This device does not hold the profit & loss this settlement is calculated '
        'from.',
  ),
  OwnerSettlementUnavailableReason.ownershipUnavailable => (
    icon: Icons.pie_chart_outline,
    title: 'Ownership does not resolve for this month',
    message:
        'The ownership shares for this month are not the fixed 50:50 split between '
        'two owners, so no settlement is calculated.',
  ),
};

// ── Chrome ───────────────────────────────────────────────────────────────────

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('owner-settlement-preview-banner'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: const BoxDecoration(
      color: AppColors.brassWash,
      borderRadius: AppRadius.allSmall,
    ),
    child: Row(
      children: [
        Text(
          'PREVIEW',
          style: AppTypography.overline.copyWith(color: AppColors.brass),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'A live settlement derived from canonical history. It is not a '
            'finalized statement and changes when the underlying figures change.',
            style: AppTypography.caption.copyWith(color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _MonthBar extends ConsumerWidget {
  const _MonthBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(settlementMonthProvider);
    final controller = ref.read(settlementMonthProvider.notifier);
    return Row(
      children: [
        IconButton(
          key: const Key('owner-settlement-previous-month'),
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: controller.previous,
        ),
        Text(
          _monthLabel(month),
          key: const Key('owner-settlement-month'),
          style: AppTypography.subheading,
        ),
        IconButton(
          key: const Key('owner-settlement-next-month'),
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          onPressed: controller.canGoNext ? controller.next : null,
        ),
      ],
    );
  }
}

class _RefreshControl extends ConsumerWidget {
  const _RefreshControl({required this.sync});

  final OwnerSettlementSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = sync.phase == OwnerSettlementSyncPhase.synchronising;
    return TextButton.icon(
      key: const Key('owner-settlement-refresh'),
      onPressed: running
          ? null
          : () => ref.read(ownerSettlementSyncProvider.notifier).refresh(),
      icon: running
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 16),
      label: Text(running ? 'Synchronising' : 'Refresh'),
    );
  }
}

/// What the last refresh means for figures that are on screen.
class _SyncNotice extends StatelessWidget {
  const _SyncNotice({required this.sync, required this.preview});

  final OwnerSettlementSyncStatus sync;
  final OwnerSettlementPreview? preview;

  @override
  Widget build(BuildContext context) {
    // Only relevant above a statement that is actually shown. Without one, the body says
    // what is missing and why.
    if (preview is! OwnerSettlementPreviewReady) return const SizedBox.shrink();

    return switch (sync.phase) {
      OwnerSettlementSyncPhase.failed when sync.localFailure => const _Notice(
        key: Key('owner-settlement-local-failure'),
        icon: Icons.error_outline,
        text:
            'The refresh could not run on this device, so nothing was asked of the '
            'server. These figures are the complete history this device last '
            'synchronised, dated below. Refresh to try again.',
      ),
      OwnerSettlementSyncPhase.failed => const _Notice(
        key: Key('owner-settlement-offline'),
        icon: Icons.cloud_off_outlined,
        text:
            'The server could not be reached. These figures are the complete history '
            'this device last synchronised, dated below.',
      ),
      OwnerSettlementSyncPhase.synchronising => const _Notice(
        key: Key('owner-settlement-refreshing'),
        icon: Icons.sync,
        text: 'Refreshing. The figures below are as last synchronised.',
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

// ── The statement ────────────────────────────────────────────────────────────

class _Statement extends ConsumerWidget {
  const _Statement({required this.ready, required this.wide});

  final OwnerSettlementPreviewReady ready;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ready.statement;
    final graph = ref.watch(masterGraphProvider).value;
    final monthName = _monthLabel(
      SettlementMonth(s.periodStart.year, s.periodStart.month),
    );

    final owners = [
      for (final line in s.lines)
        _OwnerAccount(
          line: line,
          name: ready.ownerNames[line.ownerId] ?? 'Owner',
        ),
    ];

    return Column(
      key: const Key('owner-settlement-statement'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Evidence(ready: ready),
        const SizedBox(height: AppSpacing.lg),

        // ── What the business earned ─────────────────────────────────────────
        _Panel(
          key: const Key('owner-settlement-operating-profit'),
          children: [
            Text(
              'OPERATING PROFIT · $monthName',
              style: AppTypography.overline,
            ),
            const SizedBox(height: AppSpacing.sm),
            _Row(
              label: 'Consolidated, both properties',
              amount: s.operatingProfit,
              keyName: 'owner-settlement-op-consolidated',
              strong: true,
              bySign: true,
            ),
            for (final entry in s.operatingProfitByBusinessUnit.entries)
              _Row(
                label: graph?.businessUnit(entry.key)?.name ?? 'Property',
                amount: entry.value,
                keyName: 'owner-settlement-op-${entry.key}',
                muted: true,
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Per property for information only. Entitlement is calculated on the '
              'consolidated figure, from ${_dateLabel(ready.ownershipStartDate)}, '
              'the date 50:50 ownership and settlement begin.',
              style: AppTypography.caption,
            ),
            if (!s.undistributedRemainder.isZero) ...[
              const SizedBox(height: AppSpacing.sm),
              _Row(
                label:
                    'Undivided remainder — belongs to neither owner until later '
                    'profit makes it divisible',
                amount: s.undistributedRemainder,
                keyName: 'owner-settlement-remainder',
                muted: true,
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── How it is settled between the owners ─────────────────────────────
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < owners.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.lg),
                Expanded(child: owners[i]),
              ],
            ],
          )
        else
          for (final owner in owners) ...[
            owner,
            const SizedBox(height: AppSpacing.lg),
          ],

        const SizedBox(height: AppSpacing.md),
        Text(
          'A positive position means the business owes the owner. A negative position '
          'means the amount is recoverable from the owner. A position is not cash '
          'available in a bank account.',
          key: const Key('owner-settlement-sign-convention'),
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

/// One owner's current account for the month. Every figure is a field of the OA-2 line.
class _OwnerAccount extends StatelessWidget {
  const _OwnerAccount({required this.line, required this.name});

  final OwnerSettlementLine line;
  final String name;

  @override
  Widget build(BuildContext context) {
    final id = line.ownerId;
    return _Panel(
      key: Key('owner-settlement-owner-$id'),
      children: [
        Text(name, style: AppTypography.subheading),
        const SizedBox(height: AppSpacing.sm),
        _Row(
          label: 'Opening position',
          amount: line.openingPosition,
          keyName: 'owner-settlement-opening-$id',
        ),
        _Row(
          label: 'Profit entitlement for the month',
          amount: line.profitEntitlement,
          keyName: 'owner-settlement-entitlement-$id',
        ),
        _Row(
          label: 'Less withdrawals',
          amount: line.withdrawals,
          keyName: 'owner-settlement-withdrawals-$id',
        ),
        _Row(
          label: 'Less family and non-chargeable consumption',
          amount: line.ncConsumption,
          keyName: 'owner-settlement-nc-$id',
        ),
        _Row(
          label: 'Less settlement paid',
          amount: line.settlementPaid,
          keyName: 'owner-settlement-paid-$id',
        ),
        _Row(
          label: 'Add adjustments credited',
          amount: line.adjustmentCredits,
          keyName: 'owner-settlement-adj-credit-$id',
        ),
        _Row(
          label: 'Less adjustments debited',
          amount: line.adjustmentDebits,
          keyName: 'owner-settlement-adj-debit-$id',
        ),
        const Divider(height: AppSpacing.lg, color: AppColors.hairline),
        _Row(
          label: 'Closing position',
          amount: line.closingPosition,
          keyName: 'owner-settlement-closing-$id',
          strong: true,
          bySign: true,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            _closingMeaning(line.closingPosition),
            key: Key('owner-settlement-closing-label-$id'),
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// The words that accompany the sign — a position is never told apart by colour alone
/// (spec section 20). A reading of the result's sign, not a calculation.
String _closingMeaning(Money closing) => closing.isNegative
    ? 'Recoverable from owner'
    : closing.isZero
    ? 'Nil — nothing due either way'
    : 'Due to owner';

/// Each dataset's own synchronisation evidence, and no combined time (D-188).
class _Evidence extends StatelessWidget {
  const _Evidence({required this.ready});

  final OwnerSettlementPreviewReady ready;

  @override
  Widget build(BuildContext context) {
    final freshness = ready.reportingFreshness;
    return _Panel(
      key: const Key('owner-settlement-evidence'),
      muted: true,
      children: [
        Text(
          'Owner history · synchronised as of '
          '${_instantLabel(ready.ownerHistory.serverConfirmedAt)}',
          key: const Key('owner-settlement-owner-evidence'),
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          freshness == null
              ? 'Profit & loss · complete, but its figures do not come from one '
                    'synchronisation, so no single time is stated'
              : 'Profit & loss · synchronised as of '
                    '${_instantLabel(freshness.synchronisedAt)}'
                    '${freshness.state == ReportingFreshnessState.serverHasNewer ? ' · the server has newer changes' : ''}',
          key: const Key('owner-settlement-reporting-evidence'),
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Two separate synchronisations. No single combined time is claimed.',
          style: AppTypography.caption.copyWith(color: AppColors.inkFaint),
        ),
      ],
    );
  }
}

// ── Building blocks ──────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({required this.children, this.muted = false, super.key});

  final List<Widget> children;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: muted ? AppColors.surfaceMuted : AppColors.surface,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.amount,
    required this.keyName,
    this.strong = false,
    this.muted = false,
    this.bySign = false,
  });

  final String label;
  final Money amount;
  final String keyName;
  final bool strong;
  final bool muted;
  final bool bySign;

  @override
  Widget build(BuildContext context) {
    final base = strong ? AppTypography.moneyStrong : AppTypography.money;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: (strong ? AppTypography.body : AppTypography.bodyMuted)
                  .copyWith(
                    fontWeight: strong ? FontWeight.w600 : null,
                    color: muted ? AppColors.inkMuted : null,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          MoneyText(
            amount,
            key: Key(keyName),
            style: base.copyWith(color: muted ? AppColors.inkMuted : null),
            emphasis: bySign ? MoneyEmphasis.bySign : MoneyEmphasis.neutral,
            semanticPrefix: label,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.caution),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTypography.caption)),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Column(
      children: [
        Icon(icon, size: 28, color: AppColors.inkFaint),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: AppTypography.subheading,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            message,
            style: AppTypography.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ],
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    key: Key('owner-settlement-loading'),
    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Center(
      child: SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

// ── Display formatting ───────────────────────────────────────────────────────

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthLabel(SettlementMonth m) => '${_months[m.month - 1]} ${m.year}';

String _dateLabel(BusinessDate d) =>
    '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}';

/// A server-confirmed instant, shown in the properties' own time (both are
/// `Asia/Kolkata`). Display only: nothing is derived from it.
String _instantLabel(DateTime instant) {
  final local = tz.TZDateTime.from(instant, tz.getLocation('Asia/Kolkata'));
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1].substring(0, 3)} '
      '${local.year}, $hh:$mm IST';
}
