/// Sanitised expense fixtures.
///
/// Every figure here is invented for the test that uses it. The ₹58,000 electricity bill
/// and the ₹60,000 cross-period invoice are the spec's own illustrative examples, not real
/// figures from the business (D-027).
///
/// Ids are derived exactly as the seed derives them, so a fixture references the same
/// masters the local seed and the Postgres seed both created — the point of D-040.
library;

import 'dart:io';

import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:uuid/uuid.dart';

final String ccrId = seedId('bu:CCR');
final String hkiId = seedId('bu:HKI');
final String ccrDeptId = seedId('dept:CCR/FB');
final String ccrSectionId = seedId('sec:CCR/FB/FOOD_PROD');
final String ccrCategoryId = seedId('cat:CCR/FB/FOOD_PROD/KIRANA');
final String hkiDeptId = seedId('dept:HKI/HKI_UTIL');
final String hkiSectionId = seedId('sec:HKI/HKI_UTIL/HKI_POWER');
final String hkiCategoryId = seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY');

final BusinessDate june15 = BusinessDate.of(2026, 6, 15);

/// A line with the default single derived period contribution.
ExpenseAllocation line({
  required String unit,
  required int rupees,
  String? id,
  BusinessDate? date,
  String? department,
  String? section,
  String? category,
  String label = 'Kirana & Pulses',
}) => ExpenseAllocation.wholePeriod(
  id: id ?? const Uuid().v4(),
  businessUnitId: unit,
  departmentId: department ?? (unit == hkiId ? hkiDeptId : ccrDeptId),
  sectionId: section ?? (unit == hkiId ? hkiSectionId : ccrSectionId),
  categoryId: category ?? (unit == hkiId ? hkiCategoryId : ccrCategoryId),
  amount: Money.fromRupees(rupees),
  businessDate: date ?? june15,
  categoryLabel: label,
);

ExpenseDocument expenseWith({
  required List<ExpenseAllocation> lines,
  BusinessDate? businessDate,
  BusinessDate? periodStart,
  BusinessDate? periodEnd,
  PaymentStatus payment = PaymentStatus.unpaid,
  BusinessDate? paymentDate,
  String? paymentMethodId,
  String? vendorId,
  List<ExpenseAttachment> attachments = const [],
  String? id,
}) => ExpenseDocument(
  id: id ?? const Uuid().v4(),
  orgId: seedOrgId,
  businessDate: businessDate ?? june15,
  businessDateSource: BusinessDateSource.derived,
  accountingPeriodStart: periodStart,
  accountingPeriodEnd: periodEnd,
  total: Money.sum(lines.map((l) => l.amount)),
  allocations: lines,
  paymentStatus: payment,
  paymentDate: paymentDate,
  paymentMethodId: paymentMethodId,
  vendorId: vendorId,
  attachments: attachments,
  createdByUserId: 'user-1',
  capturedAt: DateTime.utc(2026, 6, 15, 9),
);

/// ₹200, one line, one period. The ordinary case.
ExpenseDocument simpleExpense() =>
    expenseWith(lines: [line(unit: ccrId, rupees: 200)]);

/// The spec's shared electricity bill: ₹58,000 as ₹25,000 + ₹33,000.
ExpenseDocument sharedExpense() => expenseWith(
  lines: [
    line(unit: ccrId, rupees: 25000, id: 'ccr-line'),
    line(unit: hkiId, rupees: 33000, id: 'hki-line', label: 'Electricity'),
  ],
);

/// ₹60,000 covering 15 May – 14 June, split ₹30,000 / ₹30,000.
ExpenseDocument crossPeriodExpense() => expenseWith(
  lines: [
    ExpenseAllocation(
      id: 'split-line',
      businessUnitId: ccrId,
      departmentId: ccrDeptId,
      sectionId: ccrSectionId,
      categoryId: ccrCategoryId,
      categoryLabel: 'Kirana & Pulses',
      amount: Money.fromRupees(60000),
      periodContributions: [
        PeriodContribution(
          id: 'split-may',
          periodStart: BusinessDate.of(2026, 5, 15),
          periodEnd: BusinessDate.of(2026, 5, 31),
          amount: Money.fromRupees(30000),
          isDerived: false,
        ),
        PeriodContribution(
          id: 'split-jun',
          periodStart: BusinessDate.of(2026, 6, 1),
          periodEnd: BusinessDate.of(2026, 6, 14),
          amount: Money.fromRupees(30000),
          isDerived: false,
        ),
      ],
    ),
  ],
);

/// Both dimensions at once: shared between properties, and one share spread over two
/// months. The two mechanisms must compose without either special-casing the other.
ExpenseDocument sharedCrossPeriodExpense() => expenseWith(
  lines: [
    ExpenseAllocation(
      id: 'ccr-split',
      businessUnitId: ccrId,
      departmentId: ccrDeptId,
      sectionId: ccrSectionId,
      categoryId: ccrCategoryId,
      categoryLabel: 'Kirana & Pulses',
      amount: Money.fromRupees(25000),
      periodContributions: [
        PeriodContribution(
          id: 'ccr-may',
          periodStart: BusinessDate.of(2026, 5, 15),
          periodEnd: BusinessDate.of(2026, 5, 31),
          amount: Money.fromRupees(12500),
          isDerived: false,
        ),
        PeriodContribution(
          id: 'ccr-jun',
          periodStart: BusinessDate.of(2026, 6, 1),
          periodEnd: BusinessDate.of(2026, 6, 14),
          amount: Money.fromRupees(12500),
          isDerived: false,
        ),
      ],
    ),
    line(unit: hkiId, rupees: 33000, id: 'hki-line', label: 'Electricity'),
  ],
);

/// An amount that cannot split evenly: ₹1,000.01 across three months.
///
/// Largest-remainder distribution must reconcile it to the paisa — 3333367 / 3333367 /
/// 3333367 does not add up, and the fixture exists to prove the code does not do that.
ExpenseDocument oddSplitExpense() {
  final total = Money.fromPaise(100001);
  final shares = total.allocate([1, 1, 1]);
  return expenseWith(
    lines: [
      ExpenseAllocation(
        id: 'odd-line',
        businessUnitId: ccrId,
        departmentId: ccrDeptId,
        sectionId: ccrSectionId,
        categoryId: ccrCategoryId,
        categoryLabel: 'Kirana & Pulses',
        amount: total,
        periodContributions: [
          for (var i = 0; i < 3; i++)
            PeriodContribution(
              id: 'odd-$i',
              periodStart: BusinessDate.of(2026, 4 + i, 1),
              periodEnd: BusinessDate.of(2026, 4 + i, 28),
              amount: shares[i],
              isDerived: false,
            ),
        ],
      ),
    ],
  );
}

/// June salary, paid on 5 July. Both facts, neither moving the other.
ExpenseDocument juneSalaryPaidInJuly() => expenseWith(
  businessDate: BusinessDate.of(2026, 6, 30),
  periodStart: BusinessDate.of(2026, 6, 1),
  periodEnd: BusinessDate.of(2026, 6, 30),
  payment: PaymentStatus.paid,
  paymentDate: BusinessDate.of(2026, 7, 5),
  paymentMethodId: seedId('pm:BANK'),
  lines: [
    ExpenseAllocation.wholePeriod(
      id: 'salary-line',
      businessUnitId: ccrId,
      departmentId: ccrDeptId,
      sectionId: ccrSectionId,
      categoryId: ccrCategoryId,
      categoryLabel: 'Kitchen payroll',
      amount: Money.fromRupees(80000),
      businessDate: BusinessDate.of(2026, 6, 30),
      accountingPeriodStart: BusinessDate.of(2026, 6, 1),
      accountingPeriodEnd: BusinessDate.of(2026, 6, 30),
    ),
  ],
);

ExpenseAttachment stagedAttachment({
  required String id,
  int bytes = 120 * 1024,
  String contentType = 'image/jpeg',
}) => ExpenseAttachment(
  id: id,
  fileName: '$id.jpg',
  contentType: contentType,
  byteSize: bytes,
  contentHash: 'sha256-$id',
  uploadState: AttachmentUploadState.pending,
  localStagingPath: '/staging/$id.jpg',
);

/// A throwaway file path for a database that has to survive being closed and reopened.
Future<File> createTempDatabaseFile() async {
  final dir = await Directory.systemTemp.createTemp('krishna_expense_test');
  return File('${dir.path}/test.sqlite');
}
