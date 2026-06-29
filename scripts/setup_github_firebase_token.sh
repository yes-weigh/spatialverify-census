#!/usr/bin/env bash
# One-time setup: store Firebase CI token in GitHub Actions secrets.
set -euo pipefail

REPO="${1:-yes-weigh/spatialverify-census}"

echo "Opening browser for Firebase login (project: spatialverify-census)..."
TOKEN="$(firebase login:ci --project spatialverify-census)"

if [[ -z "${TOKEN}" ]]; then
  echo "firebase login:ci failed" >&2
  exit 1
fi

echo "Saving FIREBASE_TOKEN to GitHub secret for ${REPO}..."
printf '%s' "${TOKEN}" | gh secret set FIREBASE_TOKEN -R "${REPO}"

echo "Done."
gh secret list -R "${REPO}"
