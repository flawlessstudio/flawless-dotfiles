param(
  [switch]$AllowMissing,
  [string]$JsonOut
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$Root/scripts/doctor-core.ps1")
if ($AllowMissing) { $argsList += "-AllowMissing" }
if ($JsonOut) { $argsList += @("-JsonOut", $JsonOut) }

& powershell @argsList
exit $LASTEXITCODE
