<#
.SYNOPSIS
  Brand check (Q23, Q30): fails if the APEX application uses Oracle logos or brand marks.
  OAN is an independent alumni community; pages, static files and email templates must not
  carry Oracle logos, the Oracle wordmark image, Oracle Red (#C74634) or Oracle Sans.
  The word "Oracle" in running text (for example "Oracle alumni", the independence disclaimer)
  is allowed; logo files and brand assets are not.
.EXAMPLE
  .\ci\check-brand.ps1 -AppDirectory .\oan-app-portal
#>
param(
    [Parameter(Mandatory = $true)][string]$AppDirectory
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $AppDirectory -PathType Container)) { Write-Error "Application directory does not exist: $AppDirectory"; exit 2 }
$root = (Get-Item -LiteralPath (Resolve-Path $AppDirectory).Path).FullName.TrimEnd('\')   # long-name form, matches FullName below
$problems = New-Object System.Collections.Generic.List[string]

# 1. Static files whose names suggest an Oracle logo or brand asset
Get-ChildItem -Path $root -Recurse -File | Where-Object {
    $_.Name -match '(?i)(oracle|redwood).*(logo|mark|brand|wordmark)|(logo|mark|brand).*oracle|^o[-_]?logo'
} | ForEach-Object { $problems.Add("Brand asset file: $($_.FullName.Substring($root.Length + 1))") }

# 2. Source references to Oracle logos, Oracle Red or Oracle Sans
$patterns = @(
    @{ Name = 'Oracle logo reference';  Regex = '(?i)oracle[-_ ]?(logo|wordmark)|o-logo|oracle\.com/[^\s"'']*\.(png|svg|jpe?g|gif|webp)' },
    @{ Name = 'Oracle Red #C74634';     Regex = '(?i)#c74634\b' },
    @{ Name = 'Oracle Sans font';       Regex = '(?i)oracle\s*sans' }
)
Get-ChildItem -Path $root -Recurse -File -Include *.apx, *.css, *.js, *.html, *.json, *.svg | ForEach-Object {
    $file = $_
    $rel = $file.FullName.Substring($root.Length + 1)
    $lines = @(Get-Content -LiteralPath $file.FullName)       # @() so a one-line file is still an array
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($p in $patterns) {
            if ($lines[$i] -match $p.Regex) { $problems.Add("$($p.Name): ${rel}:$($i + 1)") }
        }
    }
}

if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Output $_ }
    Write-Error "Brand check failed: $($problems.Count) Oracle logo/brand reference(s) found (Q23, Q30)."
    exit 1
}
Write-Output "Brand check passed: no Oracle logos or brand marks in $AppDirectory."
exit 0
