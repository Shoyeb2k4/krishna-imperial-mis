/// One sale, on a phone.
///
/// A scaffold around [RevenueDetailPanel] and nothing more. The panel already renders the
/// document, its components and the snapshot each one carries, and already hosts the
/// correction controls — so a phone-specific detail implementation would be a second
/// rendering of one financial explanation, and the two would agree until the day somebody
/// changed one of them.
///
/// Desktop presentation may differ from mobile. Financial behaviour may not (§28, §29).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_detail_panel.dart';

class RevenueDetailPage extends ConsumerWidget {
  const RevenueDetailPage({required this.entryId, super.key});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    key: const Key('revenue-detail-page'),
    backgroundColor: AppColors.paper,
    appBar: AppBar(
      title: const Text('Sale'),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    body: RevenueDetailPanel(entryId: entryId),
  );
}
