$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$env:MISE_TRUSTED_CONFIG_PATHS = $Root

Write-Host "== PowerShell syntax validation =="
Get-ChildItem scripts -Filter *.ps1 | ForEach-Object {
  $file = $_.FullName
  $relative = "scripts/$($_.Name)"
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw ("PowerShell parse failure in {0}: {1}" -f $relative, $errors[0].Message) }
  Write-Host "PASS  $relative"
}

Write-Host ""
Write-Host "== manifest and Python validation =="
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  throw "python is required for final JSON/TOML/Python registry validation"
}

Get-ChildItem manifests -Filter *.json | ForEach-Object {
  & python -m json.tool $_.FullName *> $null
  if ($LASTEXITCODE -ne 0) { throw "Invalid JSON: $($_.Name)" }
  Write-Host "PASS  manifests/$($_.Name)"
}

& python -m py_compile scripts/sync-sources.py scripts/validate-registry.py
if ($LASTEXITCODE -ne 0) { throw "Python compile validation failed" }
Write-Host "PASS  Python scripts compile"

& python scripts/validate-registry.py
if ($LASTEXITCODE -ne 0) { throw "Final registry integrity validation failed" }

$TomlCheck = @'
import tomllib
for name in ("mise.toml", "mise.unix.toml", "mise.windows.toml", ".miserc.toml"):
    with open(name, "rb") as f:
        tomllib.load(f)
    print(f"PASS  {name}")
'@
$TomlCheck | & python -
if ($LASTEXITCODE -ne 0) { throw "TOML validation failed" }

Write-Host ""
Write-Host "== secret-safety validation =="
$Tracked = @(& git ls-files)
$Forbidden = @($Tracked | Where-Object {
  $_ -match '(^|/)(\.env(\..*)?|id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(pem|key|p12|pfx|kdbx))$'
})
if ($Forbidden.Count -gt 0) { throw ("Tracked credential-like files: " + ($Forbidden -join ", ")) }
Write-Host "PASS  no tracked credential-like filenames"

$SecretFiles = @(& git grep -IlE '(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})' -- . 2>$null)
if ($SecretFiles.Count -gt 0) { throw ("Possible secret material in: " + ($SecretFiles -join ", ")) }
Write-Host "PASS  no common plaintext-secret signatures"

Write-Host ""
Write-Host "== Windows projection dry-run =="
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/project-windows.ps1" -Plan
if ($LASTEXITCODE -ne 0) { throw "Windows projection plan failed" }
Write-Host "PASS  Windows projection plan"

Write-Host ""
Write-Host "== mise validation =="
$mise = Get-Command mise -ErrorAction SilentlyContinue
if ($mise) {
  $previous = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    & $mise.Source config *> $null
    $configCode = $LASTEXITCODE
    & $mise.Source install --dry-run *> $null
    $installCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($configCode -ne 0) { throw "mise config failed" }
  Write-Host "PASS  mise config"
  if ($installCode -ne 0) { throw "mise install --dry-run failed" }
  Write-Host "PASS  mise install --dry-run"
} else {
  Write-Warning "mise unavailable; runtime tool-plan validation skipped"
}
