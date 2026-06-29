# SpatialVerify Census

Firebase-backed field census app for HLB mapping, layout georeferencing, and house listing.

## Architecture

```
┌─────────────────────┐     ┌──────────────────────────┐
│  Flutter App        │────▶│  Firebase                │
│  (offline-first)    │     │  Auth + Firestore +      │
│  Drift + on-device  │◀────│  Storage                 │
│  map / georef       │     └──────────────────────────┘
└─────────────────────┘
```

All mission data lives on the device first, then syncs to Firebase when signed in.

## Quick Start

### Prerequisites

- Flutter 3.24+ stable
- Firebase project `spatialverify-census` (see `mobile/lib/firebase_options.dart`)

### Mobile

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

On Windows with a USB phone:

```powershell
cd mobile
.\run-debug.ps1
```

### Firebase rules deploy

Pushes Firestore and Storage rules (requires `FIREBASE_TOKEN` secret in GitHub):

```bash
firebase deploy --only firestore,storage --project spatialverify-census
```

## OTA updates (no Play Store)

Each push to `main` runs tests, **auto-increments the `+build` number** in `mobile/pubspec.yaml`, builds a release APK, publishes to Firebase, and commits the bumped version back (`[skip ci]`).

### One-time: GitHub `FIREBASE_TOKEN` secret

This cannot be created from CI — run once on your machine (browser login required):

```powershell
cd d:\census
.\scripts\setup_github_firebase_token.ps1
```

Or on macOS/Linux:

```bash
bash scripts/setup_github_firebase_token.sh
```

That runs `firebase login:ci` and stores the token in `yes-weigh/spatialverify-census` as `FIREBASE_TOKEN`.

Verify:

```bash
gh secret list -R yes-weigh/spatialverify-census
```

### Version bumps

- Edit the **name** manually when you want a semver change: `version: 1.1.0+12`
- CI **increments the build** (`+N`) on every successful `main` push automatically
- To change only the marketing version, update `1.0.0` in pubspec; the next CI run will bump `+N`

Manual publish from a local release build:

```bash
export FIREBASE_TOKEN="$(firebase login:ci)"
bash scripts/publish_android_release.sh mobile/build/app/outputs/flutter-apk/app-release.apk
```

Deploy updated Firebase rules (required once):

```bash
firebase deploy --only firestore,storage --project spatialverify-census
```

**Signing:** OTA installs only work when the new APK is signed with the **same key** as the installed app. Configure a release keystore for production field devices.

## License

Proprietary — All rights reserved.
