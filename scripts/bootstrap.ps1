param(
  [switch]$Apply,
  [switch]$Plan
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if ($Apply -and $Plan) { throw "Choose either -Plan or -Apply, not both." }
if (-not $Apply) { $Plan = $true }

if ($Plan) {
  Write-Host "== Flawless Windows environment plan =="
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/ensure-mise.ps1" -Plan
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3) { exit $LASTEXITCODE }
  if ($LASTEXITCODE -eq 0) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/install-tools.ps1" -Plan
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/project-windows.ps1" -Plan
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Write-Host ""
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/doctor.ps1" -AllowMissing
  exit $LASTEXITCODE
}

Write-Host "== Phase 1/4: mise bootstrap =="
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/ensure-mise.ps1" -Apply
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "== Phase 2/4: toolchain convergence =="
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/install-tools.ps1" -Apply
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "== Phase 3/4: native Windows configuration projection =="
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/project-windows.ps1" -Apply
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "== Phase 4/4: environment doctor =="
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/doctor.ps1"
exit $LASTEXITCODE
