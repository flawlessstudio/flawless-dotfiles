param(
  [switch]$Apply,
  [switch]$Plan
)

$ErrorActionPreference = "Stop"
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
  if ($cmd) { return [string]$cmd.Source }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\mise.exe"),
    (Join-Path $env:USERPROFILE "scoop\shims\mise.exe")
  )
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      $env:Path = "$(Split-Path -Parent $candidate);$env:Path"
      return [string]$candidate
    }
  }
  return $null
}

$existing = Resolve-Mise
if ($existing) {
  Write-Host "PASS  mise available: $existing"
  exit 0
}

if ($Plan) {
  Write-Warning "mise is not installed. Apply would install it with Scoop when available, otherwise WinGet (jdx.mise)."
  exit 3
}

if (Get-Command scoop -ErrorAction SilentlyContinue) {
  Write-Host "Installing mise with Scoop..."
  & scoop install mise | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "scoop failed to install mise" }
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
  Write-Host "Installing mise with Windows Package Manager (jdx.mise)..."
  & winget install --id jdx.mise --exact --accept-source-agreements --accept-package-agreements | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "winget failed to install mise" }
} else {
  throw "mise is missing and neither Scoop nor winget is available. Install mise, then rerun."
}

Refresh-Path
$installed = Resolve-Mise
if (-not $installed) {
  throw "mise installation completed but the executable cannot be resolved in this PowerShell session."
}

Write-Host "PASS  mise installed: $installed"
exit 0
