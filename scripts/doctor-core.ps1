param(
  [switch]$AllowMissing,
  [string]$JsonOut
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$env:MISE_TRUSTED_CONFIG_PATHS = $Root

$Results = [System.Collections.Generic.List[object]]::new()

function Add-Result([string]$Id, [string]$Status, [string]$Detail) {
  $Results.Add([pscustomobject]@{ id = $Id; status = $Status; detail = $Detail })
  Write-Host ("{0,-5} {1}: {2}" -f $Status.ToUpperInvariant(), $Id, $Detail)
}

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

function Invoke-MiseQuiet([string[]]$Arguments) {
  if (-not $script:MiseExe) { return 127 }
  $previous = $ErrorActionPreference
  try {
    # Windows PowerShell 5 may surface native stderr/progress as a terminating
    # NativeCommandError. The native exit code is authoritative for probes.
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
  if (Get-Command $Command -ErrorAction SilentlyContinue) {
    Add-Result "command:$Command" "pass" "available on PATH"
  } elseif (Test-MiseCommand $Command) {
    Add-Result "command:$Command" "pass" "available through mise"
  } elseif ($AllowMissing) {
    Add-Result "command:$Command" "warn" "missing"
  } else {
    Add-Result "command:$Command" "fail" "missing"
  }
}

function Check-Optional([string]$Command) {
  if (Get-Command $Command -ErrorAction SilentlyContinue) {
    Add-Result "optional:$Command" "pass" "available on PATH"
  } elseif (Test-MiseCommand $Command) {
    Add-Result "optional:$Command" "pass" "available through mise"
  } else {
    Add-Result "optional:$Command" "warn" "not installed"
  }
}

foreach ($cmd in @("git", "mise", "node", "python", "uv", "pnpm")) { Check-Required $cmd }
foreach ($cmd in @("codex", "claude", "hermes")) { Check-Optional $cmd }

if (Get-Command git -ErrorAction SilentlyContinue) {
  $Tracked = @(& git ls-files)
  $Forbidden = @($Tracked | Where-Object { $_ -match '(^|/)(\.env(\..*)?|id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(pem|key|p12|pfx|kdbx))$' })
  if ($Forbidden.Count -gt 0) { Add-Result "security:filenames" "fail" ("credential-like tracked paths: " + ($Forbidden -join ", ")) }
  else { Add-Result "security:filenames" "pass" "no tracked credential-like filenames" }

  $SecretFiles = @(& git grep -IlE '(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})' -- . 2>$null)
  if ($SecretFiles.Count -gt 0) { Add-Result "security:content" "fail" ("possible secret material in: " + ($SecretFiles -join ", ")) }
  else { Add-Result "security:content" "pass" "no common plaintext-secret signatures" }
} else {
  Add-Result "security:repository" "warn" "git unavailable; repository safety checks skipped"
}

foreach ($file in @(
  "manifests/environment.json",
  "manifests/harnesses.json",
  "manifests/secrets.example.json",
  "manifests/sources.example.json",
  "manifests/sources.schema.json",
  "dotfiles/gitconfig",
  "dotfiles/starship.toml",
  "scripts/project-windows.ps1"
)) {
  if (Test-Path $file) { Add-Result "source:$file" "pass" "present" }
  else { Add-Result "source:$file" "fail" "missing" }
}

if ($MiseExe) {
  $configCode = Invoke-MiseQuiet @("config")
  if ($configCode -eq 0) { Add-Result "mise:config" "pass" "configuration resolves" }
  else { Add-Result "mise:config" "fail" "configuration resolution failed with exit $configCode" }

  $toolStateCode = Invoke-MiseQuiet @("install", "--dry-run-code")
  if ($toolStateCode -eq 0) { Add-Result "mise:tools" "pass" "configured tool state converged" }
  elseif ($toolStateCode -eq 1 -and $AllowMissing) { Add-Result "mise:tools" "warn" "configured tool state incomplete" }
  elseif ($toolStateCode -eq 1) { Add-Result "mise:tools" "fail" "configured tool state incomplete" }
  else { Add-Result "mise:tools" "fail" "tool-state probe failed with exit $toolStateCode" }
} elseif ($AllowMissing) {
  Add-Result "mise" "warn" "unavailable"
} else {
  Add-Result "mise" "fail" "unavailable"
}

$previous = $ErrorActionPreference
try {
  $ErrorActionPreference = "Continue"
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/project-windows.ps1" -Status *> $null
  $projectionCode = [int]$LASTEXITCODE
} catch {
  if ($LASTEXITCODE -is [int]) { $projectionCode = [int]$LASTEXITCODE } else { $projectionCode = 2 }
} finally {
  $ErrorActionPreference = $previous
}
if ($projectionCode -eq 0) { Add-Result "projection:windows" "pass" "converged" }
elseif ($AllowMissing) { Add-Result "projection:windows" "warn" "not fully applied (exit $projectionCode)" }
else { Add-Result "projection:windows" "fail" "not fully applied (exit $projectionCode)" }

$Summary = [pscustomobject]@{
  schema_version = 1
  generated_at_utc = [DateTime]::UtcNow.ToString("o")
  root = $Root
  results = @($Results)
  pass = @($Results | Where-Object status -eq "pass").Count
  warn = @($Results | Where-Object status -eq "warn").Count
  fail = @($Results | Where-Object status -eq "fail").Count
}

if ($JsonOut) {
  $parent = Split-Path -Parent $JsonOut
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $Summary | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -Path $JsonOut
}

Write-Host "summary: pass=$($Summary.pass) warn=$($Summary.warn) fail=$($Summary.fail)"
if ($Summary.fail -gt 0) { exit 1 }
