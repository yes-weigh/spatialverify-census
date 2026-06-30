# Store a GCP service account JSON key in GitHub Actions (recommended for CI).
# User tokens from firebase login:ci expire; service account keys do not until revoked.
param(
    [Parameter(Mandatory = $true)]
    [string]$KeyPath,
    [string]$Repo = "yes-weigh/spatialverify-census"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $KeyPath)) {
    Write-Error "Key file not found: $KeyPath"
}

$json = Get-Content -Raw -LiteralPath $KeyPath
if ($json -notmatch '"type"\s*:\s*"service_account"') {
    Write-Error "File does not look like a GCP service account JSON key"
}

Write-Host "Saving FIREBASE_SERVICE_ACCOUNT to GitHub secret for $Repo ..." -ForegroundColor Cyan
$json | gh secret set FIREBASE_SERVICE_ACCOUNT -R $Repo

Write-Host "Done. CI will prefer FIREBASE_SERVICE_ACCOUNT over FIREBASE_TOKEN." -ForegroundColor Green
gh secret list -R $Repo
