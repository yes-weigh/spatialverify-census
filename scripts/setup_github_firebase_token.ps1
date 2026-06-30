# One-time setup: store Firebase CI token in GitHub Actions secrets.
# Requires: firebase-tools (npm i -g firebase-tools), gh CLI (logged in).
param(
    [string]$Repo = "yes-weigh/spatialverify-census"
)

$ErrorActionPreference = "Stop"

Write-Host "Opening browser for Firebase login (project: spatialverify-census)..." -ForegroundColor Cyan
$raw = firebase login:ci --project spatialverify-census 2>&1 | Out-String
$token = ($raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^1//' } | Select-Object -Last 1)
if (-not $token) {
    Write-Host $raw
    Write-Error "Could not parse token from firebase login:ci output. Copy the line starting with 1// manually."
}

Write-Host "Saving FIREBASE_TOKEN to GitHub secret for $Repo ..." -ForegroundColor Cyan
$token | gh secret set FIREBASE_TOKEN -R $Repo

Write-Host "Done. FIREBASE_TOKEN is set on $Repo" -ForegroundColor Green
gh secret list -R $Repo
