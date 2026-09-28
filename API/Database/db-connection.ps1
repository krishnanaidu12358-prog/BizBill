<#
    Reads the database connection from API\BizFlow.Api\appsettings.json
    (ConnectionStrings:Default) so every script uses the SAME server, database
    and login as the API. Change the connection string there, and only there.

    Dot-source it:   . "$PSScriptRoot\db-connection.ps1"
    Then use:        $Db.Server, $Db.Database, $Db.SqlcmdAuth
#>

$settingsPath = Join-Path (Split-Path -Parent $PSScriptRoot) "BizFlow.Api\appsettings.json"
if (-not (Test-Path $settingsPath)) { throw "Cannot find $settingsPath" }

$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
$cs = $settings.ConnectionStrings.Default
if (-not $cs) { throw "ConnectionStrings:Default is empty in $settingsPath" }

$builder = New-Object System.Data.Common.DbConnectionStringBuilder
$builder.set_ConnectionString($cs)

function Get-CsValue([string[]]$names) {
    foreach ($n in $names) { if ($builder.ContainsKey($n)) { return [string]$builder[$n] } }
    return $null
}

$Db = [ordered]@{
    Server   = Get-CsValue @("server", "data source", "address", "addr")
    Database = Get-CsValue @("database", "initial catalog")
    User     = Get-CsValue @("user id", "uid", "user")
    Password = Get-CsValue @("password", "pwd")
}

if (-not $Db.Database) { $Db.Database = "BizFlowDb" }

$integrated = Get-CsValue @("integrated security", "trusted_connection")
if ($Db.User -and -not ($integrated -in @("true", "sspi", "yes"))) {
    $Db.SqlcmdAuth = @("-U", $Db.User, "-P", $Db.Password)
    $Db.AuthLabel  = "as '$($Db.User)'"
} else {
    $Db.SqlcmdAuth = @("-E")
    $Db.AuthLabel  = "with Windows Authentication"
}
