/// Structurally impossible relationships must not be constructible.
///
/// The canonical case from the brief: a Section belonging to Hotel Krishna Imperial must
/// never be usable under a Crystal Canopy Department.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/masters/master_reference.dart';

class FakeHierarchy implements MasterHierarchyView {
  FakeHierarchy(this.nodes);

  final Map<String, MasterNode> nodes;

  @override
  MasterNode? businessUnit(String id) => nodes[id];
  @override
  MasterNode? department(String id) => nodes[id];
  @override
  MasterNode? section(String id) => nodes[id];
  @override
  MasterNode? expenseCategory(String id) => nodes[id];
}

/// Two properties, each with its own department, section and category.
FakeHierarchy buildGraph({
  DateTime? archiveCategory,
  DateTime? archiveSection,
}) => FakeHierarchy({
  'ccr': const MasterNode(
    id: 'ccr',
    code: 'CCR',
    name: 'Crystal Canopy Rooftop',
  ),
  'hki': const MasterNode(
    id: 'hki',
    code: 'HKI',
    name: 'Hotel Krishna Imperial',
  ),
  'ccr-fb': const MasterNode(
    id: 'ccr-fb',
    code: 'FB',
    name: 'F&B / Kitchen',
    parentId: 'ccr',
  ),
  'hki-hk': const MasterNode(
    id: 'hki-hk',
    code: 'HK',
    name: 'Housekeeping',
    parentId: 'hki',
  ),
  'ccr-food': MasterNode(
    id: 'ccr-food',
    code: 'FOOD_PROD',
    name: 'Food Production',
    parentId: 'ccr-fb',
    archivedAt: archiveSection,
  ),
  'hki-maint': const MasterNode(
    id: 'hki-maint',
    code: 'MAINT',
    name: 'Maintenance',
    parentId: 'hki-hk',
  ),
  'ccr-kirana': MasterNode(
    id: 'ccr-kirana',
    code: 'KIRANA',
    name: 'Kirana & Pulses',
    parentId: 'ccr-food',
    archivedAt: archiveCategory,
  ),
  'hki-diesel': const MasterNode(
    id: 'hki-diesel',
    code: 'DIESEL',
    name: 'Diesel',
    parentId: 'hki-maint',
  ),
});

const validCcrPath = HierarchyPath(
  businessUnitId: 'ccr',
  departmentId: 'ccr-fb',
  sectionId: 'ccr-food',
  categoryId: 'ccr-kirana',
);

void main() {
  group('a well-formed path is accepted', () {
    test('Crystal Canopy → F&B → Food Production → Kirana & Pulses', () {
      final result = HierarchyValidator.validate(
        validCcrPath,
        buildGraph(),
        forNewEntry: true,
      );
      expect(result.isValid, isTrue);
      expect(result.violations, isEmpty);
    });

    test('Hotel Krishna → Housekeeping → Maintenance → Diesel', () {
      final result = HierarchyValidator.validate(
        const HierarchyPath(
          businessUnitId: 'hki',
          departmentId: 'hki-hk',
          sectionId: 'hki-maint',
          categoryId: 'hki-diesel',
        ),
        buildGraph(),
        forNewEntry: true,
      );
      expect(result.isValid, isTrue);
    });
  });

  group('cross-property mixing is rejected', () {
    test(
      "the brief's case: a Hotel Krishna section under a Crystal Canopy department",
      () {
        final result = HierarchyValidator.validate(
          const HierarchyPath(
            businessUnitId: 'ccr',
            departmentId: 'ccr-fb',
            sectionId: 'hki-maint', // belongs to Housekeeping at the hotel
            categoryId: 'hki-diesel',
          ),
          buildGraph(),
          forNewEntry: true,
        );
        expect(result.isValid, isFalse);
        expect(
          result.violations,
          contains(HierarchyViolation.sectionNotInDepartment),
        );
        expect(
          result.message,
          contains('does not belong to the selected department'),
        );
      },
    );

    test('a department from the wrong business unit', () {
      final result = HierarchyValidator.validate(
        const HierarchyPath(
          businessUnitId: 'ccr',
          departmentId: 'hki-hk',
          sectionId: 'hki-maint',
          categoryId: 'hki-diesel',
        ),
        buildGraph(),
        forNewEntry: true,
      );
      expect(
        result.violations,
        contains(HierarchyViolation.departmentNotInBusinessUnit),
      );
    });

    test('a category from the wrong section', () {
      final result = HierarchyValidator.validate(
        const HierarchyPath(
          businessUnitId: 'ccr',
          departmentId: 'ccr-fb',
          sectionId: 'ccr-food',
          categoryId: 'hki-diesel',
        ),
        buildGraph(),
        forNewEntry: true,
      );
      expect(
        result.violations,
        contains(HierarchyViolation.categoryNotInSection),
      );
    });

    test(
      'a fully mismatched path reports every broken link, not just the first',
      () {
        final result = HierarchyValidator.validate(
          const HierarchyPath(
            businessUnitId: 'ccr',
            departmentId: 'hki-hk',
            sectionId: 'ccr-food',
            categoryId: 'hki-diesel',
          ),
          buildGraph(),
          forNewEntry: true,
        );
        expect(result.violations.length, greaterThanOrEqualTo(3));
      },
    );

    test('enforce throws rather than letting a bad path through', () {
      expect(
        () => HierarchyValidator.validate(
          const HierarchyPath(
            businessUnitId: 'ccr',
            departmentId: 'ccr-fb',
            sectionId: 'hki-maint',
            categoryId: 'hki-diesel',
          ),
          buildGraph(),
          forNewEntry: true,
        ).enforce(),
        throwsA(isA<HierarchyIntegrityFailure>()),
      );
    });
  });

  group('unknown ids', () {
    test('are reported individually, without cascading noise', () {
      final result = HierarchyValidator.validate(
        const HierarchyPath(
          businessUnitId: 'ccr',
          departmentId: 'ccr-fb',
          sectionId: 'ccr-food',
          categoryId: 'does-not-exist',
        ),
        buildGraph(),
        forNewEntry: true,
      );
      expect(result.violations, [HierarchyViolation.unknownCategory]);
    });
  });

  group('archived masters', () {
    test('cannot be used for a new entry', () {
      final result = HierarchyValidator.validate(
        validCcrPath,
        buildGraph(archiveCategory: DateTime.utc(2026, 5, 1)),
        forNewEntry: true,
      );
      expect(result.violations, contains(HierarchyViolation.archivedCategory));
      expect(result.message, contains('archived'));
    });

    test('remain valid for existing history', () {
      // Archiving "Kirana & Pulses" must not retroactively invalidate the ₹1,50,181
      // already booked against it.
      final result = HierarchyValidator.validate(
        validCcrPath,
        buildGraph(archiveCategory: DateTime.utc(2026, 5, 1)),
        forNewEntry: false,
      );
      expect(result.isValid, isTrue);
    });

    test('an archived section blocks new entries beneath it', () {
      final result = HierarchyValidator.validate(
        validCcrPath,
        buildGraph(archiveSection: DateTime.utc(2026, 5, 1)),
        forNewEntry: true,
      );
      expect(result.violations, contains(HierarchyViolation.archivedSection));
    });
  });

  group('deriving a path upward', () {
    test('a category resolves its whole chain', () {
      final path = HierarchyValidator.pathForCategory(
        'ccr-kirana',
        buildGraph(),
      );
      expect(path, validCcrPath);
    });

    test('an unknown category yields null rather than a half-built path', () {
      expect(HierarchyValidator.pathForCategory('nope', buildGraph()), isNull);
    });
  });

  group('historical integrity', () {
    test('a rename is visible, and the recorded label is preserved', () {
      const reference = MasterReference(
        id: 'ccr-kirana',
        code: 'KIRANA',
        labelSnapshot: 'Kirana & Pulses',
      );

      // The current name wins on screen, so a corrected spelling propagates.
      expect(
        reference.displayName(currentName: 'Kirana and Pulses'),
        'Kirana and Pulses',
      );
      // But what was actually recorded is never lost.
      expect(reference.labelSnapshot, 'Kirana & Pulses');
      expect(reference.wasRenamedSince('Kirana and Pulses'), isTrue);
      expect(reference.wasRenamedSince('Kirana & Pulses'), isFalse);
    });

    test('with no current name available, the snapshot is shown', () {
      const reference = MasterReference(
        id: 'x',
        code: 'WATER',
        labelSnapshot: 'Water',
      );
      expect(reference.displayName(), 'Water');
    });

    test('the immutable code is what history keys on', () {
      const before = MasterReference(
        id: 'x',
        code: 'WATER',
        labelSnapshot: 'Water',
      );
      const after = MasterReference(
        id: 'x',
        code: 'WATER',
        labelSnapshot: 'Water Charges',
      );
      // Same master, same code, same id — only the label moved.
      expect(before.id, after.id);
      expect(before.code, after.code);
      expect(before, isNot(after));
    });
  });

  group('archive policy', () {
    test('a master with live children may not be archived yet', () {
      final decision = ArchivePolicy.evaluate(
        isArchived: false,
        activeChildCount: 3,
      );
      expect(decision.isAllowed, isFalse);
      expect(decision.message, contains('underneath'));
    });

    test('a leaf master may be archived', () {
      expect(
        ArchivePolicy.evaluate(
          isArchived: false,
          activeChildCount: 0,
        ).isAllowed,
        isTrue,
      );
    });

    test('being referenced by history is not a reason to refuse', () {
      // Archiving is precisely the right action for a master with history — it is why
      // delete does not exist.
      expect(
        ArchivePolicy.evaluate(
          isArchived: false,
          activeChildCount: 0,
        ).isAllowed,
        isTrue,
      );
    });

    test('archiving twice is refused as a no-op, not treated as success', () {
      final decision = ArchivePolicy.evaluate(
        isArchived: true,
        activeChildCount: 0,
      );
      expect(decision.refusal, ArchiveRefusal.alreadyArchived);
    });
  });
}
