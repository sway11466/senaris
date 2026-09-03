<#
.SYNOPSIS
  Export the game UI icons from generated raws (key out the flat background, trim, downscale).

.DESCRIPTION
  For one or more icon ids (or 'all'), reads assets/icons-src/<group>/<id>/<id>_01_raw.(png|jpg)
  and writes assets/icons/<group>/<id>.png: turn the flat single-color background into alpha,
  trim the transparent margins, then fit inside a fixed square box. Alpha kept, no color
  reduction, no color adjustment (the look belongs to the generated art).
  A hand-made master (<id>_03_master.png, already transparent) wins over the raw when present:
  drop one in whenever the automatic key-out is not good enough for that icon.
  The alpha comes from luminance (dark background -> transparent). Icons are drawn as a bright
  mark on pure black, so a low threshold with a short ramp keeps the edge from stair-stepping.
  Recipe of record: doc/art/icons.md. Requires ImageMagick (magick).
  NOTE: keep this file ASCII-only (PowerShell 5.1).

.EXAMPLE
  powershell -File tools\gen_icon.ps1 charge
  powershell -File tools\gen_icon.ps1 charge guard raid
  powershell -File tools\gen_icon.ps1 all
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$IconIds        # one or more icon ids, or 'all'.
)
$ErrorActionPreference = 'Stop'
$Box = 128        # longest side of the trimmed icon (px). On screen it is about 36.
$Low = 6          # percent: below this luminance the pixel is fully transparent
$High = 20        # percent: above this luminance the pixel is fully opaque

$IconIds = @($IconIds)
if ($IconIds.Count -eq 0) { throw "usage: gen_icon.ps1 <icon_id> [<icon_id> ...] | all" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$srcRoot = Join-Path $repo 'assets\icons-src'
$outRoot = Join-Path $repo 'assets\icons'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

# Icon folders are assets/icons-src/<group>/<id>/ ; the group becomes assets/icons/<group>/.
$dirs = Get-ChildItem -Path $srcRoot -Directory -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.Parent.FullName -ne $srcRoot }
if ($IconIds.Count -eq 1 -and $IconIds[0] -eq 'all') {
  $IconIds = $dirs | ForEach-Object { $_.Name } | Sort-Object
}

foreach ($id in $IconIds) {
  $dir = $dirs | Where-Object { $_.Name -eq $id } | Select-Object -First 1
  if (-not $dir) {
    Write-Warning "${id}: no folder under assets/icons-src -> skipped"
    continue
  }
  $group = $dir.Parent.Name
  $master = Join-Path $dir.FullName "${id}_03_master.png"
  $src = $null
  foreach ($cand in @($master, (Join-Path $dir.FullName "${id}_01_raw.png"), (Join-Path $dir.FullName "${id}_01_raw.jpg"))) {
    if (Test-Path $cand) { $src = $cand; break }
  }
  if (-not $src) {
    Write-Warning "${id}: no ${id}_01_raw.(png|jpg) nor ${id}_03_master.png -> skipped"
    continue
  }
  $outDir = Join-Path $outRoot $group
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  $out = Join-Path $outDir "${id}.png"

  if ($src -eq $master) {
    # Already transparent: trim and fit only.
    magick $src -trim +repage -resize "${Box}x${Box}" -background none -gravity center $out
  } else {
    # Luminance -> alpha, then trim and fit.
    # The parens are magick's own grouping, so quote them (PowerShell would take them as code).
    magick $src `
      '(' -clone 0 -colorspace gray -level "${Low}%,${High}%" ')' `
      -alpha off -compose CopyOpacity -composite `
      -trim +repage -resize "${Box}x${Box}" -background none -gravity center $out
  }

  $size = magick identify -format "%wx%h" $out
  $from = if ($src -eq $master) { 'master' } else { 'raw' }
  Write-Host ("{0,-10} {1,-7} -> assets/icons/{2}/{3}.png  {4}" -f $id, $from, $group, $id, $size)
}
