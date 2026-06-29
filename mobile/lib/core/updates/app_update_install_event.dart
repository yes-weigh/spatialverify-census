enum AppUpdatePhase { downloading, installing, done, error }

class AppUpdateInstallEvent {
  const AppUpdateInstallEvent({
    required this.phase,
    this.progress,
    this.message,
  });

  final AppUpdatePhase phase;
  final double? progress;
  final String? message;
}
