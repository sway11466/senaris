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

  Two switches serve art that is an OBJECT sitting on ground rather than a
  full-frame texture (a garden plot, a building):

  -Transparent <colour> drops the background so the board can draw its own
  ground underneath (terrain_skin.csv map_ground; see doc/art/terrain.md 3.6).
  Generate the art on a flat pure background and name that colour here.

  -Fit centres the remaining art and pads the canvas until the art fits inside
  the hexagon AT ANY ROTATION. The board rotates tiles whose skin is orientable,
  and the hexagon is 110.85px from centre to an edge but 128px to a vertex, so
  art that clears the vertices can still be clipped by the edges. -Fit sizes the
  art by its half-diagonal, which is what a rotation sweeps, so the same source
  gives the same result at 0 and at 60 degrees. It also normalises size: every
  variant comes out at the same scale whatever margin the generator left.

.EXAMPLE
  powershell -File tools\gen_terrain_tile.ps1 plain art\plain_a.png
  powershell -File tools\gen_terrain_tile.ps1 plain art\p1.png art\p2.png art\p3.png
  powershell -File tools\gen_terrain_tile.ps1 bush_garden1 `
    assets\terrain-src\bush_garden1\bush_garden1_01_raw.png -Transparent white -Fit
#>
# PositionalBinding is off so that the optional switches below cannot swallow a source path:
# with the default binding, -Transparent would claim position 1 and Sources would come up empty.
[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Name,                                  # terrain id / file stem, e.g. 'plain'
  [switch]$Upright,                               # pre-stretch for the camera pitch (see $Stretch)
  [string]$Transparent = '',                      # background colour to drop, e.g. 'white'. '' = keep it
  [int]$Fuzz = 10,                                # tolerance for -Transparent, percent
  [switch]$Fit,                                   # centre the art and pad so it fits the hexagon when rotated
  [double]$FitMargin = 0.94,                      # share of the apothem the art's half-diagonal may reach
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [string[]]$Sources                              # one or more source images (variant order)
)
$ErrorActionPreference = 'Stop'
$W = 256                # tile width  = 2R
$H = 222               # tile height = ceil(sqrt3 * R), R=128
$APOTHEM = 110.85      # hex centre -> edge midpoint. The limit a rotating tile must clear.
$Colors = 64           # palette reduction (match unit tiles)
# The board camera looks down at CAM_PITCH_DEG=52 (presentation/board/hex_board_3d.gd), so a tile
# lying on the ground is squashed to sin(52)=0.788 of its height on screen. -Upright pre-stretches
# the art vertically by 1/sin(52) so it appears in its drawn proportions. Use it for art with a
# known shape (buildings); natural textures have no correct proportion and do not need it.
$Stretch = [int][math]::Round($H / [math]::Sin(52 * [math]::PI / 180))

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}
if ($FitMargin -le 0 -or $FitMargin -gt 1) { throw "-FitMargin must be in (0,1]" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$outDir = Join-Path $repo 'assets\terrain'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("terrain_tile_" + $Name)
New-Item -ItemType Directory -Force -Path $work | Out-Null

# Flat-top hexagon points on the 256x222 canvas (center 128,111; R=128; half-h=110.85).
$hex = "polygon 256,111 192,221.85 64,221.85 0,111 64,0.15 192,0.15"

$i = 0
foreach ($src in $Sources) {
  if (-not (Test-Path $src)) { Write-Warning "missing source: $src -> skipped"; continue }
  $i++
  $suffix = if ($i -eq 1) { "" } else { "_$i" }
  $out = Join-Path $outDir ("{0}{1}.png" -f $Name, $suffix)
  $note = ""

  # -Transparent: drop the flat background the art was drawn on.
  $stage = $src
  if ($Transparent -ne '') {
    $keyed = Join-Path $work ("keyed_{0}.png" -f $i)
    & magick $stage -fuzz "$Fuzz%" -transparent $Transparent $keyed
    $stage = $keyed
  }

  # -Fit: trim to the art, then pad to a square big enough that the art's half-diagonal
  # lands inside the apothem once the square has been cover-resized to the tile.
  # A square canvas of N scales by W/N, so the half-diagonal becomes hypot(w,h)/2 * W/N,
  # and we want that <= APOTHEM * FitMargin. N is therefore hypot(w,h) * (W/2) / limit.
  if ($Fit) {
    $dim = (& magick $stage -trim -format "%w %h" info:) -split '\s+'
    $cw = [double]$dim[0]; $ch = [double]$dim[1]
    $limit = $APOTHEM * $FitMargin
    $n = [int][math]::Ceiling([math]::Sqrt($cw * $cw + $ch * $ch) * ($W / 2.0) / $limit)
    $fitted = Join-Path $work ("fitted_{0}.png" -f $i)
    & magick $stage -trim +repage -background none -gravity center -extent "${n}x${n}" $fitted
    $stage = $fitted
    $note = " [fit {0}x{1} -> {2}sq]" -f [int]$cw, [int]$ch, $n
  }

  # cover-resize -> center-crop -> [-Upright: stretch tall, crop back] -> hex alpha mask -> colors
  # -background none is required, not cosmetic: -extent composites onto the background colour, so
  # with the default white it fills any transparency the art has (from -Transparent) with opaque white.
  $pre = @('-background', 'none', '-resize', "${W}x${H}^", '-gravity', 'center', '-extent', "${W}x${H}")
  if ($Upright) {
    $pre += @('-resize', "${W}x${Stretch}!", '-gravity', 'center', '-extent', "${W}x${H}")
  }
  magick $stage @pre `
    "(" -size "${W}x${H}" xc:none -fill white -draw $hex ")" `
    -alpha set -compose DstIn -composite -colors $Colors -dither None $out
  $kb = [int]((Get-Item $out).Length / 1KB)
  Write-Output ("{0,-14} <- {1,-28} -> assets/terrain/{2}{3}.png ({4}KB){5}" -f $Name, (Split-Path $src -Leaf), $Name, $suffix, $kb, $note)
}
