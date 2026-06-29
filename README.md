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

## License

Proprietary — All rights reserved.
