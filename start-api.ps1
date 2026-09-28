<#
    Starts (or restarts) the BizBill API on port 5000 for this PC AND for phones
    on the same Wi-Fi. Checks the database first so failures are obvious.
#>

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- stop an API that is already running, so this is a clean restart
$running = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue
foreach ($c in $running) {
    try {
        Write-Host "Stopping the old API (process $($c.OwningProcess)) ..." -ForegroundColor DarkGray
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop
    } catch { }
}
Start-Sleep -Milliseconds 800

# Same server, database and login as the API (API\BizFlow.Api\appsettings.json).
. (Join-Path $root "API\Database\db-connection.ps1")
Write-Host "Checking SQL Server $($Db.Server) ($($Db.Database)) ..." -ForegroundColor Cyan
if (Get-Command sqlcmd -ErrorAction SilentlyContinue) {
    & sqlcmd @(@("-S", $Db.Server) + $Db.SqlcmdAuth + @("-C", "-I", "-d", $Db.Database, "-h", "-1", "-W", "-Q", "SELECT 'Database reachable';"))
} else {
    Write-Host "sqlcmd is not installed here - skipping the check; the API reports it at /health." -ForegroundColor DarkGray
    $global:LASTEXITCODE = 0
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "`nCannot reach $($Db.Database) on $($Db.Server). Check the PC is on the same network, then run:" -ForegroundColor Red
    Write-Host "  cd `"$root\API\Database`"; .\run-database-setup.ps1" -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 1
}

# ---- this PC's Wi-Fi / LAN address, for the phone app
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
       Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and
                      $_.PrefixOrigin -in @("Dhcp", "Manual") } |
       Select-Object -First 1).IPAddress

# ---- let phones through Windows Firewall (needs admin once; harmless if it fails)
if (-not (Get-NetFirewallRule -DisplayName "BizFlow API 5000" -ErrorAction SilentlyContinue)) {
    try {
        New-NetFirewallRule -DisplayName "BizFlow API 5000" -Direction Inbound -Protocol TCP `
            -LocalPort 5000 -Action Allow -Profile Private,Domain -ErrorAction Stop | Out-Null
        Write-Host "Firewall opened for phones on port 5000." -ForegroundColor Green
    } catch {
        Write-Host "Could not open the firewall (run once as Administrator so phones can connect)." -ForegroundColor Yellow
    }
}

Write-Host "`nStarting API on port 5000 ..." -ForegroundColor Cyan
Write-Host "  This PC / Windows app : http://localhost:5000" -ForegroundColor Green
if ($ip) {
    Write-Host "  Phones (same Wi-Fi)   : http://$($ip):5000   <- type this in the app's Server button" -ForegroundColor Green
}
Write-Host "  Swagger               : http://localhost:5000/swagger" -ForegroundColor Green
Write-Host "Keep this window open. Press Ctrl+C to stop.`n" -ForegroundColor DarkGray

$env:ASPNETCORE_ENVIRONMENT = "Development"
Set-Location (Join-Path $root "API\BizFlow.Api")
# 0.0.0.0 = listen for this PC and for phones; the launch profile only allows localhost.
dotnet run --no-launch-profile --urls "http://0.0.0.0:5000"
