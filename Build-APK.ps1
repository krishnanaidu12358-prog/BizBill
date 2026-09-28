<#
    BizBill - build the Android app (APK) to install on phones.
    Double-click Build-APK.bat to run this.
#>
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Host.UI.RawUI.WindowTitle = "BizBill - Build APK"

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter -and (Test-Path "C:\flutter\bin\flutter.bat")) { $flutter = "C:\flutter\bin\flutter.bat" }
if (-not $flutter) {
    Write-Host "Flutter not found. Install it or add C:\flutter\bin to PATH." -ForegroundColor Red
    Read-Host "Press Enter to close"; exit 1
}

# This PC's Wi-Fi address - built into the app so phones find the API by themselves.
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
       Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and
                      $_.PrefixOrigin -in @("Dhcp", "Manual") } |
       Select-Object -First 1).IPAddress
$apiUrl = if ($ip) { "http://$($ip):5000" } else { "" }

Write-Host "`nBuilding BizBill for Android ..." -ForegroundColor Cyan
if ($apiUrl) { Write-Host "Phones will connect to the API at $apiUrl" -ForegroundColor Green }
Write-Host "(first build can take 5-10 minutes)`n" -ForegroundColor DarkGray

Set-Location (Join-Path $root "Frontend")
& $flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "`nflutter pub get failed - send the red text above to Claude." -ForegroundColor Red; Read-Host "Press Enter to close"; exit 1 }

if ($apiUrl) { & $flutter build apk --release "--dart-define=API_URL=$apiUrl" }
else         { & $flutter build apk --release }

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild failed - copy the red text above and send it to Claude." -ForegroundColor Red
    Read-Host "Press Enter to close"; exit 1
}

$apk = Join-Path (Get-Location) "build\app\outputs\flutter-apk\app-release.apk"
$desk = [Environment]::GetFolderPath("Desktop")
$dest = Join-Path $desk "BizBill.apk"
Copy-Item $apk $dest -Force
$mb = [math]::Round((Get-Item $dest).Length / 1MB, 1)

Write-Host "`nDONE!  BizBill.apk ($mb MB) is on your Desktop." -ForegroundColor Green
Write-Host "Send it to a phone (WhatsApp / USB / Drive), tap it, allow 'Install unknown apps', install." -ForegroundColor Green
if ($apiUrl) { Write-Host "Phone and this PC must be on the same Wi-Fi, with the API running (start-api.ps1)." -ForegroundColor Green }
Start-Process explorer.exe "/select,`"$dest`""
Read-Host "`nPress Enter to close"
