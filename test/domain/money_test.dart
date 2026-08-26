/// Money is the foundation every financial figure in the product rests on.
/// These are the highest-value tests in the project.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

void main() {
  group('construction', () {
    test('stores exact paise', () {
      expect(const Money.fromPaise(123642000).paise, 123642000);
      expect(const Money.fromRupees(1236420).paise, 123642000);
    });

    test('zero is zero', () {
      expect(Money.zero.paise, 0);
      expect(Money.zero.isZero, isTrue);
      expect(Money.zero.isNegative, isFalse);
      expect(Money.zero.isPositive, isFalse);
    });

    test('splits rupees and paise with a consistent sign', () {
      const positive = Money.fromPaise(123456);
      expect(positive.wholeRupees, 1234);
      expect(positive.paiseRemainder, 56);

      const negative = Money.fromPaise(-123456);
      expect(negative.wholeRupees, -1234);
      expect(negative.paiseRemainder, -56);
    });
  });

  group('arithmetic is exact', () {
    test('adds and subtracts without drift', () {
      // The classic float failure: 0.1 + 0.2 != 0.3. In paise it is simply exact.
      const tenPaise = Money.fromPaise(10);
      const twentyPaise = Money.fromPaise(20);
      expect(tenPaise + twentyPaise, const Money.fromPaise(30));
    });

    test('accumulating a third of a rupee a million times stays exact', () {
      var total = Money.zero;
      for (var i = 0; i < 1000000; i++) {
        total += const Money.fromPaise(33);
      }
      expect(total.paise, 33000000);
    });

    test('negation and subtraction below zero are supported', () {
      const amount = Money.fromRupees(500);
      expect((-amount).paise, -50000);
      expect((Money.fromRupees(200) - amount).paise, -30000);
    });

    test('sums an empty collection to zero, never to null', () {
      expect(Money.sum(const []), Money.zero);
      expect(
        Money.sum(const [Money.fromPaise(100), Money.fromPaise(250)]),
        const Money.fromPaise(350),
      );
    });

    test('compares and orders', () {
      const small = Money.fromPaise(100);
      const large = Money.fromPaise(200);
      expect(small < large, isTrue);
      expect(large >= large, isTrue);
      expect(small.compareTo(large), lessThan(0));
      expect([large, small]..sort(), [small, large]);
    });
  });

  group('rounding is explicit and symmetric', () {
    test('exact halves round away from zero', () {
      // 5 paise ÷ 2 = 2.5 → 3
      expect(const Money.fromPaise(5).multiplyByRatio(1, 2).paise, 3);
      expect(const Money.fromPaise(-5).multiplyByRatio(1, 2).paise, -3);
    });

    test('below and above the half behave conventionally', () {
      expect(const Money.fromPaise(4).multiplyByRatio(1, 3).paise, 1); // 1.33
      expect(const Money.fromPaise(5).multiplyByRatio(1, 3).paise, 2); // 1.67
    });

    test(
      'reversing the sign of the input only reverses the sign of the output',
      () {
        for (final paise in [1, 7, 33, 12345, 99999]) {
          final positive = Money.fromPaise(paise).percentage(500).paise;
          final negative = Money.fromPaise(-paise).percentage(500).paise;
          expect(negative, -positive, reason: 'asymmetry at $paise paise');
        }
      },
    );

    test('percentage in basis points keeps rates as integers', () {
      // 5% of ₹1,000.00
      expect(
        const Money.fromRupees(1000).percentage(500),
        const Money.fromRupees(50),
      );
      // 18% of ₹76,450.00
      expect(
        const Money.fromRupees(76450).percentage(1800),
        const Money.fromPaise(1376100),
      );
    });

    test('refuses to divide by zero rather than producing infinity', () {
      expect(
        () => const Money.fromRupees(100).multiplyByRatio(1, 0),
        throwsArgumentError,
      );
    });
  });

  group('allocation always reconciles to the source amount', () {
    test('a simple expense allocates 100% to one line', () {
      final parts = const Money.fromRupees(200).allocate([1]);
      expect(parts, [const Money.fromRupees(200)]);
    });

    test('the shared electricity bill splits exactly', () {
      // ₹58,000 shared 25,000 / 33,000 between the two properties.
      final parts = const Money.fromRupees(58000).allocate([25000, 33000]);
      expect(parts, [
        const Money.fromRupees(25000),
        const Money.fromRupees(33000),
      ]);
      expect(Money.sum(parts), const Money.fromRupees(58000));
    });

    test(
      'an indivisible amount still sums back to the original, to the paisa',
      () {
        // ₹100.00 three ways: 33.34 + 33.33 + 33.33, never 99.99 or 100.01.
        final parts = const Money.fromRupees(100).allocate([1, 1, 1]);
        expect(parts.map((p) => p.paise), [3334, 3333, 3333]);
        expect(Money.sum(parts), const Money.fromRupees(100));
      },
    );

    test('largest remainder is deterministic and ties break by position', () {
      final first = const Money.fromPaise(100).allocate([1, 1, 1]);
      final second = const Money.fromPaise(100).allocate([1, 1, 1]);
      expect(first.map((p) => p.paise), second.map((p) => p.paise));
      expect(first.map((p) => p.paise), [34, 33, 33]);
    });

    test('reconciles for a wide range of awkward amounts and splits', () {
      for (final paise in [1, 2, 7, 99, 101, 5051, 123457, 999999]) {
        for (final weights in [
          [1, 1],
          [1, 1, 1],
          [1, 2, 3],
          [7, 11, 13, 17],
          [1, 0, 1],
        ]) {
          final amount = Money.fromPaise(paise);
          final parts = amount.allocate(weights);
          expect(
            Money.sum(parts),
            amount,
            reason: 'lost paise splitting $paise by $weights',
          );
        }
      }
    });

    test(
      'a negative total splits into negative parts that still reconcile',
      () {
        final parts = const Money.fromPaise(-100).allocate([1, 1, 1]);
        expect(parts.map((p) => p.paise), [-34, -33, -33]);
        expect(Money.sum(parts), const Money.fromPaise(-100));
      },
    );

    test(
      'a zero-weight line receives nothing, never a stray leftover paisa',
      () {
        final parts = const Money.fromPaise(100).allocate([1, 0, 1]);
        expect(parts[1], Money.zero);
        expect(Money.sum(parts), const Money.fromPaise(100));
      },
    );

    test('basis-point allocation demands the shares total exactly 100%', () {
      expect(const Money.fromRupees(1000).allocateByBasisPoints([5000, 5000]), [
        const Money.fromRupees(500),
        const Money.fromRupees(500),
      ]);
      expect(
        () => const Money.fromRupees(1000).allocateByBasisPoints([5000, 4000]),
        throwsArgumentError,
      );
    });

    test('rejects nonsense weightings instead of guessing', () {
      expect(
        () => const Money.fromRupees(10).allocate([]),
        throwsArgumentError,
      );
      expect(
        () => const Money.fromRupees(10).allocate([0, 0]),
        throwsArgumentError,
      );
      expect(
        () => const Money.fromRupees(10).allocate([1, -1]),
        throwsArgumentError,
      );
    });
  });

  group('parsing user input', () {
    test('reads plain and grouped amounts', () {
      expect(Money.tryParse('1200')?.paise, 120000);
      expect(Money.tryParse('12,36,420')?.paise, 123642000);
      expect(Money.tryParse('₹12,36,420.50')?.paise, 123642050);
      expect(Money.tryParse('  8450  ')?.paise, 845000);
    });

    test('pads a single decimal place rather than misreading it', () {
      expect(Money.tryParse('10.5')?.paise, 1050);
      expect(Money.tryParse('10.05')?.paise, 1005);
    });

    test('reads both negative conventions', () {
      expect(Money.tryParse('-450.05')?.paise, -45005);
      expect(Money.tryParse('(450.05)')?.paise, -45005);
    });

    test('refuses anything it cannot read exactly', () {
      // A third decimal place is a real risk of silent truncation, so it is rejected.
      expect(Money.tryParse('10.555'), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('-'), isNull);
    });
  });

  test('equality is by value, so amounts can be compared and used as keys', () {
    expect(const Money.fromPaise(100), const Money.fromPaise(100));
    expect(
      const Money.fromPaise(100).hashCode,
      const Money.fromPaise(100).hashCode,
    );
    expect(const Money.fromPaise(100), isNot(const Money.fromPaise(101)));
  });
}
