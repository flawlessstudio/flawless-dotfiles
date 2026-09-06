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

function Test-MiseCommand([string]$Command) {
  if (-not $script:MiseExe) { return $false }
  & $script:MiseExe which $Command *> $null
  return ($LASTEXITCODE -eq 0)
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
  & $MiseExe config *> $null
  if ($LASTEXITCODE -eq 0) { Pass "mise configuration resolves" } else { Fail "mise configuration does not resolve" }

  & $MiseExe install --dry-run-code *> $null
  if ($LASTEXITCODE -eq 0) { Pass "mise tool state converged" }
  elseif ($AllowMissing) { Warn "mise reports missing configured tools" }
  else { Fail "mise reports missing configured tools" }
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
