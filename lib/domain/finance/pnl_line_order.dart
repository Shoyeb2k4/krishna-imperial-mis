/// The display order of a P&L's category lines, stated once (Phase 7 Slice 3).
///
/// Property first, then category, by id. The P&L screen on both platforms and every
/// export read this one rule, so a document never lists lines in a different order from
/// the screen it was exported from (D-299). It orders and does nothing else: no line is
/// summed, merged, dropped or ranked by amount.
library;

import 'package:krishna_mis/domain/finance/pnl.dart';

abstract final class PnlLineOrder {
  /// Revenue lines ordered by property, then category.
  static List<RevenueCategoryLine> revenue(PnlResult result) =>
      [...result.revenueByCategory]..sort((a, b) {
        final unit = a.businessUnitId.compareTo(b.businessUnitId);
        return unit != 0
            ? unit
            : a.revenueCategoryId.compareTo(b.revenueCategoryId);
      });

  /// Expense lines ordered by property, then category.
  static List<ExpenseHierarchyLine> expenses(PnlResult result) =>
      [...result.expenseByHierarchy]..sort((a, b) {
        final unit = a.businessUnitId.compareTo(b.businessUnitId);
        return unit != 0
            ? unit
            : (a.categoryId ?? '').compareTo(b.categoryId ?? '');
      });
}
