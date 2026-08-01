<#
.SYNOPSIS
  Export the game attack-effect images from hand masters (trim + downscale, keep alpha).

.DESCRIPTION
  For one or more effect_ids (or 'all'), reads effects-src/<id>/<id>_03_master.png
  and writes assets/effects/<id>.png: trim transparent margins, then fit inside a
  fixed square box. Alpha kept, no color reduction.
  Unlike the unit slots, NO padding is baked in: the effect art is trimmed tight so
  every pixel is art, and the on-screen size comes from the 'scale' column of
  data/effects/combat_effect.csv at draw time. Baking the size into padding here
  would throw away resolution for no gain, because the combat scene sizes effects
  by width against the figure box.
  Only ids whose master exists are written. Recipe of record: doc/art/units.md 3.4.
  Requires ImageMagick (magick). NOTE: keep this file ASCII-only (PowerShell 5.1).

.EXAMPLE
  powershell -File tools\gen_effect.ps1 slash_s
  powershell -File tools\gen_effect.ps1 slash_s slash_m arrow
  powershell -File tools\gen_effect.ps1 all
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$EffectIds      # one or more effect_ids, or 'all'.
)
$ErrorActionPreference = 'Stop'
$Box = 512   # longest side of the trimmed art (px). Display size comes from the csv 'scale'.

$EffectIds = @($EffectIds)
if ($EffectIds.Count -eq 0) { throw "usage: gen_effect.ps1 <effect_id> [<effect_id> ...] | all" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$csv     = Join-Path $repo 'data\effects\combat_effect.csv'
$srcRoot = Join-Path $repo 'assets\effects-src'
$outRoot = Join-Path $repo 'assets\effects'

# Read the catalog just to warn about ids the game does not know (typo guard).
$known = @{}
foreach ($r in (Import-Csv -Path $csv -Encoding UTF8)) {
  if ($r.effect_id -and $r.effect_id -ne 'エフェクトID') { $known[$r.effect_id] = $true }
}

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

if ($EffectIds.Count -eq 1 -and $EffectIds[0] -eq 'all') {
  $EffectIds = Get-ChildItem -Path $srcRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name)_03_master.png") } |
    ForEach-Object { $_.Name } | Sort-Object
}

foreach ($id in $EffectIds) {
  $master = Join-Path (Join-Path $srcRoot $id) "${id}_03_master.png"
  if (-not (Test-Path $master)) {
    Write-Warning "${id}: no master (${id}_03_master.png) -> skipped"
    continue
  }
  if (-not $known.ContainsKey($id)) {
    Write-Warning "${id}: not listed in data/effects/combat_effect.csv (the game will never load it)"
  }
  New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
  $out = Join-Path $outRoot "${id}.png"
  magick $master -trim +repage -resize "${Box}x${Box}>" -background none $out
  $wh = (magick $out -format "%wx%h" info:)
  $kb = [int]((Get-Item $out).Length / 1KB)
  Write-Output ("{0,-10} {1,-10} -> assets/effects/{0}.png ({2}KB)" -f $id, $wh, $kb)
}
