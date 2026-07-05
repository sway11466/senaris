<#
.SYNOPSIS
  Clip source art image(s) into flat-top hex terrain tiles for the board.

.DESCRIPTION
  Given a terrain name and one or more source images, resizes each to cover the
  256x222 tile (2R wide, ceil(sqrt3*R) tall; R=128), center-crops, and masks it
  to a flat-top hexagon (transparent corners) so hexes tessellate cleanly.
  Writes assets/terrain/<name>.png for the first source and <name>_2.png,
  <name>_3.png ... for the rest (the board picks a variant per hex; see
  presentation/board/hex_board.gd _load_terrain_variants). Drop-in: terrain.csv
  / JSON are NOT touched. Placeholder recipe of record: tools/gen_terrain_tiles.gd;
  art spec: doc/art/terrain.md. Requires ImageMagick (magick).
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -File tools\gen_terrain_tile.ps1 plain art\plain_a.png
  powershell -File tools\gen_terrain_tile.ps1 plain art\p1.png art\p2.png art\p3.png
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Name,                                  # terrain id / file stem, e.g. 'plain'
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [string[]]$Sources                              # one or more source images (variant order)
)
$ErrorActionPreference = 'Stop'
$W = 256                # tile width  = 2R
$H = 222               # tile height = ceil(sqrt3 * R), R=128
$Colors = 64           # palette reduction (match unit tiles)

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$outDir = Join-Path $repo 'assets\terrain'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Flat-top hexagon points on the 256x222 canvas (center 128,111; R=128; half-h=110.85).
$hex = "polygon 256,111 192,221.85 64,221.85 0,111 64,0.15 192,0.15"

$i = 0
foreach ($src in $Sources) {
  if (-not (Test-Path $src)) { Write-Warning "missing source: $src -> skipped"; continue }
  $i++
  $suffix = if ($i -eq 1) { "" } else { "_$i" }
  $out = Join-Path $outDir ("{0}{1}.png" -f $Name, $suffix)
  # cover-resize -> center-crop -> hex alpha mask (DstIn) -> reduce colors
  magick $src -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" `
    "(" -size "${W}x${H}" xc:none -fill white -draw $hex ")" `
    -alpha set -compose DstIn -composite -colors $Colors -dither None $out
  $kb = [int]((Get-Item $out).Length / 1KB)
  Write-Output ("{0,-14} <- {1,-28} -> assets/terrain/{2}{3}.png ({4}KB)" -f $Name, (Split-Path $src -Leaf), $Name, $suffix, $kb)
}
