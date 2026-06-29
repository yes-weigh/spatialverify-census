import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_release_info.dart';

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

  /// Downloads the APK via [OtaUpdate] and triggers the Android package installer.
  Stream<OtaEvent> installRelease(AppReleaseInfo release) async* {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('In-app updates are Android-only');
    }

    final ref = _storage.ref(release.apkStoragePath);
    final downloadUrl = await ref.getDownloadURL();

    yield* OtaUpdate().execute(
      downloadUrl,
      destinationFilename: 'spatialverify-${release.buildNumber}.apk',
      androidProviderAuthority: 'com.spatialverify.spatialverify.fileprovider',
    );
  }
}
