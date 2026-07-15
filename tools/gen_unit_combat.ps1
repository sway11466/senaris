<#
.SYNOPSIS
  Export the game combat images from hand masters (plan A: trim + downscale, keep alpha).

.DESCRIPTION
  For one or more skin_ids (or 'all'), reads the combat-slot masters
  units-src/<group>/<id>/<id>_<slot>_03_master.png (slot = combat, combat_hero,
  combat_effect) and writes assets/units/<id>/<id>_<slot>.png: trim transparent
  margins, downscale so the long side is <= 512px (never upscale), alpha kept.
  No 256 canvas and no color reduction (unlike the map slot) -- the combat scene
  scales with KEEP_ASPECT. <group> is a faction folder; the source dir is found by
  searching assets/units-src/ recursively for a folder named <id>.
  Only slots whose master exists are written. Recipe of record: doc/art/units.md 3.3.
  Requires ImageMagick (magick). NOTE: keep this file ASCII-only (PowerShell 5.1).

.EXAMPLE
  powershell -File tools\gen_unit_combat.ps1 fighter
  powershell -File tools\gen_unit_combat.ps1 fighter goblin
  powershell -File tools\gen_unit_combat.ps1 all
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$SkinIds        # one or more skin_ids, or 'all'.
)
$ErrorActionPreference = 'Stop'
$LongSide = 512             # output long-side cap (px). Only downscales.
$Slots    = @('combat', 'combat_hero', 'combat_effect')
$SkinIds = @($SkinIds)
if ($SkinIds.Count -eq 0) { throw "usage: gen_unit_combat.ps1 <skin_id> [<skin_id> ...] | all" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$srcRoot = Join-Path $repo 'assets\units-src'
$outRoot = Join-Path $repo 'assets\units'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

if ($SkinIds.Count -eq 1 -and $SkinIds[0] -eq 'all') {
  $SkinIds = Get-ChildItem -Path $srcRoot -Directory -Recurse |
    Where-Object { Get-ChildItem $_.FullName -Filter "*_combat*_master.png" -ErrorAction SilentlyContinue } |
    ForEach-Object { $_.Name } | Sort-Object -Unique
}

foreach ($id in $SkinIds) {
  # source dir = the folder named <id> that holds a combat master.
  $srcDir = Join-Path $srcRoot $id
  $hit = Get-ChildItem -Path $srcRoot -Directory -Recurse |
    Where-Object { $_.Name -eq $id -and (Get-ChildItem $_.FullName -Filter "*_combat*_master.png" -ErrorAction SilentlyContinue) } |
    Select-Object -First 1
  if ($hit) { $srcDir = $hit.FullName }
  $outDir = Join-Path $outRoot $id
  $any = $false
  foreach ($slot in $Slots) {
    # master = hand-final. Named _03_master (skip dew but keep master=03). Fall back to _02_master.
    $master = Join-Path $srcDir "${id}_${slot}_03_master.png"
    if (-not (Test-Path $master)) { $master = Join-Path $srcDir "${id}_${slot}_02_master.png" }
    if (-not (Test-Path $master)) { continue }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $out = Join-Path $outDir "${id}_${slot}.png"
    magick $master -trim +repage -background none -resize "${LongSide}x${LongSide}>" $out
    $kb = [int]((Get-Item $out).Length / 1KB)
    Write-Output ("{0,-16} {1,-14} -> assets/units/{2}/{2}_{1}.png ({3}KB)" -f $id, $slot, $id, $kb)
    $any = $true
  }
  if (-not $any) { Write-Warning "${id}: no combat master (${id}_combat_03_master.png ...) -> skipped" }
}
