<#
    BizFlow - one-shot database setup.

    Creates the database and every table on the SQL Server named in
    API\BizFlow.Api\appsettings.json (ConnectionStrings:Default), signing in with
    the same login the API uses. Safe to run more than once.

    Usage (from this folder):
        .\run-database-setup.ps1
#>

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "db-connection.ps1")

$Server   = $Db.Server
$Database = $Db.Database
$auth     = $Db.SqlcmdAuth

Write-Host "Connecting to $Server, database $Database, $($Db.AuthLabel)." -ForegroundColor Cyan

function Invoke-SqlFile {
    param([string]$File, [string]$Database)

    $args = @("-S", $Server) + $auth + @("-C", "-I", "-b", "-i", (Join-Path $here $File))
    if ($Database) { $args += @("-d", $Database) }

    Write-Host "`n--- $File ---" -ForegroundColor Yellow
    & sqlcmd @args
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE." }
}

# Creates the database if it is not there yet (uses the name from appsettings.json).
Write-Host "`n--- create database ---" -ForegroundColor Yellow
$create = "IF DB_ID(N'$Database') IS NULL BEGIN PRINT 'Creating database $Database ...'; CREATE DATABASE [$Database]; END ELSE PRINT 'Database $Database already exists.';"
& sqlcmd @(@("-S", $Server) + $auth + @("-C", "-I", "-b", "-Q", $create))
if ($LASTEXITCODE -ne 0) { throw "Could not create or reach database $Database on $Server." }

Invoke-SqlFile -File "02_schema.sql" -Database $Database
Invoke-SqlFile -File "04_preferences.sql" -Database $Database
Invoke-SqlFile -File "05_payment_proofs.sql" -Database $Database
Invoke-SqlFile -File "06_reconcile_balances.sql" -Database $Database
Invoke-SqlFile -File "07_expenses_and_reporting.sql" -Database $Database
Invoke-SqlFile -File "08_remove_subscriptions.sql" -Database $Database
Invoke-SqlFile -File "09_shop_upi.sql" -Database $Database
Invoke-SqlFile -File "10_barcodes.sql" -Database $Database
Invoke-SqlFile -File "11_workers_and_cards.sql" -Database $Database
Invoke-SqlFile -File "12_shop_branding.sql" -Database $Database
Invoke-SqlFile -File "13_password_resets.sql" -Database $Database

Write-Host "`n--- verification ---" -ForegroundColor Yellow
$verifyArgs = @("-S", $Server) + $auth + @("-C", "-I", "-d", $Database, "-i", (Join-Path $here "03_verify.sql"))
& sqlcmd @verifyArgs

Write-Host "`nDatabase ready." -ForegroundColor Green
Write-Host "Next: cd ..\BizFlow.Api  then  dotnet run" -ForegroundColor Green
Write-Host "The API seeds the demo accounts on first start." -ForegroundColor Green
