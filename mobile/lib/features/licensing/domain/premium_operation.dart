/// Premium operations that consume Mission Credits.
/// Isolated from mission/evidence architecture.
enum PremiumOperation {
  importHlo,
  generateBoundary,
  generateMission,
  regenerateMissionIntel,
  runCv,
  downloadOffline,
}

extension PremiumOperationLabels on PremiumOperation {
  String get label {
    switch (this) {
      case PremiumOperation.importHlo:
        return 'Import HLO PDF';
      case PremiumOperation.generateBoundary:
        return 'Boundary Detection';
      case PremiumOperation.generateMission:
        return 'Generate Mission';
      case PremiumOperation.regenerateMissionIntel:
        return 'Re-generate Mission Intelligence';
      case PremiumOperation.runCv:
        return 'Computer Vision Analysis';
      case PremiumOperation.downloadOffline:
        return 'Download Offline Package';
    }
  }
}
