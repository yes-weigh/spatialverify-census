/// Remote Android release metadata from Firestore `system/android_release`.
class AppReleaseInfo {
  const AppReleaseInfo({
    required this.versionName,
    required this.buildNumber,
    required this.apkStoragePath,
    this.releaseNotes = '',
    this.mandatory = false,
    this.publishedAt,
    this.gitSha,
  });

  final String versionName;
  final int buildNumber;
  final String apkStoragePath;
  final String releaseNotes;
  final bool mandatory;
  final DateTime? publishedAt;
  final String? gitSha;

  bool isNewerThan(int installedBuildNumber) => buildNumber > installedBuildNumber;

  factory AppReleaseInfo.fromFirestore(Map<String, dynamic> data) {
    return AppReleaseInfo(
      versionName: data['versionName'] as String? ?? '0.0.0',
      buildNumber: _asInt(data['buildNumber']),
      apkStoragePath: data['apkStoragePath'] as String? ?? '',
      releaseNotes: data['releaseNotes'] as String? ?? '',
      mandatory: data['mandatory'] as bool? ?? false,
      publishedAt: _asDateTime(data['publishedAt']),
      gitSha: data['gitSha'] as String?,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
