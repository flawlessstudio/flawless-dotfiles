param(
  [switch]$Apply,
  [switch]$Plan
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if ($Apply -and $Plan) { throw "Choose either -Plan or -Apply, not both." }
if (-not $Apply) { $Plan = $true }

function Resolve-Mise {
  $cmd = Get-Command mise -ErrorAction SilentlyContinue
  if ($cmd) { return [string]$cmd.Source }
  foreach ($candidate in @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\mise.exe"),
    (Join-Path $env:USERPROFILE "scoop\shims\mise.exe")
  )) {
    if (Test-Path $candidate) { return [string]$candidate }
  }
  return $null
}

$MiseExe = Resolve-Mise
if (-not $MiseExe) {
  Write-Error "mise is required. Run scripts/ensure-mise.ps1 -Apply first."
  exit 3
}

$env:MISE_TRUSTED_CONFIG_PATHS = $Root

if ($Plan) {
  Write-Host "== Flawless toolchain plan =="
  & $MiseExe install --dry-run
  exit $LASTEXITCODE
}

Write-Host "== Installing locked/pinned Flawless toolchain =="
& $MiseExe --yes install
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $MiseExe reshim
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $MiseExe install --dry-run-code *> $null
if ($LASTEXITCODE -eq 1) { throw "mise still reports configured tools missing after install." }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "PASS  configured toolchain converged"
exit 0
