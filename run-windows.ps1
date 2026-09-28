<#
    BizBill - run the app on Windows (counter / billing PC).

    First time only, install:
      1. Flutter SDK (flutter doctor must be green for "Windows")
      2. Visual Studio 2022 with the "Desktop development with C++" workload
      3. Turn on Windows Developer Mode:  start ms-settings:developers

    Usage (from the "Kittu Business" folder):
        .\run-windows.ps1            # run in debug
        .\run-windows.ps1 -Release   # build BizBill.exe for the shop counter
#>
param([switch]$Release)

$ErrorActionPreference = "Stop"

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

Set-Location (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "Frontend")

# Adds the Windows desktop project the first time. Does not touch lib\ (your code).
if (-not (Test-Path "windows")) {
    Write-Host "Adding Windows support..." -ForegroundColor Cyan
    $hadTest = Test-Path "test\widget_test.dart"
    flutter create --platforms=windows --project-name bizflow_app .
    # flutter create also drops a sample test that does not fit this app - remove it.
    if (-not $hadTest -and (Test-Path "test\widget_test.dart")) { Remove-Item "test\widget_test.dart" }
}

Apply-WindowsBranding (Get-Location).Path
flutter pub get

if ($Release) {
    flutter build windows --release
    $exe = "build\windows\x64\runner\Release"
    Write-Host "`nDone. Copy the whole folder below to the counter PC and run BizBill.exe:" -ForegroundColor Green
    Write-Host (Resolve-Path $exe) -ForegroundColor Green
} else {
    flutter run -d windows
}
