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

function Invoke-MiseQuiet([string[]]$Arguments) {
  $previous = $ErrorActionPreference
  try {
    # Windows PowerShell 5 may promote native stderr/progress output to
    # NativeCommandError even when the native process exits successfully.
    # For this machine-readable probe, the native exit code is authoritative.
    $ErrorActionPreference = "Continue"
    & $script:MiseExe @Arguments *> $null
    return [int]$LASTEXITCODE
  } catch {
    return if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 2 }
  } finally {
    $ErrorActionPreference = $previous
  }
}

$MiseExe = Resolve-Mise
if (-not $MiseExe) {
  Write-Error "mise is required. Run scripts/ensure-mise.ps1 -Apply first."
  exit 3
}

$env:MISE_TRUSTED_CONFIG_PATHS = $Root

if ($Plan) {
  Write-Host "== Flawless toolchain plan =="
  & $MiseExe install --dry-run | Out-Host
  exit $LASTEXITCODE
}

Write-Host "== Installing locked/pinned Flawless toolchain =="
& $MiseExe --yes install | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $MiseExe reshim | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$probeCode = Invoke-MiseQuiet @("install", "--dry-run-code")
if ($probeCode -eq 1) { throw "mise still reports configured tools missing after install." }
if ($probeCode -ne 0) { exit $probeCode }

Write-Host "PASS  configured toolchain converged"
exit 0
