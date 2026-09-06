/// The expense aggregate's financial invariants.
///
/// These are the highest-value tests in Phase 3. Everything downstream — the local
/// schema, the RPC boundary, the ledger, the P&L — assumes an expense that balances and
/// reports each paisa exactly once. If that assumption is wrong, every figure built on it
/// is wrong in a way no later test would notice.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

final _june15 = BusinessDate.of(2026, 6, 15);

ExpenseAllocation _line({
  required String id,
  required String unit,
  required int rupees,
  BusinessDate? date,
  List<PeriodContribution>? periods,
}) {
  final amount = Money.fromRupees(rupees);
  if (periods != null) {
    return ExpenseAllocation(
      id: id,
      businessUnitId: unit,
      departmentId: '$unit-dept',
      sectionId: '$unit-sec',
      categoryId: '$unit-cat',
      amount: amount,
      periodContributions: periods,
    );
  }
  return ExpenseAllocation.wholePeriod(
    id: id,
    businessUnitId: unit,
    departmentId: '$unit-dept',
    sectionId: '$unit-sec',
    categoryId: '$unit-cat',
    amount: amount,
    businessDate: date ?? _june15,
  );
}

ExpenseDocument _expense({
  required List<ExpenseAllocation> lines,
  Money? total,
  PaymentStatus payment = PaymentStatus.unpaid,
  BusinessDate? paymentDate,
  String? paymentMethodId,
  List<ExpenseAttachment> attachments = const [],
  DateTime? voidedAt,
  String? voidReason,
}) => ExpenseDocument(
  id: 'exp-1',
  orgId: 'org-1',
  businessDate: _june15,
  businessDateSource: BusinessDateSource.derived,
  total: total ?? Money.sum(lines.map((l) => l.amount)),
  allocations: lines,
  paymentStatus: payment,
  paymentDate: paymentDate,
  paymentMethodId: paymentMethodId,
  attachments: attachments,
  createdByUserId: 'user-1',
  capturedAt: DateTime.utc(2026, 6, 15, 9),
  voidedAt: voidedAt,
  voidReason: voidReason,
);

void main() {
  group('reconciliation is a property of the type', () {
    test('a simple expense is one line at the whole amount', () {
      final expense = _expense(
        lines: [_line(id: 'a', unit: 'ccr', rupees: 200)],
      );

      expect(expense.total, Money.fromRupees(200));
      expect(expense.allocations, hasLength(1));
      expect(expense.isCrossUnit, isFalse);
      expect(expense.reportedTotal, expense.total);
    });

    test('the shared electricity bill balances exactly', () {
      // The spec's own example, in paise.
      final expense = _expense(
        total: Money.fromRupees(58000),
        lines: [
          _line(id: 'a', unit: 'ccr', rupees: 25000),
          _line(id: 'b', unit: 'hki', rupees: 33000),
        ],
      );

      expect(expense.total.paise, 5800000);
      expect(expense.reportedTotal, expense.total);
      expect(expense.businessUnitIds, {'ccr', 'hki'});
      expect(expense.isCrossUnit, isTrue);
    });

    test('lines that do not sum to the total cannot be constructed', () {
      expect(
        () => _expense(
          total: Money.fromRupees(58000),
          lines: [
            _line(id: 'a', unit: 'ccr', rupees: 25000),
            _line(id: 'b', unit: 'hki', rupees: 32999),
          ],
        ),
        throwsA(
          isA<ExpenseImbalance>().having(
            (e) => e.difference.paise,
            'out by',
            -100,
          ),
        ),
      );
    });

    test('one paisa out is still out', () {
      expect(
        () => _expense(
          total: Money.fromPaise(100001),
          lines: [_line(id: 'a', unit: 'ccr', rupees: 1000)],
        ),
        throwsA(isA<ExpenseImbalance>()),
      );
    });

    test('an expense always has at least one line', () {
      expect(() => _expense(lines: const []), throwsArgumentError);
    });

    test('a zero or negative line is refused', () {
      for (final paise in [0, -1]) {
        expect(
          () => ExpenseAllocation(
            id: 'a',
            businessUnitId: 'ccr',
            departmentId: 'd',
            sectionId: 's',
            categoryId: 'c',
            amount: Money.fromPaise(paise),
            periodContributions: [
              PeriodContribution(
                id: 'p',
                periodStart: _june15,
                periodEnd: _june15,
                amount: Money.fromPaise(paise),
                isDerived: true,
              ),
            ],
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('period contributions are the only reporting source (D-060)', () {
    test('an ordinary line derives exactly one contribution', () {
      final line = _line(id: 'a', unit: 'ccr', rupees: 12000);

      expect(line.periodContributions, hasLength(1));
      expect(line.periodContributions.single.isDerived, isTrue);
      expect(line.periodContributions.single.periodKey, '2026-06');
      expect(line.periodContributions.single.amount, line.amount);
      expect(line.hasDeliberatePeriodSplit, isFalse);
    });

    test('a deliberate split reports into each month and nowhere else', () {
      // ₹60,000 covering 15 May – 14 June, split evenly.
      final line = _line(
        id: 'a',
        unit: 'ccr',
        rupees: 60000,
        periods: [
          PeriodContribution(
            id: 'p1',
            periodStart: BusinessDate.of(2026, 5, 15),
            periodEnd: BusinessDate.of(2026, 5, 31),
            amount: Money.fromRupees(30000),
            isDerived: false,
          ),
          PeriodContribution(
            id: 'p2',
            periodStart: BusinessDate.of(2026, 6, 1),
            periodEnd: BusinessDate.of(2026, 6, 14),
            amount: Money.fromRupees(30000),
            isDerived: false,
          ),
        ],
      );
      final expense = _expense(lines: [line]);

      final byPeriod = <String, Money>{};
      for (final row in expense.reportingRows) {
        byPeriod[row.periodKey] =
            (byPeriod[row.periodKey] ?? Money.zero) + row.amount;
      }

      expect(byPeriod, {
        '2026-05': Money.fromRupees(30000),
        '2026-06': Money.fromRupees(30000),
      });

      // The whole point: ₹60,000 is not *also* reported against a document-level date.
      expect(expense.reportedTotal, Money.fromRupees(60000));
      expect(expense.reportingRows, hasLength(2));
      expect(line.hasDeliberatePeriodSplit, isTrue);
      expect(expense.periodKeys, {'2026-05', '2026-06'});
    });

    test('contributions that do not sum to the line amount are refused', () {
      expect(
        () => _line(
          id: 'a',
          unit: 'ccr',
          rupees: 60000,
          periods: [
            PeriodContribution(
              id: 'p1',
              periodStart: BusinessDate.of(2026, 5, 15),
              periodEnd: BusinessDate.of(2026, 5, 31),
              amount: Money.fromRupees(30000),
              isDerived: false,
            ),
            PeriodContribution(
              id: 'p2',
              periodStart: BusinessDate.of(2026, 6, 1),
              periodEnd: BusinessDate.of(2026, 6, 14),
              amount: Money.fromRupees(29999),
              isDerived: false,
            ),
          ],
        ),
        throwsA(isA<ExpenseImbalance>()),
      );
    });

    test('an odd split still reconciles to the paisa', () {
      // ₹1,000 across three months by largest remainder: 33334 / 33333 / 33333 paise.
      final shares = Money.fromRupees(1000).allocate([1, 1, 1]);
      expect(Money.sum(shares), Money.fromRupees(1000));

      final line = _line(
        id: 'a',
        unit: 'ccr',
        rupees: 1000,
        periods: [
          for (var i = 0; i < 3; i++)
            PeriodContribution(
              id: 'p$i',
              periodStart: BusinessDate.of(2026, 4 + i, 1),
              periodEnd: BusinessDate.of(2026, 4 + i, 28),
              amount: shares[i],
              isDerived: false,
            ),
        ],
      );

      expect(
        Money.sum(line.periodContributions.map((c) => c.amount)),
        Money.fromRupees(1000),
      );
      expect(_expense(lines: [line]).reportedTotal, Money.fromRupees(1000));
    });

    test(
      'a shared and cross-period bill splits on both dimensions at once',
      () {
        final expense = _expense(
          total: Money.fromRupees(58000),
          lines: [
            _line(
              id: 'ccr',
              unit: 'ccr',
              rupees: 25000,
              periods: [
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
            _line(id: 'hki', unit: 'hki', rupees: 33000),
          ],
        );

        expect(expense.reportingRows, hasLength(3));
        expect(expense.reportedTotal, Money.fromRupees(58000));
        expect(expense.periodKeys, {'2026-05', '2026-06'});

        final ccrMay = expense.reportingRows.where(
          (r) => r.businessUnitId == 'ccr' && r.periodKey == '2026-05',
        );
        expect(ccrMay.single.amount, Money.fromRupees(12500));
      },
    );

    test(
      'an accounting period end decides the period, not the business date',
      () {
        // June salary, paid in July, recorded with a June service period.
        final line = ExpenseAllocation.wholePeriod(
          id: 'a',
          businessUnitId: 'ccr',
          departmentId: 'd',
          sectionId: 's',
          categoryId: 'c',
          amount: Money.fromRupees(80000),
          businessDate: BusinessDate.of(2026, 7, 5),
          accountingPeriodStart: BusinessDate.of(2026, 6, 1),
          accountingPeriodEnd: BusinessDate.of(2026, 6, 30),
        );

        expect(line.periodContributions.single.periodKey, '2026-06');
        expect(
          line.periodContributions.single.pnlDate,
          BusinessDate.of(2026, 6, 30),
        );
      },
    );

    test('a period cannot end before it starts', () {
      expect(
        () => PeriodContribution(
          id: 'p',
          periodStart: BusinessDate.of(2026, 6, 30),
          periodEnd: BusinessDate.of(2026, 6, 1),
          amount: Money.fromRupees(1),
          isDerived: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('a scoped user sees only their own share', () {
    final shared = _expense(
      total: Money.fromRupees(58000),
      lines: [
        _line(id: 'a', unit: 'ccr', rupees: 25000),
        _line(id: 'b', unit: 'hki', rupees: 33000),
      ],
    );

    test('an org-wide user sees the whole document', () {
      final projection = shared.projectedFor(null);

      expect(projection.isComplete, isTrue);
      expect(projection.visibleAllocations, hasLength(2));
      expect(projection.visibleTotal, Money.fromRupees(58000));
      expect(projection.documentTotal, Money.fromRupees(58000));
    });

    test('a Crystal Canopy manager sees their line and their share only', () {
      final projection = shared.projectedFor({'ccr'});

      expect(projection.visibleAllocations, hasLength(1));
      expect(projection.visibleAllocations.single.businessUnitId, 'ccr');
      expect(projection.visibleTotal, Money.fromRupees(25000));
      expect(projection.isPartial, isTrue);
    });

    test('the header total is withheld, because it would give the rest away', () {
      // ₹58,000 total minus a visible ₹25,000 is Hotel Krishna's ₹33,000. Line-level
      // filtering with an unrestricted header total protects nothing.
      final projection = shared.projectedFor({'ccr'});

      expect(projection.documentTotal, isNull);
      expect(projection.visibleTotal, isNot(shared.total));
    });

    test('a user scoped to neither unit sees nothing at all', () {
      final projection = shared.projectedFor({'other'});

      expect(projection.hasAnythingVisible, isFalse);
      expect(projection.visibleTotal, Money.zero);
      expect(projection.documentTotal, isNull);
    });

    test('a single-unit expense is complete for the unit that owns it', () {
      final simple = _expense(
        lines: [_line(id: 'a', unit: 'ccr', rupees: 200)],
      );
      final projection = simple.projectedFor({'ccr'});

      expect(projection.isComplete, isTrue);
      expect(projection.documentTotal, Money.fromRupees(200));
    });
  });

  group('payment, periods and voiding', () {
    test('paid requires a date and a method', () {
      expect(
        () => _expense(
          lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
          payment: PaymentStatus.paid,
        ),
        throwsArgumentError,
      );
      expect(
        () => _expense(
          lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
          payment: PaymentStatus.paid,
          paymentDate: BusinessDate.of(2026, 7, 5),
        ),
        throwsArgumentError,
      );

      final paid = _expense(
        lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
        payment: PaymentStatus.paid,
        paymentDate: BusinessDate.of(2026, 7, 5),
        paymentMethodId: 'bank',
      );
      expect(paid.paymentStatus, PaymentStatus.paid);
    });

    test('an unpaid expense cannot carry a payment date', () {
      expect(
        () => _expense(
          lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
          paymentDate: BusinessDate.of(2026, 7, 5),
        ),
        throwsArgumentError,
      );
    });

    test('a void always states why', () {
      expect(
        () => _expense(
          lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
          voidedAt: DateTime.utc(2026, 6, 20),
        ),
        throwsArgumentError,
      );

      final voided = _expense(
        lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
        voidedAt: DateTime.utc(2026, 6, 20),
        voidReason: 'Entered twice',
      );
      expect(voided.isVoided, isTrue);
    });
  });

  group('attachment limits (project-lead decision)', () {
    ExpenseAttachment attachment(String id, int bytes) => ExpenseAttachment(
      id: id,
      fileName: '$id.jpg',
      contentType: 'image/jpeg',
      byteSize: bytes,
      contentHash: 'hash-$id',
      uploadState: AttachmentUploadState.staged,
    );

    test('five are allowed and six are not', () {
      final five = [for (var i = 0; i < 5; i++) attachment('a$i', 1024)];
      expect(
        _expense(
          lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
          attachments: five,
        ).attachments,
        hasLength(5),
      );

      expect(
        () => _expense(
          lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
          attachments: [...five, attachment('a5', 1024)],
        ),
        throwsArgumentError,
      );
    });

    test('the total payload is capped at 25 MB', () {
      expect(
        () => _expense(
          lines: [_line(id: 'a', unit: 'ccr', rupees: 100)],
          attachments: [
            for (var i = 0; i < 3; i++) attachment('a$i', 9 * 1024 * 1024),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('the policy figures are the approved ones', () {
      expect(AttachmentPolicy.maxPerDocument, 5);
      expect(AttachmentPolicy.imageTargetBytes, 2500 * 1024);
      expect(AttachmentPolicy.maxDocumentBytes, 10 * 1024 * 1024);
      expect(AttachmentPolicy.maxTotalBytesPerDocument, 25 * 1024 * 1024);
      expect(AttachmentPolicy.stagingRetention, const Duration(days: 7));
    });

    test('staging is only reclaimable once the server has verified it', () {
      const staged = ExpenseAttachment(
        id: 'a',
        fileName: 'a.jpg',
        contentType: 'image/jpeg',
        byteSize: 1024,
        contentHash: 'h',
        uploadState: AttachmentUploadState.staged,
      );
      expect(staged.uploadState.isOnServer, isFalse);
      expect(
        staged
            .copyWith(uploadState: AttachmentUploadState.uploaded)
            .uploadState
            .isOnServer,
        isTrue,
      );
      expect(
        staged
            .copyWith(uploadState: AttachmentUploadState.stagingReclaimed)
            .uploadState
            .isOnServer,
        isTrue,
      );
      expect(AttachmentUploadState.retryNeeded.isOnServer, isFalse);
    });
  });

  group('expense numbering', () {
    test('the financial year runs 1 April to 31 March', () {
      expect(FinancialYear.of(BusinessDate.of(2026, 4, 1)).label, '26-27');
      expect(FinancialYear.of(BusinessDate.of(2026, 6, 15)).label, '26-27');
      expect(FinancialYear.of(BusinessDate.of(2027, 3, 31)).label, '26-27');
      expect(FinancialYear.of(BusinessDate.of(2027, 4, 1)).label, '27-28');
      expect(FinancialYear.of(BusinessDate.of(2026, 3, 31)).label, '25-26');
    });

    test('the boundaries belong to the right year', () {
      final fy = FinancialYear(2026);
      expect(fy.startsOn, BusinessDate.of(2026, 4, 1));
      expect(fy.endsOn, BusinessDate.of(2027, 3, 31));
      expect(fy.contains(BusinessDate.of(2026, 3, 31)), isFalse);
      expect(fy.contains(BusinessDate.of(2026, 4, 1)), isTrue);
      expect(fy.contains(BusinessDate.of(2027, 3, 31)), isTrue);
      expect(fy.contains(BusinessDate.of(2027, 4, 1)), isFalse);
    });

    test('renders the approved format', () {
      const number = ExpenseNumber(year: FinancialYear(2026), sequence: 1);
      expect(number.formatted, 'KI-EXP-26-27-000001');
    });

    test(
      'carries no business-unit prefix, because one expense may span both',
      () {
        const number = ExpenseNumber(year: FinancialYear(2026), sequence: 42);
        expect(number.formatted, isNot(contains('CCR')));
        expect(number.formatted, isNot(contains('HKI')));
        expect(number.formatted, startsWith('KI-EXP-'));
      },
    );

    test('round-trips, and is lenient only about case and spacing', () {
      const number = ExpenseNumber(year: FinancialYear(2026), sequence: 123456);
      expect(ExpenseNumber.tryParse(number.formatted), number);
      expect(ExpenseNumber.tryParse('  ki-exp-26-27-123456  '), number);
    });

    test('refuses anything that is not one', () {
      for (final bad in [
        '',
        'KI-EXP-26-27-1',
        'KI-EXP-26-28-000001',
        'KI-EXP-26-26-000001',
        'CCR-EXP-26-27-000001',
        'KI-REV-26-27-000001',
        'KI-EXP-26-27-0000001',
        'KI-EXP-2026-2027-000001',
      ]) {
        expect(
          ExpenseNumber.tryParse(bad),
          isNull,
          reason: '"$bad" must not parse as an expense number',
        );
      }
    });

    test('the sequence resets each year, and ordering follows', () {
      const lastOfYear = ExpenseNumber(
        year: FinancialYear(2026),
        sequence: 999999,
      );
      const firstOfNext = ExpenseNumber(year: FinancialYear(2027), sequence: 1);
      expect(lastOfYear.compareTo(firstOfNext), lessThan(0));
      expect(firstOfNext.formatted, 'KI-EXP-27-28-000001');
    });
  });
}
