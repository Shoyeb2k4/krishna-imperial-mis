/// Transactions, on the finance workstation: Expenses and Sales, side by side.
///
/// Spec §19 puts both under one destination — *Transactions → Expenses · Sales · Other
/// Income* — and this is that destination. A separate top-level entry for Sales would
/// have been easier and would have split a finance user's day across two places that
/// answer the same question about one property.
///
/// The chosen tab is held here rather than in a route, so switching between them does not
/// cost the ledger its filters, its page or its selection. That is the behaviour a dense
/// table needs: a finance user comparing an expense against the sale it relates to should
/// not have to rebuild a filter each time they look across.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_ledger_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_ledger_page.dart';

enum TransactionsTab { expenses, sales }

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  TransactionsTab _tab = TransactionsTab.expenses;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<TransactionsTab>(
            key: const Key('transactions-tabs'),
            segments: const [
              ButtonSegment(
                value: TransactionsTab.expenses,
                label: Text('Expenses'),
                icon: Icon(Icons.shopping_bag_outlined, size: 16),
              ),
              ButtonSegment(
                value: TransactionsTab.sales,
                label: Text('Sales'),
                icon: Icon(Icons.point_of_sale_outlined, size: 16),
              ),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _tab = selection.first),
          ),
        ),
      ),
      const Divider(height: 1, color: AppColors.hairline),
      Expanded(
        // `IndexedStack` rather than a conditional child: both ledgers keep their filters,
        // their page and their selected row while the other is showing. Rebuilding a
        // dense table from scratch on every tab change is how a finance user loses a
        // filter they spent a minute assembling.
        child: IndexedStack(
          index: _tab.index,
          children: [
            ExpenseLedgerPage(shellKind: widget.shellKind),
            RevenueLedgerPage(shellKind: widget.shellKind),
          ],
        ),
      ),
    ],
  );
}
