#!/usr/bin/env bash
# Publish a release APK to Firebase Storage and update Firestore OTA metadata.
# Requires: FIREBASE_TOKEN (firebase login:ci), curl, python3
set -euo pipefail

APK_PATH="${1:-}"
if [[ -z "${APK_PATH}" || ! -f "${APK_PATH}" ]]; then
  echo "Usage: publish_android_release.sh <path-to-app-release.apk>" >&2
  exit 1
fi

if [[ -z "${FIREBASE_TOKEN:-}" && -z "${FIREBASE_SERVICE_ACCOUNT:-}" && -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -z "${GOOGLE_GHA_CREDS_PATH:-}" ]]; then
  echo "FIREBASE_SERVICE_ACCOUNT (recommended), google-github-actions/auth, or FIREBASE_TOKEN is required" >&2
  exit 1
fi

# firebase login:ci stores a refresh token. Exchange it for an OAuth access token so
# we can call Google APIs. Firebase Storage REST (firebasestorage.googleapis.com)
# enforces security rules — app-releases/android has allow write: if false — so CI
# uploads via the GCS JSON API, which uses project IAM instead.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v npm >/dev/null 2>&1; then
  FIREBASE_TOOLS_NODE_PATH="$(npm root -g)"
  export NODE_PATH="${FIREBASE_TOOLS_NODE_PATH}${NODE_PATH:+:${NODE_PATH}}"
fi
if ! node -e "require('firebase-tools/lib/auth')" >/dev/null 2>&1; then
  echo "firebase-tools is required. Install with: npm install -g firebase-tools" >&2
  exit 1
fi
ACCESS_TOKEN="$(node "${SCRIPT_DIR}/firebase_access_token.js")"

PROJECT_ID="${FIREBASE_PROJECT_ID:-spatialverify-census}"
STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET:-spatialverify-census.firebasestorage.app}"
PUBSPEC="${PUBSPEC_PATH:-mobile/pubspec.yaml}"

if [[ ! -f "${PUBSPEC}" ]]; then
  echo "pubspec not found at ${PUBSPEC}" >&2
  exit 1
fi

read -r VERSION_NAME BUILD_NUMBER < <(
  python3 - <<'PY' "${PUBSPEC}"
import os, sys
path = sys.argv[1]
if os.environ.get("VERSION_NAME") and os.environ.get("BUILD_NUMBER"):
    print(os.environ["VERSION_NAME"], os.environ["BUILD_NUMBER"])
    raise SystemExit(0)
line = next(l for l in open(path) if l.startswith("version:"))
_, value = line.split(":", 1)
value = value.strip()
if "+" in value:
    name, build = value.split("+", 1)
else:
    name, build = value, "1"
print(name.strip(), build.strip())
PY
)

GIT_SHA="${GITHUB_SHA:-local}"
RELEASE_NOTES="${RELEASE_NOTES:-Automated build from ${GIT_SHA}}"
APK_STORAGE_PATH="app-releases/android/spatialverify-${BUILD_NUMBER}.apk"
ENCODED_PATH="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${APK_STORAGE_PATH}', safe=''))")"

echo "Uploading ${APK_PATH} -> gs://${STORAGE_BUCKET}/${APK_STORAGE_PATH}"
curl -fsS -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary @"${APK_PATH}" \
  "https://storage.googleapis.com/upload/storage/v1/b/${STORAGE_BUCKET}/o?uploadType=media&name=${ENCODED_PATH}"

PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "Updating Firestore system/android_release"
curl -fsS -X PATCH \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/system/android_release?updateMask.fieldPaths=versionName&updateMask.fieldPaths=buildNumber&updateMask.fieldPaths=apkStoragePath&updateMask.fieldPaths=releaseNotes&updateMask.fieldPaths=mandatory&updateMask.fieldPaths=publishedAt&updateMask.fieldPaths=gitSha" \
  -d @- <<EOF
{
  "fields": {
    "versionName": {"stringValue": "${VERSION_NAME}"},
    "buildNumber": {"integerValue": "${BUILD_NUMBER}"},
    "apkStoragePath": {"stringValue": "${APK_STORAGE_PATH}"},
    "releaseNotes": {"stringValue": "${RELEASE_NOTES}"},
    "mandatory": {"booleanValue": false},
    "publishedAt": {"timestampValue": "${PUBLISHED_AT}"},
    "gitSha": {"stringValue": "${GIT_SHA}"}
  }
}
EOF

echo "Published ${VERSION_NAME}+${BUILD_NUMBER} (${APK_STORAGE_PATH})"
