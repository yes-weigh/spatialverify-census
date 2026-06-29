# One-time setup: store Firebase CI token in GitHub Actions secrets.
# Requires: firebase-tools (npm i -g firebase-tools), gh CLI (logged in).
param(
    [string]$Repo = "yes-weigh/spatialverify-census"
)

$ErrorActionPreference = "Stop"

Write-Host "Opening browser for Firebase login (project: spatialverify-census)..." -ForegroundColor Cyan
$raw = firebase login:ci --project spatialverify-census 2>&1 | Out-String
if ($raw -match '(1//[\w-]+)') {
    $token = $Matches[1]
} else {
    Write-Host $raw
    Write-Error "Could not parse token from firebase login:ci output"
}

Write-Host "Saving FIREBASE_TOKEN to GitHub secret for $Repo ..." -ForegroundColor Cyan
$token | gh secret set FIREBASE_TOKEN -R $Repo

Write-Host "Done. FIREBASE_TOKEN is set on $Repo" -ForegroundColor Green
gh secret list -R $Repo
