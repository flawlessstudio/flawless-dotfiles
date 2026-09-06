param(
  [switch]$AllowMissing
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$env:MISE_TRUSTED_CONFIG_PATHS = $Root

$PassCount = 0
$WarnCount = 0
$FailCount = 0

function Pass([string]$Message) { Write-Host "PASS  $Message"; $script:PassCount++ }
function Warn([string]$Message) { Write-Warning $Message; $script:WarnCount++ }
function Fail([string]$Message) { Write-Host "FAIL  $Message" -ForegroundColor Red; $script:FailCount++ }

function Resolve-Mise {
  $cmd = Get-Command mise -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($candidate in @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\mise.exe"),
    (Join-Path $env:USERPROFILE "scoop\shims\mise.exe")
  )) {
    if (Test-Path $candidate) { return $candidate }
  }
  return $null
}

$MiseExe = Resolve-Mise

function Invoke-MiseQuiet([string[]]$Arguments) {
  if (-not $script:MiseExe) { return 127 }
  $previous = $ErrorActionPreference
  try {
    # Windows PowerShell 5 can promote native stderr/progress text to
    # NativeCommandError even for a native exit code of 0. Machine-readable
    # probes therefore use the process exit code as the source of truth.
    $ErrorActionPreference = "Continue"
    & $script:MiseExe @Arguments *> $null
    return [int]$LASTEXITCODE
  } catch {
    if ($LASTEXITCODE -is [int]) { return [int]$LASTEXITCODE }
    return 2
  } finally {
    $ErrorActionPreference = $previous
  }
}

function Test-MiseCommand([string]$Command) {
  return ((Invoke-MiseQuiet @("which", $Command)) -eq 0)
}

function Check-Required([string]$Command) {
  if (Get-Command $Command -ErrorAction SilentlyContinue) { Pass "command:$Command" }
  elseif (Test-MiseCommand $Command) { Pass "managed:$Command available through mise" }
  elseif ($AllowMissing) { Warn "command:$Command missing" }
  else { Fail "command:$Command missing" }
}

function Check-Optional([string]$Command) {
  if (Get-Command $Command -ErrorAction SilentlyContinue) { Pass "optional:$Command available" }
  elseif (Test-MiseCommand $Command) { Pass "optional:$Command available through mise" }
  else { Warn "optional:$Command not installed" }
}

Write-Host "== Flawless environment doctor =="
Write-Host "root: $Root"
Write-Host ""

@("git", "mise", "node", "python", "uv", "pnpm") | ForEach-Object { Check-Required $_ }
@("codex", "claude", "hermes") | ForEach-Object { Check-Optional $_ }

Write-Host ""
Write-Host "-- repository safety --"

if (Get-Command git -ErrorAction SilentlyContinue) {
  $Tracked = @(& git ls-files)
  $Forbidden = @($Tracked | Where-Object {
    $_ -match '(^|/)(\.env(\..*)?|id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(pem|key|p12|pfx|kdbx))$'
  })
  if ($Forbidden.Count -gt 0) { Fail ("tracked credential-like files detected: " + ($Forbidden -join ", ")) }
  else { Pass "no tracked credential-like filenames" }

  $SecretFiles = @(& git grep -IlE '(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})' -- . 2>$null)
  if ($SecretFiles.Count -gt 0) { Fail ("possible secret material detected in tracked files: " + ($SecretFiles -join ", ")) }
  else { Pass "no common plaintext-secret signatures in tracked content" }
} else {
  Warn "repository safety checks skipped because git is unavailable"
}

@(
  "manifests/environment.json",
  "manifests/harnesses.json",
  "manifests/secrets.example.json",
  "dotfiles/gitconfig",
  "dotfiles/starship.toml",
  "scripts/project-windows.ps1"
) | ForEach-Object {
  if (Test-Path $_) { Pass "source:$_" } else { Fail "source:$_ missing" }
}

Write-Host ""
Write-Host "-- declarative state --"
if ($MiseExe) {
  $configCode = Invoke-MiseQuiet @("config")
  if ($configCode -eq 0) { Pass "mise configuration resolves" } else { Fail "mise configuration does not resolve" }

  $toolStateCode = Invoke-MiseQuiet @("install", "--dry-run-code")
  if ($toolStateCode -eq 0) { Pass "mise tool state converged" }
  elseif ($toolStateCode -eq 1 -and $AllowMissing) { Warn "mise reports missing configured tools" }
  elseif ($toolStateCode -eq 1) { Fail "mise reports missing configured tools" }
  else { Fail "mise tool-state probe failed with exit code $toolStateCode" }
} else {
  if ($AllowMissing) { Warn "mise state checks skipped" } else { Fail "mise unavailable" }
}

& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/project-windows.ps1" -Status *> $null
if ($LASTEXITCODE -eq 0) { Pass "Windows configuration projection converged" }
elseif ($AllowMissing) { Warn "Windows configuration projection is not fully applied" }
else { Fail "Windows configuration projection is not fully applied" }

Write-Host ""
Write-Host "summary: pass=$PassCount warn=$WarnCount fail=$FailCount"
if ($FailCount -gt 0) { exit 1 }
