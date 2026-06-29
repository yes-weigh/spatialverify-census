# Live debug on USB-connected Android phone (SpatialVerify)
param(
  [switch]$Pub,       # run "flutter pub get" (skipped by default for speed)
  [switch]$Clean,     # "flutter clean" before run (use after native/plugin changes)
  [switch]$Attach,    # attach to app already running on phone (fastest re-connect)
  [switch]$NoBuild    # skip Gradle when APK is already installed (Dart-only tweaks)
)

$env:PATH = "d:\census\tools\flutter\bin;d:\census\tools\android-sdk\platform-tools;" + $env:PATH
$env:ANDROID_HOME = "d:\census\tools\android-sdk"
$env:ANDROID_SDK_ROOT = "d:\census\tools\android-sdk"
$env:TEMP = "d:\census\tmp"
$env:TMP = "d:\census\tmp"

Set-Location $PSScriptRoot

# Prefer Wi-Fi LAN IP so the phone can reach the laptop API (not emulator/WSL addresses).
$lanIp = (
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object {
    $_.IPAddress -match '^(192\.168\.|10\.)' -and
    $_.InterfaceAlias -notmatch 'vEthernet|WSL|Hyper-V|Loopback'
  } |
  Select-Object -First 1 -ExpandProperty IPAddress
)
if (-not $lanIp) { $lanIp = '192.168.1.26' }
Write-Host "API host for phone: $lanIp"

$adbLines = @(adb devices | Select-String "\tdevice$" | ForEach-Object { ($_ -split "\s+", 2)[0] })
if (-not $adbLines.Count) {
  Write-Host ""
  Write-Host "No Android phone detected over USB." -ForegroundColor Red
  Write-Host "  1. Reconnect USB cable (use a data cable, not charge-only)"
  Write-Host "  2. On phone: Settings > Developer options > USB debugging ON"
  Write-Host "  3. Xiaomi/Redmi: also enable 'Install via USB' / 'USB debugging (Security settings)'"
  Write-Host "  4. Unlock phone and tap Allow when prompted"
  Write-Host "  5. Run: adb devices   (should show your device as 'device', not 'unauthorized')"
  Write-Host ""
  exit 1
}

$deviceId = $adbLines[0]
if ($adbLines.Count -gt 1) {
  Write-Host "Multiple devices found; using $deviceId"
} else {
  Write-Host "Using device: $deviceId"
}

# Google Maps: key in android/local.properties (GOOGLE_MAPS_API_KEY) or env var
$googleMapsKey = $env:GOOGLE_MAPS_API_KEY
if (-not $googleMapsKey) {
  $localProps = Join-Path $PSScriptRoot "android\local.properties"
  if (Test-Path $localProps) {
    Get-Content $localProps | ForEach-Object {
      if ($_ -match '^\s*GOOGLE_MAPS_API_KEY=(.+)$') {
        $googleMapsKey = $Matches[1].Trim()
      }
    }
  }
}
if (-not $googleMapsKey) { $googleMapsKey = '' }
if ($googleMapsKey) {
  Write-Host "Google Maps API key: configured (from local.properties or env)"
} else {
  Write-Host "Google Maps API key: not set (Esri fallback + compass navigation)" -ForegroundColor Yellow
}

$dartDefines = @(
  "--dart-define=GOOGLE_MAPS_API_KEY=$googleMapsKey"
)

if ($Clean) {
  Write-Host "Cleaning build outputs..." -ForegroundColor Yellow
  flutter clean
}

$packageConfig = Join-Path $PSScriptRoot '.dart_tool\package_config.json'
$needsPubGet = $Pub -or -not (Test-Path $packageConfig)
if ($needsPubGet) {
  if (-not (Test-Path $packageConfig)) {
    Write-Host 'Restoring packages (missing .dart_tool after clean or first run)...' -ForegroundColor Yellow
  }
  flutter pub get
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($Attach) {
  Write-Host "Attaching to running app (no rebuild). Press q to detach." -ForegroundColor Cyan
  flutter attach -d $deviceId
  exit $LASTEXITCODE
}

$flutterArgs = @('run', '-d', $deviceId) + $dartDefines
if (-not $needsPubGet) { $flutterArgs += '--no-pub' }
if ($NoBuild) { $flutterArgs += '--no-build' }

Write-Host ''
Write-Host 'Speed tips:' -ForegroundColor Cyan
Write-Host '  r = hot reload (~1s)   R = hot restart (~3s)   q = quit'
Write-Host '  Keep this session open - avoid re-running the script for Dart/UI changes.'
Write-Host '  Re-run only after pubspec.yaml, Gradle, or --dart-define changes.'
Write-Host '  Faster reconnect: .\run-debug.ps1 -Attach'
Write-Host '  Skip Gradle if APK installed: .\run-debug.ps1 -NoBuild'
Write-Host '  After plugin/native changes: .\run-debug.ps1 -Pub -Clean'
Write-Host ''

flutter @flutterArgs
exit $LASTEXITCODE
