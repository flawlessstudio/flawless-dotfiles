param(
  [switch]$AllowMissing
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$PassCount = 0
$WarnCount = 0
$FailCount = 0

function Pass([string]$Message) { Write-Host "PASS  $Message"; $script:PassCount++ }
function Warn([string]$Message) { Write-Warning $Message; $script:WarnCount++ }
function Fail([string]$Message) { Write-Host "FAIL  $Message" -ForegroundColor Red; $script:FailCount++ }

function Check-Required([string]$Command) {
  if (Get-Command $Command -ErrorAction SilentlyContinue) { Pass "command:$Command" }
  elseif ($AllowMissing) { Warn "command:$Command missing" }
  else { Fail "command:$Command missing" }
}

function Check-Optional([string]$Command) {
  if (Get-Command $Command -ErrorAction SilentlyContinue) { Pass "optional:$Command available" }
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
  if ($Forbidden.Count -gt 0) {
    Fail ("tracked credential-like files detected: " + ($Forbidden -join ", "))
  } else {
    Pass "no tracked credential-like filenames"
  }

  $SecretFiles = @(& git grep -IlE '(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})' -- . 2>$null)
  if ($SecretFiles.Count -gt 0) {
    Fail ("possible secret material detected in tracked files: " + ($SecretFiles -join ", "))
  } else {
    Pass "no common plaintext-secret signatures in tracked content"
  }
} else {
  Warn "repository safety checks skipped because git is unavailable"
}

@(
  "manifests/environment.json",
  "manifests/harnesses.json",
  "manifests/secrets.example.json",
  "dotfiles/gitconfig",
  "dotfiles/starship.toml"
) | ForEach-Object {
  if (Test-Path $_) { Pass "source:$_" } else { Fail "source:$_ missing" }
}

Write-Host ""
Write-Host "-- declarative state --"
if (Get-Command mise -ErrorAction SilentlyContinue) {
  & mise config *> $null
  if ($LASTEXITCODE -eq 0) { Pass "mise configuration resolves" } else { Fail "mise configuration does not resolve" }

  & mise bootstrap status --missing *> $null
  if ($LASTEXITCODE -eq 0) { Pass "mise desired state converged" }
  elseif ($AllowMissing) { Warn "mise reports missing/unapplied desired state" }
  else { Fail "mise reports missing/unapplied desired state" }
} else {
  Warn "mise state checks skipped"
}

Write-Host ""
Write-Host "summary: pass=$PassCount warn=$WarnCount fail=$FailCount"
if ($FailCount -gt 0) { exit 1 }
