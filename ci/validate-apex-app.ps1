<#
.SYNOPSIS
  Validate an APEXLang application directory offline with SQLcl (no database connection).
  PowerShell port of the APEXLang 26.2 skill script apexlang-compile/scripts/validate-apex-app.sh.
.EXAMPLE
  $env:SQLCL_BIN = 'C:\path\to\sqlcl\bin\sql.exe'
  .\ci\validate-apex-app.ps1 -AppDirectory .\oan-app-portal
#>
param(
    [Parameter(Mandatory = $true)][string]$AppDirectory
)
$ErrorActionPreference = 'Stop'

$sqlcl = $env:SQLCL_BIN
if (-not $sqlcl) {
    # Fall back to sql on PATH (winget installs SQLcl and adds it to PATH)
    $cmd = Get-Command sql -ErrorAction SilentlyContinue
    if ($cmd) { $sqlcl = $cmd.Source }
}
if (-not $sqlcl -or -not (Test-Path $sqlcl)) {
    Write-Error 'SQLCL_BIN must point to the SQLcl executable (sql.exe / sql.cmd), or sql must be on PATH.'
    exit 2
}
if (-not (Test-Path $AppDirectory -PathType Container)) {
    Write-Error "Application directory does not exist: $AppDirectory"
    exit 2
}
$appPath = (Resolve-Path $AppDirectory).Path
if ($appPath -match '["\r\n]') {
    Write-Error 'Application directory contains unsupported SQLcl command characters.'
    exit 2
}

# SQLcl needs a readable stdin, and Windows PowerShell 5.1 prefixes piped stdin with a UTF-8 BOM
# (SQLcl then reports "Unknown Command"). So the commands are written to a BOM-less file and cmd.exe
# pipes that file into SQLcl. SQLcl can report errors while exiting 0, so the success marker is required.
$ErrorActionPreference = 'Continue'
$script = Join-Path ([IO.Path]::GetTempPath()) ("oan-validate-" + [guid]::NewGuid().ToString('N') + ".sql")
[IO.File]::WriteAllText($script, "apex validate -input `"$appPath`"`nexit`n", (New-Object Text.UTF8Encoding($false)))
try {
    $output = cmd.exe /d /c "type `"$script`" | `"$sqlcl`" /nolog 2>&1" | Out-String -Width 400
} finally {
    Remove-Item $script -ErrorAction SilentlyContinue
}
Write-Output $output

if ($LASTEXITCODE -ne 0 -or $output -notmatch 'Validation successful') {
    Write-Error 'APEXLang validation failed.'
    exit 1
}
exit 0
