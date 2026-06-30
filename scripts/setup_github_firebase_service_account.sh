#!/usr/bin/env bash
# Store a GCP service account JSON key in GitHub Actions (recommended for CI).
set -euo pipefail

KEY_PATH="${1:-}"
REPO="${2:-yes-weigh/spatialverify-census}"

if [[ -z "${KEY_PATH}" || ! -f "${KEY_PATH}" ]]; then
  echo "Usage: setup_github_firebase_service_account.sh <path-to-key.json> [owner/repo]" >&2
  exit 1
fi

if ! grep -q '"type"[[:space:]]*:[[:space:]]*"service_account"' "${KEY_PATH}"; then
  echo "File does not look like a GCP service account JSON key" >&2
  exit 1
fi

echo "Saving FIREBASE_SERVICE_ACCOUNT to GitHub secret for ${REPO} ..."
gh secret set FIREBASE_SERVICE_ACCOUNT -R "${REPO}" < "${KEY_PATH}"

echo "Done. CI will prefer FIREBASE_SERVICE_ACCOUNT over FIREBASE_TOKEN."
gh secret list -R "${REPO}"
