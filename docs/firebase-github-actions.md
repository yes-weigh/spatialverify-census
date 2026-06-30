# Firebase & GitHub Actions

Firebase project: **spatialverify-census**

## Workflows

| Workflow | File | When it runs | What it does |
|----------|------|--------------|--------------|
| **SpatialVerify CI** | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | Push/PR to `main` or `develop` | `flutter analyze`, tests, debug APK build |
| **Publish OTA release APK** | same file, job `publish-android-release` | Push to `main` (after mobile job passes) | Bump build number, release APK, publish to Firebase, commit `[skip ci]` |
| **Firebase Deploy** | [`.github/workflows/firebase-deploy.yml`](../.github/workflows/firebase-deploy.yml) | Push to `main` when `firebase/**`, `public/**`, or Firebase config changes | Firestore rules, Storage rules, Hosting |

CI auth (in order of preference):

1. **`FIREBASE_SERVICE_ACCOUNT`** — GCP service account JSON (recommended; does not expire like user tokens)
2. **`FIREBASE_TOKEN`** — `firebase login:ci` refresh token (legacy fallback)

## Recommended: `FIREBASE_SERVICE_ACCOUNT`

User tokens from `firebase login:ci` expire or get revoked. Use a service account for stable CI.

### 1. Create service account (GCP Console)

1. [Google Cloud Console](https://console.cloud.google.com/) → project **spatialverify-census**
2. **IAM & Admin** → **Service Accounts** → **Create**
3. Name e.g. `github-actions-ota`
4. Grant roles:
   - **Storage Object Admin** (upload APK to the default bucket)
   - **Cloud Datastore User** (PATCH `system/android_release` in Firestore)
   - **Firebase Hosting Admin** (only if you use Firebase Deploy workflow for hosting)
5. **Keys** → **Add key** → **JSON** → download the file

### 2. Store in GitHub

**Windows:**

```powershell
cd d:\census
.\scripts\setup_github_firebase_service_account.ps1 -KeyPath "C:\path\to\key.json"
```

**macOS / Linux:**

```bash
bash scripts/setup_github_firebase_service_account.sh /path/to/key.json
```

Verify:

```powershell
gh secret list -R yes-weigh/spatialverify-census
```

You should see `FIREBASE_SERVICE_ACCOUNT`. CI uses `google-github-actions/auth` and no longer depends on `FIREBASE_TOKEN` for OTA publish.

Delete the JSON file from your machine after uploading the secret.

## Legacy: `FIREBASE_TOKEN` secret

Only needed if you do not use a service account.

```powershell
cd d:\census
.\scripts\setup_github_firebase_token.ps1
```

If OTA publish fails with “credentials are no longer valid”, prefer migrating to **`FIREBASE_SERVICE_ACCOUNT`** above instead of regenerating the user token again.

The Google account must have permission to upload to Storage and write Firestore `system/android_release`.

## OTA publish flow

Script: [`scripts/publish_android_release.sh`](../scripts/publish_android_release.sh)

1. Obtain Google OAuth access token (service account / ADC, or `FIREBASE_TOKEN` exchange via `firebase-tools`)
2. Upload APK to `app-releases/android/spatialverify-{buildNumber}.apk` (GCS API — bypasses Storage rules that block client writes)
3. PATCH Firestore `system/android_release` with version metadata

Field devices and the [Hosting download page](../public/index.html) read that metadata.

## Manual deploy from Actions

GitHub → **Actions** → **Firebase Deploy** → **Run workflow**

## Local deploy (same as Firebase Deploy workflow)

```powershell
cd d:\census
firebase deploy --only firestore,storage,hosting --project spatialverify-census
```

Rules only:

```powershell
firebase deploy --only firestore,storage --project spatialverify-census
```

## Manual OTA publish (local release APK)

```bash
export FIREBASE_TOKEN="$(firebase login:ci --project spatialverify-census)"
bash scripts/publish_android_release.sh mobile/build/app/outputs/flutter-apk/app-release.apk
```

Requires `npm install -g firebase-tools` and a release-signed APK.
