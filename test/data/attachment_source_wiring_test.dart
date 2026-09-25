/// The invariant that was missing while the picker did not exist (D-077).
///
/// Every attachment test in this project overrode `attachmentSourceProvider` with a
/// synthetic source — correctly, because the OS picker cannot be driven by the harness.
/// The consequence nobody checked is that *no test ever exercised what production
/// resolves*, so `UnavailableAttachmentSource` survived a whole phase of green
/// attachment acceptance and reached both real clients as
/// "Attaching a bill is not available on this device yet."
///
/// These tests assert the production resolution itself, for both shipped platforms, from
/// the host. They fail if either platform resolves to something that cannot pick a file.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/data/attachments/attachment_source.dart';
import 'package:krishna_mis/data/attachments/platform_attachment_source.dart';

void main() {
  group('the production attachment source, per shipped platform', () {
    test(
      'Android resolves a real picker offering camera, gallery and files',
      () {
        final source = attachmentSourceFor('android');

        expect(source, isA<AndroidAttachmentSource>());
        expect(source, isNot(isA<UnavailableAttachmentSource>()));
        expect(source.available, isNotEmpty);
        expect(
          source.available,
          containsAll(const [
            AttachmentIntake.camera,
            AttachmentIntake.gallery,
            AttachmentIntake.file,
          ]),
        );
      },
    );

    test('Windows resolves a real picker offering the file dialog', () {
      final source = attachmentSourceFor('windows');

      expect(source, isA<WindowsAttachmentSource>());
      expect(source, isNot(isA<UnavailableAttachmentSource>()));
      expect(source.available, {AttachmentIntake.file});
    });

    test('neither shipped platform can resolve to "nothing available"', () {
      // The single assertion that would have caught the defect. The expense form renders
      // "Attaching a bill is not available on this device yet." when `available` is
      // empty, so an empty set on a shipped platform *is* the bug, whatever the type.
      for (final os in const ['android', 'windows']) {
        expect(
          attachmentSourceFor(os).available,
          isNotEmpty,
          reason: '$os would tell the user attachments are unavailable',
        );
      }
    });

    test('what each platform offers matches what its shell claims to offer', () {
      // `intakesFor` shapes the UI; the adapter honours the request. If they disagree, a
      // button exists that the adapter answers with null, which looks to a user exactly
      // like a picker that silently refuses to open.
      expect(
        attachmentSourceFor('android').available,
        intakesFor(AppShellKind.mobile),
      );
      expect(
        attachmentSourceFor('windows').available,
        intakesFor(AppShellKind.desktop),
      );
    });

    test('a platform this product does not ship on is honestly unavailable', () {
      // Not a shipped target (spec §2). Saying "unavailable" here is correct; saying it
      // on Android or Windows is the defect above.
      expect(attachmentSourceFor('linux'), isA<UnavailableAttachmentSource>());
      expect(attachmentSourceFor('linux').available, isEmpty);
    });
  });

  group('the provider resolves the adapter itself, with no override', () {
    // The old arrangement defaulted to "unavailable" and expected a bootstrap to replace
    // it. The replacement was never written and nothing objected (D-077).
    //
    // This used to read the provider on the host and require a real picker, which held
    // only because the suite ran on Windows. On a Linux CI host the production answer is
    // honestly "unavailable", so the claim is now made in two host-independent halves:
    //
    //   1. the provider's body is exactly the production resolution for the running OS,
    //      with nothing in front of it — no default, no bootstrap step, no override;
    //   2. that resolution gives a real picker on both shipped platforms (the group
    //      above).
    //
    // Replacing the body with `UnavailableAttachmentSource()` fails (1) on every host.
    test('its body is the production resolution for the running OS', () {
      final source = File('lib/app/providers.dart').readAsStringSync();
      final declaration = RegExp(
        r'final attachmentSourceProvider = Provider<AttachmentSource>\(\s*'
        r'\(ref\) => attachmentSourceFor\(Platform\.operatingSystem\),\s*\);',
      );
      expect(
        declaration.hasMatch(source),
        isTrue,
        reason:
            'attachmentSourceProvider must resolve attachmentSourceFor(Platform.'
            'operatingSystem) directly — anything else is a step production can forget',
      );
    });

    test('reading it with no override gives what this OS resolves to', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final source = container.read(attachmentSourceProvider);
      final expected = attachmentSourceFor(Platform.operatingSystem);

      expect(source.runtimeType, expected.runtimeType);
      expect(source.available, expected.available);
      if (const {'android', 'windows'}.contains(Platform.operatingSystem)) {
        // On a shipped host the production answer is a real picker, read directly.
        expect(source, isNot(isA<UnavailableAttachmentSource>()));
        expect(source.available, isNotEmpty);
      }
    });
  });
}
