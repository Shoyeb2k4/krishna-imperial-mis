/// What production actually resolves for the revenue gateway (Slice 10, D-077).
///
/// `revenueGatewayProvider` defaults to null, which is correct — an offline-only build has
/// no server to re-read from, and the conflict path treats absence as *"cannot check right
/// now"* rather than as an error. A default that is wrong but harmless-looking is exactly
/// what D-077 paid for, so the default is not the risk: **forgetting the override is.**
///
/// So this reads `main()`'s own source and the bootstrap's own result, rather than
/// asserting on a provider some test overrode. Nothing here needs a device, a backend, or
/// a running application, which is the property that makes it a check somebody will keep.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final main_ = File('lib/main.dart').readAsStringSync();
  final bootstrap = File('lib/app/bootstrap.dart').readAsStringSync();

  group('the revenue gateway reaches the application it was built for', () {
    test('main() overrides the provider from the bootstrap result', () {
      expect(
        main_,
        contains(
          'revenueGatewayProvider.overrideWithValue(boot.revenueGateway)',
        ),
        reason:
            'the conflict path reads this provider; a null default that nothing '
            'overrides is D-077 exactly',
      );
    });

    test(
      'the bootstrap carries the gateway it already built for the sync worker',
      () {
        // One gateway, not two clients: the worker that delivers a correction and the
        // path that re-reads the record after a conflict must be talking to the same
        // session, or "what the server says now" is answered by a different server.
        expect(bootstrap, contains('final RevenueGateway? revenueGateway;'));
        expect(bootstrap, contains('gatewayForRevenue = revenueGateway;'));
        expect(bootstrap, contains('revenueGateway: gatewayForRevenue,'));
        expect(
          bootstrap,
          contains('RevenueMutationEndpoint(revenueGateway)'),
          reason: 'the same instance must be the one the transport uses',
        );
      },
    );

    test('the acceptance harness assembles the same application', () {
      // A second composition root is a second thing to forget, and it has now been
      // forgotten twice: once for the attachment worker, which left a bill `staged` for
      // ever while the real build moved it on, and once here, which made a conflict
      // unresolvable in the acceptance while it resolved in the shipped app.
      //
      // So the two lists are compared rather than each being trusted: every provider
      // `main()` overrides must be overridden by the harness too.
      final harness = File(
        'integration_test/device_acceptance_test.dart',
      ).readAsStringSync();

      final overridden = RegExp(
        r'(\w+Provider)\.overrideWith',
      ).allMatches(main_).map((m) => m.group(1)!).toSet();
      final byHarness = RegExp(
        r'(\w+Provider)\.overrideWith',
      ).allMatches(harness).map((m) => m.group(1)!).toSet();

      expect(
        overridden.difference(byHarness),
        isEmpty,
        reason:
            'the acceptance would be driving a different application from the one '
            'main() builds',
      );
    });

    test('no shipped file overrides it with anything else', () {
      // A second override would mean two answers to "which gateway is production's",
      // and the one that lost would be invisible.
      final overrides = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        if (text.contains('revenueGatewayProvider.overrideWith')) {
          overrides.add(file.path);
        }
      }
      expect(overrides, hasLength(1));
      expect(overrides.single, endsWith('main.dart'));
    });
  });
}
