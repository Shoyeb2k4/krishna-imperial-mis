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
