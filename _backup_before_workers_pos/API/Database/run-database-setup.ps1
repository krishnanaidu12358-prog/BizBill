<#
    BizFlow - one-shot local database setup.

    Creates BizFlowDb on the local SQL Server instance, the application login,
    and every table. Safe to run more than once.

    Usage (from this folder):
        .\run-database-setup.ps1
        .\run-database-setup.ps1 -Server "DESKTOP-BV2BD6K\SQLEXPRESS"
#>

param(
    [string]$Server = "DESKTOP-BV2BD6K",

    # Leave blank to use Windows Authentication (the default and simplest).
    # To run the scripts as 'sa' instead, pass -SaPassword "<your sa password>".
    [string]$SaPassword = ""
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($SaPassword) {
    $auth = @("-U", "sa", "-P", $SaPassword)
    Write-Host "Connecting to $Server as 'sa'." -ForegroundColor Cyan
} else {
    $auth = @("-E")
    Write-Host "Connecting to $Server with Windows Authentication." -ForegroundColor Cyan
}

function Invoke-SqlFile {
    param([string]$File, [string]$Database)

    $args = @("-S", $Server) + $auth + @("-C", "-I", "-b", "-i", (Join-Path $here $File))
    if ($Database) { $args += @("-d", $Database) }

    Write-Host "`n--- $File ---" -ForegroundColor Yellow
    & sqlcmd @args
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE." }
}

Invoke-SqlFile -File "01_create_database.sql"
Invoke-SqlFile -File "02_schema.sql" -Database "BizFlowDb"
Invoke-SqlFile -File "04_preferences.sql" -Database "BizFlowDb"
Invoke-SqlFile -File "05_payment_proofs.sql" -Database "BizFlowDb"
Invoke-SqlFile -File "06_reconcile_balances.sql" -Database "BizFlowDb"
Invoke-SqlFile -File "07_expenses_and_reporting.sql" -Database "BizFlowDb"
Invoke-SqlFile -File "08_remove_subscriptions.sql" -Database "BizFlowDb"
Invoke-SqlFile -File "09_shop_upi.sql" -Database "BizFlowDb"
Invoke-SqlFile -File "10_barcodes.sql" -Database "BizFlowDb"

Write-Host "`n--- verification ---" -ForegroundColor Yellow
$verifyArgs = @("-S", $Server) + $auth + @("-C", "-I", "-d", "BizFlowDb", "-i", (Join-Path $here "03_verify.sql"))
& sqlcmd @verifyArgs

Write-Host "`nDatabase ready." -ForegroundColor Green
Write-Host "Next: cd ..\BizFlow.Api  then  dotnet run" -ForegroundColor Green
Write-Host "The API seeds the demo accounts on first start." -ForegroundColor Green
