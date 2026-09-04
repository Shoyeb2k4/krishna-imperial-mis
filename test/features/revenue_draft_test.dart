/// The rules a user experiences as "why is Save greyed out", tested without a widget.
///
/// The point of keeping [RevenueDraft] pure is that these can be asserted directly rather
/// than inferred from what a screen happened to render — and that the same rules govern
/// both platforms, so Slice 9 inherits them rather than restating them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _restaurant = 'cat-restaurant';
const _nandbhog = 'cat-nandbhog';
const _room = 'cat-room';
const _banquet = 'cat-banquet';

final _june15 = BusinessDate.of(2026, 6, 15);

MasterNode _node(String id, String code, String name, {String? parent}) =>
    MasterNode(id: id, code: code, name: name, parentId: parent);

MasterGraph _graph({bool banquetArchived = false}) => MasterGraph(
  departments: const [],
  sections: const [],
  expenseCategories: const [],
  businessUnits: [
    _node(_ccr, 'CCR', 'Crystal Canopy Rooftop'),
    _node(_hki, 'HKI', 'Hotel Krishna Imperial'),
  ],
  revenueCategories: [
    _node(_restaurant, 'RESTAURANT', 'Restaurant', parent: _ccr),
    _node(_nandbhog, 'NANDBHOG', 'Nandbhog', parent: _ccr),
    _node(_room, 'ROOM', 'Room', parent: _hki),
    MasterNode(
      id: _banquet,
      code: 'BANQUET',
      name: 'Banquet',
      parentId: _hki,
      archivedAt: banquetArchived ? DateTime.utc(2026, 5, 1) : null,
    ),
  ],
);

AuthoritySnapshot _authority({Set<String> units = const {_ccr, _hki}}) =>
    AuthoritySnapshot(
      userId: 'u',
      orgId: 'org-1',
      grants: [
        for (final unit in units)
          CapabilityGrant(Capability.revenueCreate, businessUnitId: unit),
      ],
      resolvedAt: DateTime.utc(2026, 6, 15, 9),
    );

TaxRule _rule({
  required String id,
  required String category,
  int rateBp = 500,
  TaxTreatment treatment = TaxTreatment.inclusive,
  EnteredBasis? basis = EnteredBasis.inclusiveTotal,
  String? bandId,
  String? bandLabel,
  int? bandFloor,
  int? bandCeiling,
  String? subtypeId,
  String? premisesStatus,
}) => TaxRule(
  id: id,
  revenueCategoryId: category,
  rateBasisPoints: rateBp,
  treatment: treatment,
  effectiveFrom: BusinessDate.of(2026, 4, 1),
  inputBasis: basis,
  valueBandId: bandId,
  valueBandLabel: bandLabel,
  valueBandFloor: bandFloor == null ? null : Money.fromPaise(bandFloor),
  valueBandCeiling: bandCeiling == null ? null : Money.fromPaise(bandCeiling),
  supplySubtypeId: subtypeId,
  premisesStatusCode: premisesStatus,
);

/// The verified FY 2026-27 baseline, as the device caches it.
RevenueTaxRuleSet _baseline() => RevenueTaxRuleSet([
  _rule(id: 'rule-restaurant', category: _restaurant),
  _rule(id: 'rule-nandbhog', category: _nandbhog),
  _rule(id: 'rule-room', category: _room),
  _rule(
    id: 'rule-banquet',
    category: _banquet,
    rateBp: 0,
    treatment: TaxTreatment.none,
  ),
]);

RevenueDraft _draft({String? unit = _ccr, String? category}) {
  var draft = RevenueDraft.blank(businessDate: _june15, businessUnitId: unit);
  if (category != null) draft = draft.withCategory(category);
  return draft;
}

void main() {
  group('business unit selection', () {
    test('a one-property user has it preselected by the caller', () {
      final units = RevenueDraft.permittedUnits(
        _graph(),
        _authority(units: {_ccr}),
      );

      expect(units.map((u) => u.code), ['CCR']);
    });

    test('a two-property user is offered both', () {
      final units = RevenueDraft.permittedUnits(_graph(), _authority());
      expect(units.map((u) => u.code), ['CCR', 'HKI']);
    });

    test('an org-wide grant covers every property (D-025)', () {
      final orgWide = AuthoritySnapshot(
        userId: 'u',
        orgId: 'org-1',
        grants: const [CapabilityGrant(Capability.revenueCreate)],
        resolvedAt: DateTime.utc(2026, 6, 15, 9),
      );

      expect(RevenueDraft.permittedUnits(_graph(), orgWide), hasLength(2));
    });

    test('no authority offers nothing at all', () {
      expect(RevenueDraft.permittedUnits(_graph(), null), isEmpty);
    });

    test('a capability for another act does not permit recording sales', () {
      final wrongCapability = AuthoritySnapshot(
        userId: 'u',
        orgId: 'org-1',
        grants: const [
          CapabilityGrant(Capability.expenseCreate, businessUnitId: _ccr),
        ],
        resolvedAt: DateTime.utc(2026, 6, 15, 9),
      );

      expect(RevenueDraft.permittedUnits(_graph(), wrongCapability), isEmpty);
    });
  });

  group('category filtering', () {
    test('only the selected property is offered', () {
      // Order is the master graph's own — sort order, then name — and is deliberately
      // not restated here. What this asserts is the boundary: a property's categories,
      // and no other property's.
      expect(_draft().categoriesFor(_graph()).map((c) => c.code).toSet(), {
        'RESTAURANT',
        'NANDBHOG',
      });
      expect(
        _draft(unit: _hki).categoriesFor(_graph()).map((c) => c.code).toSet(),
        {'ROOM', 'BANQUET'},
      );
    });

    test('an archived category is not offered for a new sale', () {
      // Archiving keeps a category valid for what is already recorded against it and
      // refuses it for anything new (D-035). Offering it here would be offering something
      // the server would then refuse.
      expect(
        _draft(
          unit: _hki,
        ).categoriesFor(_graph(banquetArchived: true)).map((c) => c.code),
        ['ROOM'],
      );
    });

    test('nothing is offered before a property is chosen', () {
      expect(_draft(unit: null).categoriesFor(_graph()), isEmpty);
    });
  });

  group('dependent selections are cleared, never carried', () {
    test('changing property clears the category', () {
      final chosen = _draft(category: _restaurant);
      expect(chosen.revenueCategoryId, _restaurant);

      final moved = chosen.withBusinessUnit(_hki);

      expect(
        moved.revenueCategoryId,
        isNull,
        reason:
            'a Crystal Canopy category under Hotel Krishna is refused by the '
            "server's composite key, and offering it would be offering something "
            'that cannot exist (D-040)',
      );
    });

    test('changing property clears the amounts', () {
      final typed = _draft(
        category: _restaurant,
      ).withAmount('x', Money.fromRupees(1000));
      final moved = typed.withBusinessUnit(_hki);

      expect(moved.components.single.amount, isNull);
    });

    test('changing category clears the band, subtype and amounts', () {
      var draft = _draft(category: _room);
      draft = draft.withComponentsFor(
        RevenueTaxRuleSet([
          _rule(
            id: 'r-lower',
            category: _room,
            bandId: 'band-lower',
            bandLabel: 'Lower',
            bandFloor: 0,
            bandCeiling: 750000,
          ),
        ]),
      );
      expect(draft.components.single.valueBandId, 'band-lower');

      final switched = draft.withCategory(_banquet);

      expect(switched.components.single.valueBandId, isNull);
      expect(switched.components.single.amount, isNull);
    });

    test('re-selecting the same property changes nothing', () {
      final draft = _draft(category: _restaurant);
      expect(identical(draft.withBusinessUnit(_ccr), draft), isTrue);
    });

    test('the notes and entry kind survive a property change', () {
      // They are the operator's own words about the act, not properties of a unit's
      // configuration. Clearing them would be losing something nobody asked to lose.
      final draft = _draft(
        category: _restaurant,
      ).withDetails(notes: 'Diwali evening');

      expect(draft.withBusinessUnit(_hki).notes, 'Diwali evening');
    });
  });

  group('the form shape comes from the configuration (D-081)', () {
    test('the verified baseline gives every category one plain amount', () {
      for (final category in [_restaurant, _nandbhog, _room, _banquet]) {
        final draft = _draft(
          unit: category == _room || category == _banquet ? _hki : _ccr,
          category: category,
        ).withComponentsFor(_baseline());

        expect(draft.components, hasLength(1), reason: category);
        expect(
          draft.components.single.valueBandId,
          isNull,
          reason:
              '$category has no configured band today, so none is asked for',
        );
      }
    });

    test('Room shows no band selector while one generic rule is configured', () {
      // The architecture supports bands; the configuration does not use one. Rendering a
      // tariff-band picker anyway would invent a choice nobody has to make.
      final preview = _draft(
        unit: _hki,
        category: _room,
      ).withComponentsFor(_baseline()).previewWith(_baseline());

      expect(preview.requiresBandChoice, isFalse);
      expect(preview.lines, hasLength(1));
    });

    test('two configured bands give two labelled fields, with no release', () {
      final banded = RevenueTaxRuleSet([
        _rule(
          id: 'r-lower',
          category: _room,
          bandId: 'band-lower',
          bandLabel: 'Up to ₹7,500',
          bandFloor: 0,
          bandCeiling: 750000,
        ),
        _rule(
          id: 'r-upper',
          category: _room,
          rateBp: 1200,
          bandId: 'band-upper',
          bandLabel: 'Above ₹7,500',
          bandFloor: 750000,
        ),
      ]);

      final draft = _draft(
        unit: _hki,
        category: _room,
      ).withComponentsFor(banded);

      expect(draft.components, hasLength(2));
      expect(draft.components.map((c) => c.valueBandLabel), [
        'Up to ₹7,500',
        'Above ₹7,500',
      ]);
    });

    test(
      'bands are ordered by their configured boundary, not by discovery',
      () {
        final banded = RevenueTaxRuleSet([
          _rule(
            id: 'r-upper',
            category: _room,
            bandId: 'b2',
            bandLabel: 'Upper',
            bandFloor: 750000,
          ),
          _rule(
            id: 'r-lower',
            category: _room,
            bandId: 'b1',
            bandLabel: 'Lower',
            bandFloor: 0,
            bandCeiling: 750000,
          ),
        ]);

        expect(
          _draft(
            unit: _hki,
            category: _room,
          ).withComponentsFor(banded).components.map((c) => c.valueBandLabel),
          ['Lower', 'Upper'],
          reason: 'the fields must not reshuffle between builds',
        );
      },
    );

    test('an amount already typed survives a re-shape for the same band', () {
      final banded = RevenueTaxRuleSet([
        _rule(
          id: 'r-lower',
          category: _room,
          bandId: 'b1',
          bandLabel: 'Lower',
          bandFloor: 0,
          bandCeiling: 750000,
        ),
      ]);

      var draft = _draft(unit: _hki, category: _room).withComponentsFor(banded);
      final componentId = draft.components.single.id;
      draft = draft.withAmount(componentId, Money.fromRupees(42000));

      final reshaped = draft.withComponentsFor(banded);

      expect(
        reshaped.components.single.amount,
        Money.fromRupees(42000),
        reason:
            'a configuration refresh must not empty a form somebody is typing in',
      );
    });
  });

  group('the live preview is the record', () {
    test('Restaurant extracts GST from the total rather than adding it', () {
      final draft = _draft(
        category: _restaurant,
      ).withComponentsFor(_baseline());
      final preview = draft
          .withAmount(draft.components.single.id, Money.fromRupees(100000))
          .previewWith(_baseline());

      expect(preview.gross, Money.fromPaise(10000000));
      expect(preview.tax, Money.fromPaise(476190));
      expect(preview.net, Money.fromPaise(9523810));
      expect(
        preview.gross,
        Money.fromRupees(100000),
        reason:
            '₹1,00,000 entered is ₹1,00,000 billed — 5% is not added on top',
      );
      expect(preview.tax.paise + preview.net.paise, preview.gross.paise);
    });

    test('Nandbhog computes identically and stays a separate category', () {
      final draft = _draft(category: _nandbhog).withComponentsFor(_baseline());
      final preview = draft
          .withAmount(draft.components.single.id, Money.fromRupees(12500))
          .previewWith(_baseline());

      expect(preview.tax, Money.fromPaise(59524));
      expect(
        preview.lines.single.rule.id,
        'rule-nandbhog',
        reason: 'the same treatment is not the same rule (D-089)',
      );
    });

    test('Banquet carries no tax, and the entered figure survives whole', () {
      final draft = _draft(
        unit: _hki,
        category: _banquet,
      ).withComponentsFor(_baseline());
      final preview = draft
          .withAmount(draft.components.single.id, Money.fromPaise(4034300))
          .previewWith(_baseline());

      expect(preview.tax, Money.zero);
      expect(preview.gross, preview.net);
      expect(preview.carriesTax, isFalse);
    });

    test(
      'the amount label follows the treatment as well as the basis (D-097)',
      () {
        final taxed = _draft(
          category: _restaurant,
        ).withComponentsFor(_baseline()).previewWith(_baseline());
        final untaxed = _draft(
          unit: _hki,
          category: _banquet,
        ).withComponentsFor(_baseline()).previewWith(_baseline());

        expect(taxed.lines.single.label, 'Customer total (incl. GST)');
        expect(
          untaxed.lines.single.label,
          'Amount billed to the customer',
          reason:
              'labelling an untaxed figure as GST-inclusive tells an operator '
              'something false about the money',
        );
        expect(untaxed.lines.single.label, isNot(contains('GST')));
      },
    );

    test('two bands sum to exact paise', () {
      final banded = RevenueTaxRuleSet([
        _rule(
          id: 'r-lower',
          category: _room,
          bandId: 'b1',
          bandLabel: 'Lower',
          bandFloor: 0,
          bandCeiling: 750000,
        ),
        _rule(
          id: 'r-upper',
          category: _room,
          rateBp: 1200,
          bandId: 'b2',
          bandLabel: 'Upper',
          bandFloor: 750000,
        ),
      ]);

      var draft = _draft(unit: _hki, category: _room).withComponentsFor(banded);
      draft = draft
          .withAmount(draft.components[0].id, Money.fromPaise(4200000))
          .withAmount(draft.components[1].id, Money.fromPaise(2300000));

      final preview = draft.previewWith(banded);

      expect(preview.gross, Money.fromPaise(6500000));
      expect(preview.tax, Money.fromPaise(446429));
      expect(preview.net, Money.fromPaise(6053571));
      expect(preview.tax.paise + preview.net.paise, preview.gross.paise);
    });

    test('nothing is previewed for an empty field', () {
      final preview = _draft(
        category: _restaurant,
      ).withComponentsFor(_baseline()).previewWith(_baseline());

      expect(preview.isResolved, isTrue);
      expect(preview.isComplete, isFalse);
      expect(preview.lines.single.computed, isNull);
    });
  });

  group('Save is offered only when it would succeed', () {
    RevenueDraft complete() {
      final draft = _draft(
        category: _restaurant,
      ).withComponentsFor(_baseline());
      return draft.withAmount(
        draft.components.single.id,
        Money.fromRupees(1000),
      );
    }

    test('a complete draft may be saved', () {
      final draft = complete();
      expect(draft.canSave(draft.previewWith(_baseline())), isTrue);
    });

    test('no category, no save', () {
      final draft = _draft();
      expect(draft.canSave(draft.previewWith(_baseline())), isFalse);
    });

    test('no property, no save', () {
      final draft = _draft(unit: null);
      expect(draft.canSave(draft.previewWith(_baseline())), isFalse);
    });

    test('an empty amount, no save', () {
      final draft = _draft(
        category: _restaurant,
      ).withComponentsFor(_baseline());
      expect(draft.canSave(draft.previewWith(_baseline())), isFalse);
    });

    test('one of two bands left empty, no save', () {
      final banded = RevenueTaxRuleSet([
        _rule(
          id: 'r-lower',
          category: _room,
          bandId: 'b1',
          bandLabel: 'Lower',
          bandFloor: 0,
          bandCeiling: 750000,
        ),
        _rule(
          id: 'r-upper',
          category: _room,
          bandId: 'b2',
          bandLabel: 'Upper',
          bandFloor: 750000,
        ),
      ]);

      var draft = _draft(unit: _hki, category: _room).withComponentsFor(banded);
      draft = draft.withAmount(draft.components[0].id, Money.fromRupees(42000));

      expect(draft.canSave(draft.previewWith(banded)), isFalse);
    });

    test('unavailable configuration blocks the preview and the save', () {
      final draft = complete();
      final preview = draft.previewWith(
        _baseline(),
        unavailable: const RevenueConfigurationUnavailable(
          RevenueConfigurationGap.expired,
        ),
      );

      expect(preview.isResolved, isFalse);
      expect(preview.blockedBy, isA<RevenueConfigurationUnavailable>());
      expect(draft.canSave(preview), isFalse);
      expect(preview.blockedBy!.message, contains('24 hours'));
    });

    test('an unresolvable rule blocks it, and says which condition failed', () {
      final needsBand = RevenueTaxRuleSet([
        _rule(
          id: 'r-lower',
          category: _restaurant,
          bandId: 'b1',
          bandLabel: 'Lower',
          bandFloor: 0,
          bandCeiling: 750000,
        ),
      ]);

      // A draft whose single component names no band, against a rule that requires one.
      final draft = _draft(category: _restaurant);
      final preview = draft.previewWith(needsBand);

      expect(preview.blockedBy, isA<RevenueTaxMissingFact>());
      expect(preview.requiresBandChoice, isTrue);
      expect(draft.canSave(preview), isFalse);
    });

    test('an incomplete rule blocks it rather than assuming a basis', () {
      final noBasis = RevenueTaxRuleSet([
        _rule(id: 'r-legacy', category: _restaurant, basis: null),
      ]);

      final preview = _draft(category: _restaurant).previewWith(noBasis);

      expect(preview.blockedBy, isA<RevenueTaxIncompleteRule>());
    });

    test('an ambiguous configuration blocks it rather than picking one', () {
      final ambiguous = RevenueTaxRuleSet([
        _rule(id: 'a', category: _restaurant),
        _rule(id: 'b', category: _restaurant, rateBp: 1800),
      ]);

      final preview = _draft(category: _restaurant).previewWith(ambiguous);

      expect(preview.blockedBy, isA<RevenueTaxAmbiguous>());
    });

    test('no rule for the date blocks it, and is not a zero rate', () {
      final preview = RevenueDraft.blank(
        businessDate: BusinessDate.of(2026, 3, 31),
        businessUnitId: _ccr,
      ).withCategory(_restaurant).previewWith(_baseline());

      expect(preview.blockedBy, isA<RevenueTaxNoApplicableRule>());
      expect(preview.tax, Money.zero);
      expect(
        preview.isResolved,
        isFalse,
        reason:
            'recording it untaxed would silently overstate Net Sales (D-084)',
      );
    });
  });

  group('the entry draft handed to Slice 7', () {
    test(
      'carries the band identity the operator stated, and no amount-derived one',
      () {
        final banded = RevenueTaxRuleSet([
          _rule(
            id: 'r-lower',
            category: _room,
            bandId: 'band-lower',
            bandLabel: 'Lower',
            bandFloor: 0,
            bandCeiling: 750000,
          ),
        ]);

        var draft = _draft(
          unit: _hki,
          category: _room,
        ).withComponentsFor(banded);
        draft = draft.withAmount(
          draft.components.single.id,
          // Deliberately far above the band's ceiling. The band is what the operator
          // stated; nothing compares the two, and nothing may (D-094).
          Money.fromPaise(99000000),
        );

        final entry = draft.toEntryDraft(capturedAt: DateTime.utc(2026, 6, 15));

        expect(entry.components.single.valueBandId, 'band-lower');
        expect(entry.components.single.enteredAmount.paise, 99000000);
      },
    );

    test('carries the business date and the details', () {
      final draft = _draft(category: _restaurant)
          .withComponentsFor(_baseline())
          .withDetails(notes: 'Evening', sourceReference: 'TILL-4');
      final entry = draft
          .withAmount(draft.components.single.id, Money.fromRupees(500))
          .toEntryDraft(capturedAt: DateTime.utc(2026, 6, 15, 20));

      expect(entry.businessDate, _june15);
      expect(entry.businessUnitId, _ccr);
      expect(entry.revenueCategoryId, _restaurant);
      expect(entry.notes, 'Evening');
      expect(entry.sourceReference, 'TILL-4');
      expect(entry.capturedAt, DateTime.utc(2026, 6, 15, 20));
    });
  });
}
