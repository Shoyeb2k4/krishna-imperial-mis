/// The read-only drill-down beneath a P&L: which level is open, what it holds, and the
/// document a row explains (Phase 5 Slice 10).
///
/// ## Every level belongs to one report, for one person
///
/// A location is anchored to the viewer, the scope and the P&L date range of the report it
/// was opened from ([PnlDrillAnchor]). Changing any of the three makes the anchor stale, and
/// a stale anchor is refused rather than re-read under the new report — so a drill-down can
/// never show another person's figures, another property or another period.
///
/// ## Nothing here calculates
///
/// Department and section figures are grouped by `PnlDrilldown`, document rows are summed by
/// the cache, and every level is shown only when `PnlDrilldown` says its children add up
/// exactly to the parent on screen. Authority is `PnlAuthority`, decided again here before
/// anything is read. The fetched document comes from `ReportDocumentReader`, in memory only.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/expenses/expense_document_detail.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:meta/meta.dart';

// ── Anchors and locations ───────────────────────────────────────────────────

/// The report a drill-down belongs to: who, which properties, which P&L dates.
@immutable
final class PnlDrillAnchor {
  const PnlDrillAnchor({
    required this.viewerUserId,
    required this.businessUnitIds,
    required this.range,
  });

  static PnlDrillAnchor of(PnlReportView view) => PnlDrillAnchor(
    viewerUserId: view.viewerUserId,
    businessUnitIds: view.envelope.scope.ordered,
    range: view.range,
  );

  final String viewerUserId;

  /// Sorted, so two anchors of one report are equal however they were built.
  final List<String> businessUnitIds;
  final ReportRange range;

  ReportingScope get scope => ReportingScope(businessUnitIds);
  bool get isConsolidated => businessUnitIds.length > 1;

  @override
  bool operator ==(Object other) =>
      other is PnlDrillAnchor &&
      other.viewerUserId == viewerUserId &&
      other.businessUnitIds.join(',') == businessUnitIds.join(',') &&
      other.range.from == range.from &&
      other.range.to == range.to;

  @override
  int get hashCode => Object.hash(
    viewerUserId,
    businessUnitIds.join(','),
    range.from,
    range.to,
  );
}

/// A level of the drill-down, identified by canonical ids — never by a display name.
@immutable
sealed class PnlDrillLocation {
  const PnlDrillLocation(this.anchor);
  final PnlDrillAnchor anchor;

  /// The property this level is inside, or null for the department list of the whole report.
  String? get businessUnitId;

  /// The level above, or null when the level above is the P&L itself.
  PnlDrillLocation? get parent;
}

/// Revenue → Revenue Category → Documents.
final class PnlRevenueDocumentsAt extends PnlDrillLocation {
  const PnlRevenueDocumentsAt(
    super.anchor, {
    required this.businessUnitId,
    required this.revenueCategoryId,
  });

  @override
  final String businessUnitId;
  final String revenueCategoryId;

  @override
  PnlDrillLocation? get parent => null;

  @override
  bool operator ==(Object other) =>
      other is PnlRevenueDocumentsAt &&
      other.anchor == anchor &&
      other.businessUnitId == businessUnitId &&
      other.revenueCategoryId == revenueCategoryId;

  @override
  int get hashCode => Object.hash(anchor, businessUnitId, revenueCategoryId);
}

/// Expenses → Department.
final class PnlExpenseDepartmentsAt extends PnlDrillLocation {
  const PnlExpenseDepartmentsAt(super.anchor);

  @override
  String? get businessUnitId => null;

  @override
  PnlDrillLocation? get parent => null;

  @override
  bool operator ==(Object other) =>
      other is PnlExpenseDepartmentsAt && other.anchor == anchor;

  @override
  int get hashCode => Object.hash('departments', anchor);
}

/// Expenses → Department → Section.
final class PnlExpenseSectionsAt extends PnlDrillLocation {
  const PnlExpenseSectionsAt(
    super.anchor, {
    required this.businessUnitId,
    required this.departmentId,
  });

  @override
  final String businessUnitId;
  final String departmentId;

  @override
  PnlDrillLocation get parent => PnlExpenseDepartmentsAt(anchor);

  @override
  bool operator ==(Object other) =>
      other is PnlExpenseSectionsAt &&
      other.anchor == anchor &&
      other.businessUnitId == businessUnitId &&
      other.departmentId == departmentId;

  @override
  int get hashCode => Object.hash(anchor, businessUnitId, departmentId);
}

/// Expenses → Department → Section → Category.
final class PnlExpenseCategoriesAt extends PnlDrillLocation {
  const PnlExpenseCategoriesAt(
    super.anchor, {
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
  });

  @override
  final String businessUnitId;
  final String departmentId;
  final String sectionId;

  @override
  PnlDrillLocation get parent => PnlExpenseSectionsAt(
    anchor,
    businessUnitId: businessUnitId,
    departmentId: departmentId,
  );

  @override
  bool operator ==(Object other) =>
      other is PnlExpenseCategoriesAt &&
      other.anchor == anchor &&
      other.businessUnitId == businessUnitId &&
      other.departmentId == departmentId &&
      other.sectionId == sectionId;

  @override
  int get hashCode =>
      Object.hash(anchor, businessUnitId, departmentId, sectionId);
}

/// Expenses → Department → Section → Category → Documents.
final class PnlExpenseDocumentsAt extends PnlDrillLocation {
  const PnlExpenseDocumentsAt(
    super.anchor, {
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
  });

  @override
  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;

  @override
  PnlDrillLocation get parent => PnlExpenseCategoriesAt(
    anchor,
    businessUnitId: businessUnitId,
    departmentId: departmentId,
    sectionId: sectionId,
  );

  @override
  bool operator ==(Object other) =>
      other is PnlExpenseDocumentsAt &&
      other.anchor == anchor &&
      other.businessUnitId == businessUnitId &&
      other.departmentId == departmentId &&
      other.sectionId == sectionId &&
      other.categoryId == categoryId;

  @override
  int get hashCode =>
      Object.hash(anchor, businessUnitId, departmentId, sectionId, categoryId);
}

// ── What a level holds ──────────────────────────────────────────────────────

enum PnlDrillRefusal {
  /// The report this level was opened from is no longer the one on screen.
  reportChanged,

  /// Not available to this person.
  notAuthorised,

  /// The document rows for this range are not on this device.
  notDownloaded,

  /// The children do not add up exactly to the parent, so nothing is shown.
  unreconciled,
}

@immutable
sealed class PnlDrillView {
  const PnlDrillView();
}

final class PnlDrillRefused extends PnlDrillView {
  const PnlDrillRefused(this.reason);
  final PnlDrillRefusal reason;
}

/// Departments, sections or categories, and the parent they add up to exactly.
final class PnlExpenseLevelView extends PnlDrillView {
  const PnlExpenseLevelView({
    required this.location,
    required this.parent,
    required this.children,
  });

  final PnlDrillLocation location;
  final ExpenseTotals parent;
  final List<ExpenseHierarchyLine> children;
}

/// A revenue category's documents, and the category line they add up to exactly.
final class PnlRevenueDocumentsView extends PnlDrillView {
  const PnlRevenueDocumentsView({
    required this.location,
    required this.parent,
    required this.documents,
  });

  final PnlRevenueDocumentsAt location;
  final RevenueCategoryLine parent;
  final List<RevenueDocumentLine> documents;
}

/// An expense bucket's documents, and the bucket line they add up to exactly.
final class PnlExpenseDocumentsView extends PnlDrillView {
  const PnlExpenseDocumentsView({
    required this.location,
    required this.parent,
    required this.documents,
  });

  final PnlExpenseDocumentsAt location;
  final ExpenseHierarchyLine parent;
  final List<ExpenseDocumentLine> documents;
}

/// One level, read for the person signed in now.
final pnlDrillLevelProvider = FutureProvider.autoDispose
    .family<PnlDrillView, PnlDrillLocation>((ref, location) async {
      final principal = ref.watch(sessionProvider).principal;
      final view = await ref.watch(pnlViewProvider.future);
      final anchor = location.anchor;

      if (view is! PnlReportView ||
          view.viewerUserId != principal.userId ||
          PnlDrillAnchor.of(view) != anchor) {
        return const PnlDrillRefused(PnlDrillRefusal.reportChanged);
      }
      if (!_mayRead(principal, anchor, location.businessUnitId)) {
        return const PnlDrillRefused(PnlDrillRefusal.notAuthorised);
      }
      final result = view.envelope.resultOrNull;
      if (result == null) {
        return const PnlDrillRefused(PnlDrillRefusal.reportChanged);
      }
      final leaves = result.expenseByHierarchy;

      PnlDrillView level(
        ExpenseTotals? parent,
        List<ExpenseHierarchyLine> children,
      ) {
        if (parent == null) {
          return const PnlDrillRefused(PnlDrillRefusal.reportChanged);
        }
        if (!PnlDrilldown.expenseChildrenReconcile(
          parent,
          children.map((c) => c.totals),
        )) {
          return const PnlDrillRefused(PnlDrillRefusal.unreconciled);
        }
        return PnlExpenseLevelView(
          location: location,
          parent: parent,
          children: children,
        );
      }

      switch (location) {
        case PnlExpenseDepartmentsAt():
          return level(
            PnlDrilldown.expensesOf(result),
            PnlDrilldown.departments(leaves),
          );

        case PnlExpenseSectionsAt(:final businessUnitId, :final departmentId):
          return level(
            PnlDrilldown.department(
              leaves,
              businessUnitId: businessUnitId,
              departmentId: departmentId,
            )?.totals,
            PnlDrilldown.sections(
              leaves,
              businessUnitId: businessUnitId,
              departmentId: departmentId,
            ),
          );

        case PnlExpenseCategoriesAt(
          :final businessUnitId,
          :final departmentId,
          :final sectionId,
        ):
          return level(
            PnlDrilldown.section(
              leaves,
              businessUnitId: businessUnitId,
              departmentId: departmentId,
              sectionId: sectionId,
            )?.totals,
            PnlDrilldown.categories(
              leaves,
              businessUnitId: businessUnitId,
              departmentId: departmentId,
              sectionId: sectionId,
            ),
          );

        case PnlExpenseDocumentsAt(
          :final businessUnitId,
          :final departmentId,
          :final sectionId,
          :final categoryId,
        ):
          final parent = PnlDrilldown.category(
            leaves,
            businessUnitId: businessUnitId,
            departmentId: departmentId,
            sectionId: sectionId,
            categoryId: categoryId,
          );
          if (parent == null) {
            return const PnlDrillRefused(PnlDrillRefusal.reportChanged);
          }
          final rows = await ref.watch(pnlReportingLockProvider).run(() async {
            final source = await ref.watch(
              reportingDrilldownSourceProvider.future,
            );
            return source.expenseDocuments(
              scope: anchor.scope,
              range: anchor.range,
              businessUnitId: businessUnitId,
              departmentId: departmentId,
              sectionId: sectionId,
              categoryId: categoryId,
            );
          });
          return switch (rows) {
            DrilldownRowsUnavailable(:final reason) => PnlDrillRefused(
              _refusalFor(reason),
            ),
            DrilldownRowsAvailable(:final rows) =>
              PnlDrilldown.expenseChildrenReconcile(
                    parent.totals,
                    rows.map((r) => r.totals),
                  )
                  ? PnlExpenseDocumentsView(
                      location: location,
                      parent: parent,
                      documents: rows,
                    )
                  : const PnlDrillRefused(PnlDrillRefusal.unreconciled),
          };

        case PnlRevenueDocumentsAt(
          :final businessUnitId,
          :final revenueCategoryId,
        ):
          final parent = PnlDrilldown.revenueCategory(
            result.revenueByCategory,
            businessUnitId: businessUnitId,
            revenueCategoryId: revenueCategoryId,
          );
          if (parent == null) {
            return const PnlDrillRefused(PnlDrillRefusal.reportChanged);
          }
          final rows = await ref.watch(pnlReportingLockProvider).run(() async {
            final source = await ref.watch(
              reportingDrilldownSourceProvider.future,
            );
            return source.revenueDocuments(
              scope: anchor.scope,
              range: anchor.range,
              businessUnitId: businessUnitId,
              revenueCategoryId: revenueCategoryId,
            );
          });
          return switch (rows) {
            DrilldownRowsUnavailable(:final reason) => PnlDrillRefused(
              _refusalFor(reason),
            ),
            DrilldownRowsAvailable(:final rows) =>
              PnlDrilldown.revenueChildrenReconcile(
                    parent.totals,
                    rows.map((r) => r.totals),
                  )
                  ? PnlRevenueDocumentsView(
                      location: location,
                      parent: parent,
                      documents: rows,
                    )
                  : const PnlDrillRefused(PnlDrillRefusal.unreconciled),
          };
      }
    });

PnlDrillRefusal _refusalFor(ReportingCoverage reason) =>
    reason == ReportingCoverage.notAuthorised
    ? PnlDrillRefusal.notAuthorised
    : PnlDrillRefusal.notDownloaded;

/// The D2 intersection for the report's scope, decided before anything is read. A level
/// inside a property must be inside the report's scope.
bool _mayRead(Principal principal, PnlDrillAnchor anchor, String? unit) {
  if (anchor.businessUnitIds.isEmpty) return false;
  if (unit != null && !anchor.businessUnitIds.contains(unit)) return false;
  return anchor.isConsolidated
      ? PnlAuthority.mayReadConsolidated(principal)
      : PnlAuthority.mayReadUnit(principal, anchor.businessUnitIds.single);
}

// ── A document, opened from a row ───────────────────────────────────────────

/// A row the current bucket produced, and the bucket it came from. There is no way to name
/// a document by a free-form id: a request carries the row itself, and is honoured only
/// while that exact row is still in the bucket for the person signed in now.
@immutable
sealed class PnlDocumentRequest {
  const PnlDocumentRequest();
  PnlDrillLocation get location;
}

final class PnlRevenueDocumentRequest extends PnlDocumentRequest {
  const PnlRevenueDocumentRequest(this.location, this.line);

  @override
  final PnlRevenueDocumentsAt location;
  final RevenueDocumentLine line;

  @override
  bool operator ==(Object other) =>
      other is PnlRevenueDocumentRequest &&
      other.location == location &&
      other.line == line;

  @override
  int get hashCode => Object.hash(location, line);
}

final class PnlExpenseDocumentRequest extends PnlDocumentRequest {
  const PnlExpenseDocumentRequest(this.location, this.line);

  @override
  final PnlExpenseDocumentsAt location;
  final ExpenseDocumentLine line;

  @override
  bool operator ==(Object other) =>
      other is PnlExpenseDocumentRequest &&
      other.location == location &&
      other.line == line;

  @override
  int get hashCode => Object.hash(location, line);
}

enum PnlDocumentRefusal {
  /// The report, or the row, is no longer the one on screen.
  reportChanged,

  /// The server withheld the document, or the reader may not read this report.
  notAvailable,

  /// No answer: detail is not on this device, and a connection is needed to open it.
  notDownloaded,

  /// The document no longer explains the cached row.
  changed,
}

@immutable
sealed class PnlDocumentView {
  const PnlDocumentView();
}

final class PnlDocumentRefused extends PnlDocumentView {
  const PnlDocumentRefused(this.reason);
  final PnlDocumentRefusal reason;
}

final class PnlRevenueDocumentReady extends PnlDocumentView {
  const PnlRevenueDocumentReady({required this.entry, required this.line});
  final RevenueEntry entry;
  final RevenueDocumentLine line;
}

final class PnlExpenseDocumentReady extends PnlDocumentView {
  const PnlExpenseDocumentReady({required this.detail, required this.line});
  final ExpenseDocumentDetail detail;
  final ExpenseDocumentLine line;
}

/// The document behind a row, fetched on demand and held only as long as a surface shows
/// it. Nothing is written anywhere.
final pnlDocumentDetailProvider = FutureProvider.autoDispose
    .family<PnlDocumentView, PnlDocumentRequest>((ref, request) async {
      final level = await ref.watch(
        pnlDrillLevelProvider(request.location).future,
      );

      switch ((request, level)) {
        case (
          PnlRevenueDocumentRequest(:final line),
          PnlRevenueDocumentsView(:final documents, :final location),
        ):
          if (!documents.contains(line)) {
            return const PnlDocumentRefused(PnlDocumentRefusal.reportChanged);
          }
          final reader = ref.watch(reportDocumentReaderProvider);
          if (reader == null) {
            return const PnlDocumentRefused(PnlDocumentRefusal.notDownloaded);
          }
          return switch (await reader.revenueFor(
            line,
            range: location.anchor.range,
          )) {
            ReportDocumentReady(:final document) => PnlRevenueDocumentReady(
              entry: document,
              line: line,
            ),
            ReportDocumentChanged() => const PnlDocumentRefused(
              PnlDocumentRefusal.changed,
            ),
            ReportDocumentNotAvailable() => const PnlDocumentRefused(
              PnlDocumentRefusal.notAvailable,
            ),
            ReportDocumentNotDownloaded() => const PnlDocumentRefused(
              PnlDocumentRefusal.notDownloaded,
            ),
          };

        case (
          PnlExpenseDocumentRequest(:final line),
          PnlExpenseDocumentsView(:final documents, :final location),
        ):
          if (!documents.contains(line)) {
            return const PnlDocumentRefused(PnlDocumentRefusal.reportChanged);
          }
          final reader = ref.watch(reportDocumentReaderProvider);
          if (reader == null) {
            return const PnlDocumentRefused(PnlDocumentRefusal.notDownloaded);
          }
          return switch (await reader.expenseFor(
            line,
            range: location.anchor.range,
          )) {
            ReportDocumentReady(:final document) => PnlExpenseDocumentReady(
              detail: document,
              line: line,
            ),
            ReportDocumentChanged() => const PnlDocumentRefused(
              PnlDocumentRefusal.changed,
            ),
            ReportDocumentNotAvailable() => const PnlDocumentRefused(
              PnlDocumentRefusal.notAvailable,
            ),
            ReportDocumentNotDownloaded() => const PnlDocumentRefused(
              PnlDocumentRefusal.notDownloaded,
            ),
          };

        case (_, PnlDrillRefused(reason: PnlDrillRefusal.notAuthorised)):
          return const PnlDocumentRefused(PnlDocumentRefusal.notAvailable);

        case _:
          return const PnlDocumentRefused(PnlDocumentRefusal.reportChanged);
      }
    });

// ── Where the Windows surface is ────────────────────────────────────────────

@immutable
final class PnlDrillState {
  const PnlDrillState({required this.location, this.selected});
  final PnlDrillLocation location;
  final PnlDocumentRequest? selected;
}

/// The open level and selected document on the Windows surface. Reset whenever the person
/// or the selected scope or period changes.
final pnlDrillProvider = NotifierProvider<PnlDrillController, PnlDrillState?>(
  PnlDrillController.new,
);

class PnlDrillController extends Notifier<PnlDrillState?> {
  @override
  PnlDrillState? build() {
    ref.watch(sessionProvider.select((s) => s.principal.userId));
    ref.watch(pnlSelectionProvider);
    return null;
  }

  void open(PnlDrillLocation location) =>
      state = PnlDrillState(location: location);

  void select(PnlDocumentRequest request) {
    // Opening a row always asks the server again. A copy still held from the last time this
    // row was open is never shown in its place: offline the answer is "not downloaded", and
    // online it is current (D-239).
    ref.invalidate(pnlDocumentDetailProvider(request));
    state = PnlDrillState(location: request.location, selected: request);
  }

  void closeDocument() {
    final current = state;
    if (current != null) state = PnlDrillState(location: current.location);
  }

  void close() => state = null;
}

/// Vendor names, archived included: a vendor archived today still supplied the period.
final pnlVendorNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final vendors = await ref.watch(vendorListProvider(true).future);
  return {for (final v in vendors) v.id: v.name};
});
