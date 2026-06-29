# Sprint 1 validation playbook (run before Sprint 2)
# Prerequisites: Docker Desktop running
#
# Usage:
#   .\scripts\run-validation.ps1 -ObsCount 10000
#   .\scripts\run-validation.ps1 -ObsCount 100000

param(
    [int]$ObsCount = 10000,
    [int]$BenchRuns = 20,
    [switch]$SkipLoadTest,
    [switch]$RunAccuracyEval
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host "=== Sprint 1 Validation ===" -ForegroundColor Cyan
Write-Host "Observation target: $ObsCount"

# 1. Start infrastructure
Write-Host "`n[1/6] Starting Docker..." -ForegroundColor Yellow
Set-Location $Root
docker compose up -d
if ($LASTEXITCODE -ne 0) { throw "Docker compose failed — is Docker Desktop running?" }

Start-Sleep -Seconds 8

# 2. Migrate + seed
Write-Host "`n[2/6] Migrating database..." -ForegroundColor Yellow
Set-Location "$Root\backend"
npm run migrate
if ($LASTEXITCODE -ne 0) { throw "Migration failed" }

Write-Host "`n[3/6] Seeding (if empty)..." -ForegroundColor Yellow
npm run seed

# 3. Load test
if (-not $SkipLoadTest) {
    Write-Host "`n[4/6] Loading $ObsCount synthetic observations..." -ForegroundColor Yellow
    $env:OBS_COUNT = "$ObsCount"
    $env:ASSET_COUNT = [math]::Max(500, [math]::Floor($ObsCount / 20)).ToString()
    $env:BATCH_SIZE = "200"
    npm run loadtest:observations
    if ($LASTEXITCODE -ne 0) { throw "Load test failed" }
} else {
    Write-Host "`n[4/6] Skipping load test" -ForegroundColor Gray
}

# 4. Benchmark
Write-Host "`n[5/6] Running identity benchmark ($BenchRuns runs)..." -ForegroundColor Yellow
$env:BENCH_RUNS = "$BenchRuns"
npm run bench:identity
if ($LASTEXITCODE -ne 0) { throw "Benchmark failed" }

# 5. Optional accuracy eval
if ($RunAccuracyEval) {
    Write-Host "`n[6/6] Running accuracy evaluation..." -ForegroundColor Yellow
    npm run eval:identity-accuracy
    if ($LASTEXITCODE -ne 0) { throw "Accuracy eval failed" }
} else {
    Write-Host "`n[6/6] Skipping accuracy eval (pass -RunAccuracyEval to enable)" -ForegroundColor Gray
}

Write-Host "`n=== Validation complete ===" -ForegroundColor Green
Write-Host "Reports saved to: backend\benchmark-results\"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  - Review p50/p95/p99 and EXPLAIN flags in JSON report"
Write-Host "  - If 10k passes, rerun: .\scripts\run-validation.ps1 -ObsCount 100000"
Write-Host "  - Then: .\scripts\run-validation.ps1 -ObsCount 100000 -RunAccuracyEval"
