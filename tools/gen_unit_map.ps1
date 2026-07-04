<#
.SYNOPSIS
  Export the game map.png (stage 3) from a hand master (stage 2) or raw AI image (stage 1).

.DESCRIPTION
  Given one or more skin_ids, looks up map_scale in unit_skin.csv, sets the figure
  height = BaseHeight * map_scale, and writes a 256px square, transparent, 64-color
  assets/units/<id>/<id>_map.png from source/<id>/<id>_02_master.png.
  If the 02_master is missing it falls back to the 01_raw (white bg auto-keyed;
  fringe is meant to be cleaned by hand in the 02_master later).
  Recipe of record: doc/art/visual-identity.md section 6.1. Requires ImageMagick (magick).
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1 files.

.EXAMPLE
  powershell -File tools\gen_unit_map.ps1 fighter
  powershell -File tools\gen_unit_map.ps1 fighter novice vanguard
  powershell -File tools\gen_unit_map.ps1 all
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$SkinIds        # one or more skin_ids, or 'all'. All positional args land here.
)
$ErrorActionPreference = 'Stop'
$BaseHeight = 200   # figure height (px) at map_scale=1.0. Baseline = fighter.
$Colors     = 64    # palette reduction color count
$Canvas     = 256   # output canvas (square)
$SkinIds = @($SkinIds)
if ($SkinIds.Count -eq 0) { throw "usage: gen_unit_map.ps1 <skin_id> [<skin_id> ...] | all" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here                  # parent of tools/ = repo root
$csv     = Join-Path $repo 'data\units\unit_skin.csv'
$srcRoot = Join-Path $repo 'assets\units\source'
$outRoot = Join-Path $repo 'assets\units'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

# Read map_scale. Row 1 = english keys (Import-Csv header); row 2 = JP labels, dropped by the numeric filter.
$scale = @{}
foreach ($r in (Import-Csv -Path $csv -Encoding UTF8)) {
  if ($r.map_scale -match '^[0-9.]+$') { $scale[$r.skin_id] = [double]$r.map_scale }
}

if ($SkinIds.Count -eq 1 -and $SkinIds[0] -eq 'all') { $SkinIds = @($scale.Keys) }

foreach ($id in $SkinIds) {
  $sc = if ($scale.ContainsKey($id)) { $scale[$id] } else { 1.0 }
  $h  = [int][math]::Round($BaseHeight * $sc)
  $master = Join-Path $srcRoot "$id\${id}_02_master.png"
  $raw    = Join-Path $srcRoot "$id\${id}_01_raw.png"
  $outDir = Join-Path $outRoot $id
  $out    = Join-Path $outDir "${id}_map.png"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  if (Test-Path $master) {
    # 02_master is already transparent: trim -> scale -> 256 square -> reduce colors
    magick $master -trim +repage -resize "x$h" -background none -gravity south -extent "${Canvas}x${Canvas}" -colors $Colors -dither None $out
    $srcKind = 'master'
  }
  elseif (Test-Path $raw) {
    # 01_raw is white-bg: key out the background via border floodfill, then same steps (provisional)
    magick $raw -fuzz 6% -trim +repage -alpha set -bordercolor white -border 1 -fuzz 14% -fill none -draw "alpha 0,0 floodfill" -shave 1x1 -resize "x$h" -background none -gravity south -extent "${Canvas}x${Canvas}" -colors $Colors -dither None $out
    $srcKind = 'raw(provisional)'
  }
  else {
    Write-Warning "${id}: no source (${id}_02_master.png / ${id}_01_raw.png) -> skipped"
    continue
  }
  $kb = [int]((Get-Item $out).Length / 1KB)
  Write-Output ("{0,-16} scale={1,-4} H={2,-4} src={3,-16} -> assets/units/{4}/{4}_map.png ({5}KB)" -f $id, $sc, $h, $srcKind, $id, $kb)
}
