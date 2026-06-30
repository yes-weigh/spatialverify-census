import '../domain/premium_operation.dart';

/// Configurable credit costs for premium operations.
class OperationCostCatalog {
  OperationCostCatalog._();

  static const Map<PremiumOperation, int> _costs = {
    PremiumOperation.importHlo: 5,
    PremiumOperation.generateBoundary: 5,
    PremiumOperation.generateMission: 5,
    PremiumOperation.regenerateMissionIntel: 5,
    PremiumOperation.runCv: 5,
    PremiumOperation.downloadOffline: 3,
  };

  static int cost(PremiumOperation operation) => _costs[operation] ?? 5;

  static String operationKey(PremiumOperation operation) => operation.name;

  static PremiumOperation? fromKey(String key) {
    for (final op in PremiumOperation.values) {
      if (op.name == key) return op;
    }
    return null;
  }
}
