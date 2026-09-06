param(
  [switch]$Apply,
  [switch]$Plan
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if ($Apply -and $Plan) { throw "Choose either -Plan or -Apply, not both." }
if (-not $Apply) { $Plan = $true }

function Refresh-Path {
  $parts = @()
  foreach ($value in @(
    $env:Path,
    [Environment]::GetEnvironmentVariable("Path", "User"),
    [Environment]::GetEnvironmentVariable("Path", "Machine")
  )) {
    if ($value) { $parts += ($value -split ';') }
  }
  $env:Path = (($parts | Where-Object { $_ } | Select-Object -Unique) -join ';')
}

function Resolve-Mise {
  $cmd = Get-Command mise -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\mise.exe"),
    (Join-Path $env:USERPROFILE "scoop\shims\mise.exe")
  )
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      $env:Path = "$(Split-Path -Parent $candidate);$env:Path"
      return $candidate
    }
  }
  return $null
}

function Ensure-Mise {
  $existing = Resolve-Mise
  if ($existing) { return $existing }

  if ($Plan) {
    Write-Warning "mise is not installed. Install it first, or rerun with -Apply."
    exit 3
  }

  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "Installing mise with Scoop (recommended Windows package path)..."
    & scoop install mise
    if ($LASTEXITCODE -ne 0) { throw "scoop failed to install mise" }
  } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "Installing mise with the official Windows package id jdx.mise..."
    & winget install --id jdx.mise --exact --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install mise" }
  } else {
    throw "mise is missing and neither Scoop nor winget is available. Install mise, then rerun this command."
  }

  Refresh-Path
  $installed = Resolve-Mise
  if (-not $installed) {
    throw "mise was installed but cannot be resolved in this PowerShell session. Open a new shell and rerun."
  }
  return $installed
}

$MiseExe = Ensure-Mise
# Trust is process-scoped: plan/apply do not write persistent trust state.
$env:MISE_TRUSTED_CONFIG_PATHS = $Root

if ($Plan) {
  Write-Host "== Flawless Windows environment plan =="
  & $MiseExe install --dry-run
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/project-windows.ps1" -Plan
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Write-Host ""
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/doctor.ps1" -AllowMissing
  exit $LASTEXITCODE
}

Write-Host "== Installing pinned Flawless toolchain =="
& $MiseExe --yes install
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $MiseExe reshim
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "== Applying native Windows configuration projection =="
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/project-windows.ps1" -Apply
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/doctor.ps1"
exit $LASTEXITCODE
