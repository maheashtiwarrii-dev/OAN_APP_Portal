<#
.SYNOPSIS
  Import an APEXLang application directory into a database with SQLcl.
  PowerShell port of the APEXLang 26.2 skill script apexlang-deploy/scripts/deploy-apex-app.sh.
  Import is an outward action: run only after live validation passes and the import is approved
  (plan "APEXLang pipeline", gate 8.0 for production).
.EXAMPLE
  $env:SQLCL_BIN = 'C:\path\to\sqlcl\bin\sql.exe'
  $env:SQLCL_CONNECTION_STRING = '-name oan_app_dev'      # saved SQLcl connection; never put passwords in git
  .\ci\deploy-apex-app.ps1 -AppDirectory .\oan-app-portal
#>
param(
    [Parameter(Mandatory = $true)][string]$AppDirectory
)
$ErrorActionPreference = 'Stop'

$sqlcl = $env:SQLCL_BIN
if (-not $sqlcl) {
    $cmd = Get-Command sql -ErrorAction SilentlyContinue
    if ($cmd) { $sqlcl = $cmd.Source }
}
if (-not $sqlcl -or -not (Test-Path $sqlcl)) { Write-Error 'SQLCL_BIN must point to the SQLcl executable.'; exit 2 }
if (-not $env:SQLCL_CONNECTION_STRING) { Write-Error 'SQLCL_CONNECTION_STRING must be set (e.g. "-name oan_app_dev").'; exit 2 }
if (-not (Test-Path $AppDirectory -PathType Container)) { Write-Error "Application directory does not exist: $AppDirectory"; exit 2 }
$appPath = (Resolve-Path $AppDirectory).Path
if ($appPath -match '["\r\n]') { Write-Error 'Application directory contains unsupported SQLcl command characters.'; exit 2 }

$commands = @"
begin
  apex_application_install.set_auto_install_sup_obj(p_auto_install_sup_obj => true);
end;
/
apex import -input "$appPath"
exit
"@
$connArgs = $env:SQLCL_CONNECTION_STRING -split ' '
# SQLcl needs a readable stdin, and Windows PowerShell 5.1 prefixes piped stdin with a UTF-8 BOM
# ("Unknown Command"), so the commands go to a BOM-less file that cmd.exe pipes into SQLcl.
$ErrorActionPreference = 'Continue'
$script = Join-Path ([IO.Path]::GetTempPath()) ("oan-deploy-" + [guid]::NewGuid().ToString('N') + ".sql")
[IO.File]::WriteAllText($script, $commands.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
try {
    cmd.exe /d /c "type `"$script`" | `"$sqlcl`" $($env:SQLCL_CONNECTION_STRING)"
    $rc = $LASTEXITCODE
} finally {
    Remove-Item $script -ErrorAction SilentlyContinue
}
exit $rc
