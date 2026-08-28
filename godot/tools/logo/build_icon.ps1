<#
.SYNOPSIS
  Build the application icon (PNG + ICO) from the icon SVGs.

.DESCRIPTION
  Two steps that must not drift apart:

    1. Rasterize assets/icon-src/icon_{small,large}.svg to every size Windows
       asks for (tools/logo/build_icon.gd). The small emblem is used at 48px and
       below, the seven-tile one from 64px up. This also writes the PNG that
       project.godot points at, and a preview strip on a dark and a light ground.
    2. Bundle those PNGs into assets/icon/icon.ico with ImageMagick. Godot can
       write PNG but not ICO, and Windows wants one file holding every size.

  The SVGs themselves come from tools/logo/build_logo.py. Run that first if the
  emblem changed. Spec: doc/art/icon.md.
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File godot\tools\logo\build_icon.ps1
  powershell -ExecutionPolicy Bypass -File godot\tools\logo\build_icon.ps1 -Godot "C:\path\to\Godot.exe"
#>

[CmdletBinding()]
param(
  # Godot editor binary. Defaults to $env:GODOT, then PATH, then a winget install.
  # The path is machine-specific and stays out of the repo.
  [string]$Godot = ''
)

$ErrorActionPreference = 'Stop'

function Find-Godot([string]$explicit) {
  foreach ($candidate in @($explicit, $env:GODOT)) {
    if ($candidate -and (Test-Path $candidate)) { return (Resolve-Path $candidate).Path }
  }
  $cmd = Get-Command 'godot' -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path $winget) {
    $hit = Get-ChildItem -Path $winget -Filter 'Godot_v*.exe' -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike '*console*' } |
      Sort-Object Name -Descending |
      Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  throw "Godot not found. Pass -Godot <path>, set `$env:GODOT, or add it to PATH."
}

# Repo root is three levels above godot/tools/logo/.
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$project = Join-Path $repo 'godot'
$pngDir = Join-Path $project 'assets\icon-src\png'
$ico = Join-Path $project 'assets\icon\icon.ico'
# Smallest first: Explorer reads the order as a hint when it picks an entry.
$sizes = 16, 24, 32, 48, 64, 128, 256

$godotExe = Find-Godot $Godot
$magick = Get-Command 'magick' -ErrorAction SilentlyContinue
if (-not $magick) { throw 'ImageMagick not found. Install it, or add magick to PATH.' }
Write-Host "Godot:   $godotExe"
Write-Host "Magick:  $($magick.Source)"

Write-Host ''
Write-Host '--- 1/2 rasterize ---'
# Piping is what makes PowerShell wait: the Godot binary is a GUI-subsystem exe,
# so calling it bare returns before it has run and leaves $LASTEXITCODE unset.
& $godotExe --headless --path $project --script res://tools/logo/build_icon.gd | Out-Host
if ($LASTEXITCODE -ne 0) { throw "build_icon.gd failed ($LASTEXITCODE)." }

Write-Host ''
Write-Host '--- 2/2 bundle ---'
$pngs = $sizes | ForEach-Object {
  $p = Join-Path $pngDir "icon_$($_).png"
  if (-not (Test-Path $p)) { throw "Missing $p." }
  $p
}
& $magick.Source @pngs $ico
if ($LASTEXITCODE -ne 0) { throw "magick failed ($LASTEXITCODE)." }
Write-Host "$ico ($([math]::Round((Get-Item $ico).Length / 1KB, 1)) KB)"
