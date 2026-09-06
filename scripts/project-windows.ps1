param(
  [switch]$Plan,
  [switch]$Apply,
  [switch]$Status,
  [switch]$Unapply
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$Modes = @($Plan, $Apply, $Status, $Unapply) | Where-Object { $_ }
if ($Modes.Count -gt 1) { throw "Choose exactly one of -Plan, -Apply, -Status, or -Unapply." }
if ($Modes.Count -eq 0) { $Status = $true }

$HomeDir = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath("UserProfile") }
if (-not $HomeDir) { throw "Unable to resolve the user home directory." }

$ManagedRoot = Join-Path $HomeDir ".config\flawless"
$GitConfig = Join-Path $HomeDir ".gitconfig"
$PwshProfile = Join-Path $HomeDir "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
$WindowsPowerShellProfile = Join-Path $HomeDir "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$GitSource = Join-Path $Root "dotfiles\gitconfig"
$StarshipSource = Join-Path $Root "dotfiles\starship.toml"
$ManagedGit = Join-Path $ManagedRoot "gitconfig"
$ManagedStarship = Join-Path $ManagedRoot "starship.toml"

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Ensure-Parent([string]$Path) {
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
}

function Read-Text([string]$Path) {
  if (-not (Test-Path $Path)) { return "" }
  return [IO.File]::ReadAllText($Path)
}

function Get-ExistingEncoding([string]$Path) {
  if (-not (Test-Path $Path)) { return $script:Utf8NoBom }
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    return New-Object System.Text.UTF8Encoding($true)
  }
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    return New-Object System.Text.UnicodeEncoding($false, $true)
  }
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
    return New-Object System.Text.UnicodeEncoding($true, $true)
  }
  return $script:Utf8NoBom
}

function Write-Text([string]$Path, [string]$Text) {
  Ensure-Parent $Path
  $encoding = Get-ExistingEncoding $Path
  [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function New-Block([string]$Id, [string]$Body, [string]$Newline) {
  $start = "# >>> flawless:$Id >>> managed by flawless-dotfiles; do not edit between markers"
  $end = "# <<< flawless:$Id <<<"
  return $start + $Newline + $Body.TrimEnd("`r", "`n") + $Newline + $end + $Newline
}

function Get-Newline([string]$Text) {
  if ($Text.Contains("`r`n")) { return "`r`n" }
  return "`n"
}

function Get-BlockState([string]$Path, [string]$Id, [string]$Body) {
  if (-not (Test-Path $Path)) { return "missing" }
  $text = Read-Text $Path
  $newline = Get-Newline $text
  $expected = New-Block $Id $Body $newline
  $start = "# >>> flawless:$Id >>> managed by flawless-dotfiles; do not edit between markers"
  $end = "# <<< flawless:$Id <<<"
  $startIndex = $text.IndexOf($start, [StringComparison]::Ordinal)
  if ($startIndex -lt 0) { return "missing" }
  $endIndex = $text.IndexOf($end, $startIndex, [StringComparison]::Ordinal)
  if ($endIndex -lt 0) { return "differs" }
  $afterEnd = $endIndex + $end.Length
  if ($afterEnd -lt $text.Length -and $text.Substring($afterEnd).StartsWith("`r`n")) { $afterEnd += 2 }
  elseif ($afterEnd -lt $text.Length -and $text[$afterEnd] -eq "`n") { $afterEnd += 1 }
  $actual = $text.Substring($startIndex, $afterEnd - $startIndex)
  if ($actual -eq $expected) { return "applied" }
  return "differs"
}

function Set-Block([string]$Path, [string]$Id, [string]$Body) {
  $text = Read-Text $Path
  $newline = Get-Newline $text
  $block = New-Block $Id $Body $newline
  $start = "# >>> flawless:$Id >>> managed by flawless-dotfiles; do not edit between markers"
  $end = "# <<< flawless:$Id <<<"
  $startIndex = $text.IndexOf($start, [StringComparison]::Ordinal)

  if ($startIndex -ge 0) {
    $endIndex = $text.IndexOf($end, $startIndex, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "Found start marker without end marker in $Path for $Id." }
    $afterEnd = $endIndex + $end.Length
    if ($afterEnd -lt $text.Length -and $text.Substring($afterEnd).StartsWith("`r`n")) { $afterEnd += 2 }
    elseif ($afterEnd -lt $text.Length -and $text[$afterEnd] -eq "`n") { $afterEnd += 1 }
    $text = $text.Substring(0, $startIndex) + $block + $text.Substring($afterEnd)
  } else {
    if ($text.Length -gt 0 -and -not ($text.EndsWith("`n") -or $text.EndsWith("`r"))) { $text += $newline }
    if ($text.Length -gt 0) { $text += $newline }
    $text += $block
  }
  Write-Text $Path $text
}

function Remove-Block([string]$Path, [string]$Id) {
  if (-not (Test-Path $Path)) { return }
  $text = Read-Text $Path
  $start = "# >>> flawless:$Id >>> managed by flawless-dotfiles; do not edit between markers"
  $end = "# <<< flawless:$Id <<<"
  $startIndex = $text.IndexOf($start, [StringComparison]::Ordinal)
  if ($startIndex -lt 0) { return }
  $endIndex = $text.IndexOf($end, $startIndex, [StringComparison]::Ordinal)
  if ($endIndex -lt 0) { throw "Refusing destructive rollback: start marker exists without end marker in $Path for $Id." }
  $afterEnd = $endIndex + $end.Length
  if ($afterEnd -lt $text.Length -and $text.Substring($afterEnd).StartsWith("`r`n")) { $afterEnd += 2 }
  elseif ($afterEnd -lt $text.Length -and $text[$afterEnd] -eq "`n") { $afterEnd += 1 }
  $before = $text.Substring(0, $startIndex).TrimEnd("`r", "`n")
  $after = $text.Substring($afterEnd).TrimStart("`r", "`n")
  $newline = Get-Newline $text
  $newText = $before
  if ($before.Length -gt 0 -and $after.Length -gt 0) { $newText += $newline + $newline }
  $newText += $after
  if ($newText.Length -gt 0) { $newText += $newline }
  Write-Text $Path $newText
}

function Get-CopyState([string]$Source, [string]$Target) {
  if (-not (Test-Path $Target)) { return "missing" }
  if ((Get-FileHash -Algorithm SHA256 $Source).Hash -eq (Get-FileHash -Algorithm SHA256 $Target).Hash) { return "applied" }
  return "differs"
}

function Apply-Copy([string]$Source, [string]$Target) {
  Ensure-Parent $Target
  Copy-Item -Force $Source $Target
}

function Remove-CopyConservatively([string]$Source, [string]$Target) {
  if (-not (Test-Path $Target)) { return }
  if ((Get-FileHash -Algorithm SHA256 $Source).Hash -eq (Get-FileHash -Algorithm SHA256 $Target).Hash) {
    Remove-Item -Force $Target
  } else {
    Write-Warning "Preserving modified managed file during unapply: $Target"
  }
}

$GitBody = @'
[include]
  path = ~/.config/flawless/gitconfig
'@

$ProfileBody = @'
$flawlessMiseShims = Join-Path $env:LOCALAPPDATA 'mise\shims'
if ((Test-Path $flawlessMiseShims) -and (($env:PATH -split ';') -notcontains $flawlessMiseShims)) {
  $env:PATH = "$flawlessMiseShims;$env:PATH"
}
$env:STARSHIP_CONFIG = Join-Path $env:USERPROFILE '.config\flawless\starship.toml'
'@

$Checks = @(
  @{ Kind = "copy"; Name = "managed-gitconfig"; Source = $GitSource; Target = $ManagedGit },
  @{ Kind = "copy"; Name = "managed-starship"; Source = $StarshipSource; Target = $ManagedStarship },
  @{ Kind = "block"; Name = "git-include"; Path = $GitConfig; Id = "gitconfig"; Body = $GitBody },
  @{ Kind = "block"; Name = "pwsh-profile"; Path = $PwshProfile; Id = "mise-shims"; Body = $ProfileBody },
  @{ Kind = "block"; Name = "powershell-profile"; Path = $WindowsPowerShellProfile; Id = "mise-shims"; Body = $ProfileBody }
)

function Get-CheckState($Check) {
  if ($Check.Kind -eq "copy") { return Get-CopyState $Check.Source $Check.Target }
  return Get-BlockState $Check.Path $Check.Id $Check.Body
}

if ($Plan -or $Status) {
  $notApplied = 0
  foreach ($check in $Checks) {
    $state = Get-CheckState $check
    Write-Host ("{0,-8} {1}" -f $state.ToUpperInvariant(), $check.Name)
    if ($state -ne "applied") { $notApplied++ }
  }
  if ($Status -and $notApplied -gt 0) { exit 1 }
  exit 0
}

if ($Apply) {
  foreach ($check in $Checks) {
    $state = Get-CheckState $check
    if ($state -eq "applied") {
      Write-Host "KEEP    $($check.Name)"
      continue
    }
    if ($check.Kind -eq "copy") { Apply-Copy $check.Source $check.Target }
    else { Set-Block $check.Path $check.Id $check.Body }
    Write-Host "APPLY   $($check.Name)"
  }
  & $PSCommandPath -Status
  exit $LASTEXITCODE
}

if ($Unapply) {
  foreach ($check in ($Checks | Select-Object -Reverse)) {
    if ($check.Kind -eq "copy") { Remove-CopyConservatively $check.Source $check.Target }
    else { Remove-Block $check.Path $check.Id }
    Write-Host "UNAPPLY $($check.Name)"
  }
  if ((Test-Path $ManagedRoot) -and -not (Get-ChildItem -Force $ManagedRoot | Select-Object -First 1)) {
    Remove-Item -Force $ManagedRoot
  }
  exit 0
}
