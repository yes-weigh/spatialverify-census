# Local web dev in Chrome (SpatialVerify) — hot reload, no phone required.
$env:PATH = "d:\census\tools\flutter\bin;" + $env:PATH
$env:TEMP = "d:\census\tmp"
$env:TMP = "d:\census\tmp"

Set-Location $PSScriptRoot

$webPort = if ($env:WEB_PORT) { $env:WEB_PORT } else { 8080 }
$apiPort = if ($env:API_PORT) { $env:API_PORT } else { 3000 }
$apiHost = "127.0.0.1"

Write-Host "Web app:  http://localhost:$webPort"
Write-Host "API base: http://${apiHost}:$apiPort/api/v1 (start backend separately if needed)"

# Google Maps: key in android/local.properties (GOOGLE_MAPS_API_KEY) or env var.
# Web needs "Maps JavaScript API" enabled (Android uses "Maps SDK for Android" — separate product).
# Set SKIP_GOOGLE_MAPS=1 to use Esri satellite tiles instead (fine for UI-only dev).
$skipGoogleMaps = $env:SKIP_GOOGLE_MAPS -eq '1'
$googleMapsKey = if ($skipGoogleMaps) { '' } else { $env:GOOGLE_MAPS_API_KEY }
if (-not $googleMapsKey -and -not $skipGoogleMaps) {
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

$indexPath = Join-Path $PSScriptRoot "web\index.html"
$indexBackup = Join-Path $PSScriptRoot "web\index.html.bak"
$indexContent = Get-Content $indexPath -Raw
Copy-Item $indexPath $indexBackup -Force

$mapsScript = if ($googleMapsKey) {
  "<script async defer src=`"https://maps.googleapis.com/maps/api/js?key=$googleMapsKey&loading=async`"></script>"
} else {
  "<!-- Google Maps API key not set; map tiles and routing use Esri/compass fallbacks -->"
}

if ($skipGoogleMaps) {
  Write-Host 'Google Maps: skipped (SKIP_GOOGLE_MAPS=1) - Esri satellite tiles' -ForegroundColor Yellow
} elseif ($googleMapsKey) {
  Write-Host 'Google Maps API key: configured (from local.properties or env)'
  Write-Host '  Web requires Maps JavaScript API + localhost referrer on this key.' -ForegroundColor DarkGray
  Write-Host '  If maps fail, enable Maps JavaScript API in Google Cloud Console' -ForegroundColor DarkGray
  Write-Host '  or run: $env:SKIP_GOOGLE_MAPS=''1''; .\run-web.ps1' -ForegroundColor DarkGray
} else {
  Write-Host 'Google Maps API key: not set (Esri fallback + compass navigation)' -ForegroundColor Yellow
}

try {
  $updated = $indexContent -replace '<!-- GOOGLE_MAPS_SCRIPT -->', $mapsScript
  Set-Content -Path $indexPath -Value $updated -NoNewline

  flutter run -d chrome `
    --web-port=$webPort `
    --web-hostname=localhost `
    --dart-define=API_BASE_URL=http://${apiHost}:$apiPort/api/v1 `
    --dart-define=WS_BASE_URL=ws://${apiHost}:$apiPort/ws `
    --dart-define=STANDALONE_MODE=true `
    --dart-define=GOOGLE_MAPS_API_KEY=$googleMapsKey
}
finally {
  if (Test-Path $indexBackup) {
    Move-Item $indexBackup $indexPath -Force
  }
}
