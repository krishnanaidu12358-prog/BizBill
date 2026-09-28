<#
    BizBill - one place to set up and run everything, for Windows AND mobile.
    Double-click BizFlow-Setup.bat to open this.
#>

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$frontend = Join-Path $root "Frontend"
$Host.UI.RawUI.WindowTitle = "BizBill Setup"

function Title($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "  [OK] $t" -ForegroundColor Green }
function Bad($t)   { Write-Host "  [!!] $t" -ForegroundColor Yellow }

# Puts the BizBill icon, window title and BizBill.exe name on the Windows app.
function Apply-WindowsBranding($frontend) {
    $win = Join-Path $frontend "windows"
    if (-not (Test-Path $win)) { return }
    $ico = Join-Path $frontend "branding\app_icon.ico"
    if (Test-Path $ico) { Copy-Item $ico (Join-Path $win "runner\resources\app_icon.ico") -Force }
    $edits = @(
        @{ File = "runner\main.cpp";  From = 'L"bizflow_app"';                 To = 'L"BizBill"' },
        @{ File = "CMakeLists.txt";   From = 'set(BINARY_NAME "bizflow_app")'; To = 'set(BINARY_NAME "BizBill")' },
        @{ File = "runner\Runner.rc"; From = '"bizflow_app.exe"';              To = '"BizBill.exe"' },
        @{ File = "runner\Runner.rc"; From = '"bizflow_app"';                  To = '"BizBill"' }
    )
    foreach ($e in $edits) {
        $path = Join-Path $win $e.File
        if (Test-Path $path) {
            $text = [IO.File]::ReadAllText($path)
            if ($text.Contains($e.From)) { [IO.File]::WriteAllText($path, $text.Replace($e.From, $e.To)) }
        }
    }
}

function LanIp {
    (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
     Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and
                    $_.PrefixOrigin -in @("Dhcp", "Manual") } |
     Select-Object -First 1).IPAddress
}

# ------------------------------------------------------------ 1. tools
Title "Checking tools"
$haveFlutter = [bool](Get-Command flutter -ErrorAction SilentlyContinue)
$haveDotnet  = [bool](Get-Command dotnet  -ErrorAction SilentlyContinue)
$haveSql     = [bool](Get-Command sqlcmd  -ErrorAction SilentlyContinue)
if ($haveFlutter) { Ok "Flutter" } else { Bad "Flutter not found - install it: https://docs.flutter.dev/get-started/install/windows" }
if ($haveDotnet)  { Ok ".NET SDK" } else { Bad ".NET SDK not found - install .NET 9 SDK" }
if ($haveSql)     { Ok "sqlcmd (SQL Server)" } else { Bad "sqlcmd not found - install SQL Server command-line tools" }
if (-not $haveFlutter) { Read-Host "`nPress Enter to close"; exit 1 }

# ------------------------------------------------------------ 2. app packages + Windows support
Title "Preparing the app (Windows + Android)"
Set-Location $frontend
if (-not (Test-Path (Join-Path $frontend "windows"))) {
    Write-Host "Adding Windows desktop support (first time only) ..."
    $hadTest = Test-Path "test\widget_test.dart"
    flutter create --platforms=windows --project-name bizflow_app .
    # flutter create also drops a sample test that does not fit this app - remove it.
    if (-not $hadTest -and (Test-Path "test\widget_test.dart")) { Remove-Item "test\widget_test.dart" }
}
Apply-WindowsBranding $frontend
flutter pub get
if ($LASTEXITCODE -eq 0) { Ok "Packages ready (share_plus, qr_flutter, mobile_scanner ...)" }
else { Bad "flutter pub get failed - copy the red text above and send it to Claude" }

# ------------------------------------------------------------ 3. API
if ($haveDotnet) {
    Title "Restarting the API"
    Start-Process powershell -ArgumentList @(
        "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $root 'start-api.ps1')`"")
    Ok "API is starting in its own window (keep it open)."
}

$ip = LanIp

# ------------------------------------------------------------ 4. menu
while ($true) {
    Title "What do you want to do?"
    Write-Host "  1  Run BizBill on this Windows PC"
    Write-Host "  2  Run BizBill on an Android phone (connected by USB, USB debugging on)"
    Write-Host "  3  Build the Windows app for the shop counter (BizBill.exe)"
    Write-Host "  4  Build the Android app to install on phones (.apk)"
    Write-Host "  5  Restart the API"
    Write-Host "  6  Check setup (flutter doctor)"
    Write-Host "  0  Exit"
    if ($ip) { Write-Host "`n  Phones: in the app's login screen tap Server and enter  http://$($ip):5000" -ForegroundColor Green }
    $choice = Read-Host "`nType a number and press Enter"

    Set-Location $frontend
    switch ($choice) {
        "1" { Apply-WindowsBranding $frontend; flutter run -d windows }
        "2" {
            flutter devices
            flutter run -d android
        }
        "3" {
            Apply-WindowsBranding $frontend
            flutter build windows --release
            if ($LASTEXITCODE -eq 0) {
                $out = Join-Path $frontend "build\windows\x64\runner\Release"
                Ok "Done. Copy this whole folder to the counter PC and run BizBill.exe:"
                Write-Host "     $out" -ForegroundColor Green
                Start-Process explorer.exe $out
            }
        }
        "4" {
            flutter build apk --release
            if ($LASTEXITCODE -eq 0) {
                $out = Join-Path $frontend "build\app\outputs\flutter-apk"
                Ok "Done. Send the APK to the phones (WhatsApp / USB) and install it:"
                Write-Host "     $out\app-release.apk" -ForegroundColor Green
                Start-Process explorer.exe $out
            }
        }
        "5" {
            Start-Process powershell -ArgumentList @(
                "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $root 'start-api.ps1')`"")
            Ok "API restarting in its own window."
        }
        "6" { flutter doctor }
        "0" { exit 0 }
        default { Bad "Type 1, 2, 3, 4, 5, 6 or 0." }
    }
}
