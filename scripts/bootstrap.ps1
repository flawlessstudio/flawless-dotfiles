param(
  [switch]$Apply,
  [switch]$Plan
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if ($Apply -and $Plan) {
  throw "Choose either -Plan or -Apply, not both."
}
if (-not $Apply) { $Plan = $true }

function Refresh-Path {
  $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $user = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = "$machine;$user"
}

function Ensure-Mise {
  if (Get-Command mise -ErrorAction SilentlyContinue) { return }

  if ($Plan) {
    Write-Warning "mise is not installed. Install it first, or rerun with -Apply."
    exit 3
  }

  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "Installing mise with the official Windows package id jdx.mise..."
    & winget install --id jdx.mise --exact --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install mise" }
    Refresh-Path
  } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "Installing mise with Scoop..."
    & scoop install mise
    if ($LASTEXITCODE -ne 0) { throw "scoop failed to install mise" }
    Refresh-Path
  } else {
    throw "mise is missing and neither winget nor Scoop is available. Install mise, then rerun this command."
  }

  if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    throw "mise was installed but is not visible in this PowerShell session. Open a new shell and rerun with -Apply."
  }
}

Ensure-Mise

if ($Plan) {
  Write-Host "== Flawless environment plan =="
  & mise bootstrap --dry-run
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Write-Host ""
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/doctor.ps1" -AllowMissing
  exit $LASTEXITCODE
}

Write-Host "Trusting repository-local mise configuration..."
& mise trust "$Root/mise.toml"
if ($LASTEXITCODE -ne 0) { throw "mise trust failed" }

Write-Host "== Applying Flawless desired state =="
& mise bootstrap --yes
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/doctor.ps1"
exit $LASTEXITCODE
