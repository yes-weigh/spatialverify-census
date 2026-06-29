import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_release_info.dart';
import 'app_update_install_event.dart';

/// Checks Firestore for a newer Android build and installs from Firebase Storage.
class AppUpdateService {
  AppUpdateService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  static const releaseDocPath = 'system/android_release';

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  Future<PackageInfo> installedPackageInfo() => PackageInfo.fromPlatform();

  Future<AppReleaseInfo?> fetchLatestRelease() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    final snap = await _firestore.doc(releaseDocPath).get();
    if (!snap.exists || snap.data() == null) return null;

    final info = AppReleaseInfo.fromFirestore(snap.data()!);
    if (info.buildNumber <= 0 || info.apkStoragePath.isEmpty) return null;
    return info;
  }

  Future<AppReleaseInfo?> checkForUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    final installed = await installedPackageInfo();
    final latest = await fetchLatestRelease();
    if (latest == null) return null;

    final installedBuild = int.tryParse(installed.buildNumber) ?? 0;
    if (!latest.isNewerThan(installedBuild)) return null;
    return latest;
  }

  Stream<AppReleaseInfo?> watchForUpdate() async* {
    if (kIsWeb || !Platform.isAndroid) return;

    final installed = await installedPackageInfo();
    final installedBuild = int.tryParse(installed.buildNumber) ?? 0;

    await for (final snap in _firestore.doc(releaseDocPath).snapshots()) {
      if (!snap.exists || snap.data() == null) {
        yield null;
        continue;
      }
      final latest = AppReleaseInfo.fromFirestore(snap.data()!);
      if (latest.buildNumber > installedBuild && latest.apkStoragePath.isNotEmpty) {
        yield latest;
      } else {
        yield null;
      }
    }
  }

  /// Downloads the APK from Storage and opens the Android package installer.
  Stream<AppUpdateInstallEvent> installRelease(AppReleaseInfo release) async* {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('In-app updates are Android-only');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/spatialverify-${release.buildNumber}.apk');
    if (file.existsSync()) {
      await file.delete();
    }

    final ref = _storage.ref(release.apkStoragePath);
    final task = ref.writeToFile(file);

    await for (final snapshot in task.snapshotEvents) {
      final total = snapshot.totalBytes;
      if (total > 0) {
        yield AppUpdateInstallEvent(
          phase: AppUpdatePhase.downloading,
          progress: snapshot.bytesTransferred / total,
        );
      }
    }

    await task;

    if (!file.existsSync() || await file.length() < 1024) {
      yield const AppUpdateInstallEvent(
        phase: AppUpdatePhase.error,
        message: 'Downloaded APK is missing or too small.',
      );
      return;
    }

    yield const AppUpdateInstallEvent(phase: AppUpdatePhase.installing);

    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type == ResultType.done) {
      yield const AppUpdateInstallEvent(phase: AppUpdatePhase.done);
      return;
    }

    yield AppUpdateInstallEvent(
      phase: AppUpdatePhase.error,
      message: result.message ?? 'Could not open the Android installer.',
    );
  }
}
