# Called by deploy.bat after "flutter build web".
# 1) puts a new version name into build\web\sw.js
# 2) puts the list of every build file into build\web\sw.js (for offline use)
$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot 'build\web'
$sw   = Join-Path $root 'sw.js'
if (-not (Test-Path $sw)) { throw "sw.js not found in build\web" }

$ver = 'sam-' + (Get-Date -Format yyyyMMddHHmmss)

$files = Get-ChildItem $root -Recurse -File |
  ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') } |
  Where-Object {
    $_ -ne 'sw.js' -and
    $_ -notmatch '\.(map|symbols)$' -and
    $_ -notmatch '^canvaskit/(chromium|skwasm)' -and
    $_ -ne '.last_build_id'
  }

$list = ConvertTo-Json -Compress -InputObject @($files)

$js = [System.IO.File]::ReadAllText($sw)
$verOld  = "const VERSION = 'sam-dev';"
$listOld = 'const PRECACHE = [];'
if (-not $js.Contains($verOld) -or -not $js.Contains($listOld)) {
  throw "sw.js placeholders not found (VERSION / PRECACHE lines were changed)"
}
$js = $js.Replace($verOld, "const VERSION = '$ver';").Replace($listOld, "const PRECACHE = $list;")

[System.IO.File]::WriteAllText($sw, $js, (New-Object System.Text.UTF8Encoding $false))
Write-Host "sw.js stamped: $ver, $(@($files).Count) files"
