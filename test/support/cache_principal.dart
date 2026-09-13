import 'package:krishna_mis/domain/auth/capability.dart';

/// An explicitly authorised principal for tests whose subject is cache behaviour rather
/// than authorisation. It grants only the read capabilities the two canonical cache
/// adapters compose; production code never imports this fixture.
Principal canonicalCachePrincipal(String userId) => Principal(
  userId: userId,
  grants: const [
    CapabilityGrant(Capability.reportsView),
    CapabilityGrant(Capability.revenueView),
    CapabilityGrant(Capability.expenseViewAll),
    CapabilityGrant(Capability.ownerSettlementView),
    CapabilityGrant(Capability.ownerLedgerView),
  ],
);
