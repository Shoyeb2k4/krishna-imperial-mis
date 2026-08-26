/// Indian digit grouping is a hard constraint: ₹12,36,420 — never ₹1,236,420.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

void main() {
  group('the owner-specified examples', () {
    test('123642000 paise with decimals', () {
      expect(
        MoneyFormatter.standard.format(const Money.fromPaise(123642000)),
        '₹12,36,420.00',
      );
    });

    test('123642000 paise as whole rupees', () {
      expect(
        MoneyFormatter.wholeRupees.format(const Money.fromPaise(123642000)),
        '₹12,36,420',
      );
    });

    test('zero', () {
      expect(MoneyFormatter.wholeRupees.format(Money.zero), '₹0');
      expect(MoneyFormatter.standard.format(Money.zero), '₹0.00');
    });
  });

  group('Indian grouping across every boundary', () {
    void expectWhole(int rupees, String formatted) {
      expect(
        MoneyFormatter.wholeRupees.format(Money.fromRupees(rupees)),
        formatted,
        reason: 'grouping wrong for $rupees',
      );
    }

    test('below one thousand is ungrouped', () {
      expectWhole(0, '₹0');
      expectWhole(7, '₹7');
      expectWhole(99, '₹99');
      expectWhole(999, '₹999');
    });

    test('thousands take the first comma after three digits', () {
      expectWhole(1000, '₹1,000');
      expectWhole(76450, '₹76,450');
      expectWhole(99999, '₹99,999');
    });

    test('lakh boundary switches to groups of two', () {
      expectWhole(100000, '₹1,00,000');
      expectWhole(150181, '₹1,50,181');
      expectWhole(1236420, '₹12,36,420');
      expectWhole(9999999, '₹99,99,999');
    });

    test('crore boundary and beyond', () {
      expectWhole(10000000, '₹1,00,00,000');
      expectWhole(326862, '₹3,26,862');
      expectWhole(1000000000, '₹1,00,00,00,000');
    });

    test('never groups the western way', () {
      final formatted = MoneyFormatter.wholeRupees.format(
        const Money.fromRupees(1236420),
      );
      expect(formatted, isNot(contains('1,236,420')));
    });
  });

  group('negatives are always marked, never by colour alone', () {
    test('minus style is the default', () {
      expect(
        MoneyFormatter.standard.format(const Money.fromPaise(-45005)),
        '-₹450.05',
      );
      expect(
        MoneyFormatter.wholeRupees.format(const Money.fromRupees(-1236420)),
        '-₹12,36,420',
      );
    });

    test('accounting style uses parentheses', () {
      expect(
        MoneyFormatter.accounting.format(const Money.fromPaise(-45005)),
        '(₹450.05)',
      );
      expect(
        MoneyFormatter.accounting.format(const Money.fromPaise(45005)),
        '₹450.05',
      );
    });

    test('negative zero is not a thing', () {
      expect(
        MoneyFormatter.standard.format(const Money.fromPaise(-0)),
        '₹0.00',
      );
    });

    test(
      'rounding a negative to whole rupees goes away from zero, like the domain',
      () {
        // -₹0.50 → -₹1, matching Money's halfUpAwayFromZero policy exactly.
        expect(
          MoneyFormatter.wholeRupees.format(const Money.fromPaise(-50)),
          '-₹1',
        );
        expect(
          MoneyFormatter.wholeRupees.format(const Money.fromPaise(50)),
          '₹1',
        );
      },
    );
  });

  group('decimal modes', () {
    test('whenPresent hides an empty paise part and shows a real one', () {
      const formatter = MoneyFormatter(decimals: MoneyDecimals.whenPresent);
      expect(formatter.format(const Money.fromRupees(8450)), '₹8,450');
      expect(formatter.format(const Money.fromPaise(845050)), '₹8,450.50');
    });

    test('always pads a single paisa to two places', () {
      expect(
        MoneyFormatter.standard.format(const Money.fromPaise(105)),
        '₹1.05',
      );
      expect(
        MoneyFormatter.standard.format(const Money.fromPaise(100)),
        '₹1.00',
      );
      expect(MoneyFormatter.standard.format(const Money.fromPaise(5)), '₹0.05');
    });

    test('plain omits the symbol for spreadsheet cells', () {
      expect(
        MoneyFormatter.plain.format(const Money.fromPaise(123642000)),
        '12,36,420.00',
      );
    });
  });

  test('formatting round-trips through the parser', () {
    for (final paise in [0, 5, 105, 845050, 123642000, -45005]) {
      final amount = Money.fromPaise(paise);
      final text = MoneyFormatter.standard.format(amount);
      expect(
        Money.tryParse(text),
        amount,
        reason: 'round trip failed for $text',
      );
    }
  });
}
