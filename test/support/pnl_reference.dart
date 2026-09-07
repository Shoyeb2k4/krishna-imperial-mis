/// An independent oracle for the P&L, for parity testing only.
///
/// `ARCHITECTURE.md` §6.3 requires the parity suite to have something to assert against
/// before a second engine exists: *"a deliberately naive, obviously-correct pure-Dart fold
/// over the same fixtures"*. This is it, created in Slice 2 so Slice 3 does not have to
/// invent one under time pressure and end up writing the production formula twice.
///
/// **It does not call the production calculator, and must never be changed to.** An oracle
/// that delegates proves that a function equals itself. This one re-expresses the same
/// arithmetic in the simplest form there is: two `for` loops over plain `int`s. It uses no
/// `Money`, no `BusinessDate`, no domain type at all — so a defect in a shared primitive
/// cannot hide by being present on both sides of the comparison.
///
/// **It is not business logic and does not ship.** It lives under `test/`, nothing in
/// `lib/` references it, and a guard in `finance_purity_test.dart` asserts that stays
/// true.
///
/// The one thing it deliberately shares with production is the *input grain*: it folds
/// individual accepted contributions, where `Pnl.compute` receives sums an engine already
/// produced. That difference is the point — between them they check both the summing and
/// the deriving.
library;

/// One accepted revenue component: three integers, in paise.
typedef ReferenceRevenueRow = ({int gross, int tax, int net});

/// What the oracle worked out, in paise.
final class ReferencePnlFigures {
  const ReferencePnlFigures({
    required this.gross,
    required this.gst,
    required this.net,
    required this.expenses,
    required this.operatingProfit,
  });

  final int gross;
  final int gst;
  final int net;
  final int expenses;
  final int operatingProfit;

  @override
  String toString() =>
      'ReferencePnlFigures(gross: $gross, gst: $gst, net: $net, '
      'expenses: $expenses, profit: $operatingProfit)';
}

/// The whole P&L, folded the obvious way.
///
/// Written to be read rather than to be clever: if this disagrees with the production
/// calculator, the production calculator is the one under suspicion.
ReferencePnlFigures referencePnl({
  required List<ReferenceRevenueRow> revenue,
  required List<int> expensePaise,
}) {
  var gross = 0;
  var gst = 0;
  var net = 0;
  for (final row in revenue) {
    gross += row.gross;
    gst += row.tax;
    net += row.net;
  }

  var expenses = 0;
  for (final amount in expensePaise) {
    expenses += amount;
  }

  return ReferencePnlFigures(
    gross: gross,
    gst: gst,
    net: net,
    expenses: expenses,
    operatingProfit: net - expenses,
  );
}
