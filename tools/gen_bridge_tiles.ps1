<#
.SYNOPSIS
  Build the 12 bridge tiles (4 width roles x 3 axes) from TWO source images:
  one deck texture and one parapet (railing) strip.

.DESCRIPTION
  A bridge is an object placed flat (terrain_skin.csv placement=flat): the board
  lays the tile art as a horizontal hex plate at the bridge's own height, while
  the river underneath stays at its absolute water level. The tile art is a
  straight band of deck the same width as the road band (see -Bite), with the
  parapet running along the band's edges and everything outside the band
  transparent, so the water shows through beside a narrow bridge.

  Width roles (which sides carry a parapet), matching the skin ids in
  data/terrain/terrain_skin.csv:
    <name>_*        single width: parapet on BOTH edges
    <name>_left_*   left edge of a wide bridge: parapet on the LEFT only,
                    deck extended to the right edge of the hex
    <name>_right_*  right edge: parapet on the RIGHT only, deck to the left
    <name>_mid_*    middle: deck only, covering the whole hex
  Left and right are seen walking UP the axis on screen. Axes: _v runs straight
  up-down, _r upper-right to lower-left (+60 deg), _l upper-left to lower-right
  (-60 deg). Terrain art bakes in no light direction, so rotating the whole
  composition and mirroring the parapet are both allowed (doc/art/terrain.md).

  The DECK source is a full-frame stone texture seen from directly overhead;
  a pattern-free texture is safest, and if it has a grain, draw it up-down
  (the direction of travel). -DeckX/-DeckW pick the clean region to use (stay
  inside any drawn outline), like gen_area_tiles.ps1. The RAIL source is a
  HORIZONTAL strip of parapet seen from directly overhead, the outer face of
  the parapet at the TOP of the strip; -RailX/-RailY/-RailW/-RailH pick the
  strip. It is rotated upright, scaled to -RailTileW px and repeated along the
  band edge.

  -CombatFront copies a finished near-view parapet band (drawn separately by
  the owner) to <skin>_combat_front.png for all 12 skins, which is what the
  combat scene overlays in front of the front rank (doc/tech/combat_scene.md).

  Output: assets/terrain/<name>[_left|_right|_mid]_[v|r|l].png, 256x222 flat-top
  hex tiles. Drop-in: terrain_skin.csv is NOT touched. Art spec:
  doc/art/terrain.md section 3.7. Requires ImageMagick (magick).
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -File tools\gen_bridge_tiles.ps1 river_bridge_stone1 `
    -Deck assets\terrain-src\bridge_stone1\bridge_stone1_floor_01_raw.png `
    -DeckX 260 -DeckW 500 `
    -Rail assets\terrain-src\bridge_stone1\bridge_stone1_rail_01_raw.png `
    -RailX 0 -RailY 420 -RailW 1000 -RailH 120
#>
param(
  [Parameter(Mandatory = $true)][string]$Name,   # skin family, e.g. 'river_bridge_stone1'
  [Parameter(Mandatory = $true)][string]$Deck,   # deck texture source
  [Parameter(Mandatory = $true)][int]$DeckX,     # source X of the clean deck region
  [Parameter(Mandatory = $true)][int]$DeckW,     # its width. Stay inside any drawn outline.
  [int]$DeckY = 0,                               # source Y of that region
  [int]$DeckH = 0,                               # its height (0 = down to the bottom)
  [Parameter(Mandatory = $true)][string]$Rail,   # parapet strip source (horizontal band)
  [Parameter(Mandatory = $true)][int]$RailX,     # source rectangle of the strip
  [Parameter(Mandatory = $true)][int]$RailY,
  [Parameter(Mandatory = $true)][int]$RailW,
  [Parameter(Mandatory = $true)][int]$RailH,
  [int]$RailTileW = 14,                          # parapet width on the tile, px (256px tile)
  [int]$Bite = 46,                               # px eaten in from an edge midpoint; sets the band
                                                 # width. 46 = the road band, so road and bridge meet
  [string]$CombatFront = ''                      # finished combat-front band to copy per skin, '' = skip
)
$ErrorActionPreference = 'Stop'
$W = 256                 # tile width  = 2R
$H = 222                 # tile height = ceil(sqrt3 * R), R=128
$APOTHEM = 110.85        # hex centre -> edge midpoint. Same for all six edges.
$Colors = 64             # palette reduction (match the other terrain tiles)
$SQ = 256                # square work canvas so the art can be rotated about (128,128)
$CX = 128.0

# role suffix -> which band edges carry a parapet / how far the deck reaches
$ROLES = [ordered]@{ '' = 'both'; '_left' = 'left'; '_right' = 'right'; '_mid' = 'none' }
# axis suffix -> rotation of the whole composition, degrees clockwise.
# +60 turns the up-down band to run upper-right/lower-left (_r), -60 the other way (_l).
$AXES = [ordered]@{ '_v' = 0; '_r' = 60; '_l' = -60 }

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$outDir = Join-Path $repo 'assets\terrain'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (-not [System.IO.Path]::IsPathRooted($Deck)) { $Deck = Join-Path $repo $Deck }
if (-not [System.IO.Path]::IsPathRooted($Rail)) { $Rail = Join-Path $repo $Rail }
if (-not (Test-Path $Deck)) { throw "deck source not found: $Deck" }
if (-not (Test-Path $Rail)) { throw "rail source not found: $Rail" }
if ($CombatFront -ne '') {
  if (-not [System.IO.Path]::IsPathRooted($CombatFront)) { $CombatFront = Join-Path $repo $CombatFront }
  if (-not (Test-Path $CombatFront)) { throw "combat front source not found: $CombatFront" }
}

$halfW = $APOTHEM - $Bite
if ($halfW -le 0) { throw "-Bite must be smaller than $APOTHEM" }
if ($halfW -lt (128.0 / 2)) {
  Write-Warning ("-Bite {0} leaves a {1:N1}px band, under the 128px hex edge: the deck will not cover a connected edge end to end" -f $Bite, (2 * $halfW))
}
if ($RailTileW -ge $halfW) { throw "-RailTileW must be smaller than the band half-width ($halfW px)" }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("bridge_tiles_" + $Name)
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$hexPoly = "polygon 256,111 192,221.85 64,221.85 0,111 64,0.15 192,0.15"
$baseY = [int](($SQ - $H) / 2)   # centre the 256x222 tile in the square work canvas

# 1. Deck texture covering the whole square canvas (grain up-down, as drawn).
if ($DeckH -le 0) {
  $srcH = [int](& magick $Deck -format '%h' info:)
  $DeckH = $srcH - $DeckY
}
$deckFull = Join-Path $work 'deck.png'
& magick $Deck -crop ("{0}x{1}+{2}+{3}" -f $DeckW, $DeckH, $DeckX, $DeckY) +repage `
  -resize "${SQ}x${SQ}^" -gravity center -extent "${SQ}x${SQ}" $deckFull

# 2. The parapet, upright. The strip is drawn horizontally with the OUTER face at
#    the top, so -rotate -90 stands it up with the outer face on the LEFT; the
#    right-hand parapet is the same strip mirrored (no baked light direction).
$railV = Join-Path $work 'rail_v.png'
& magick $Rail -crop ("{0}x{1}+{2}+{3}" -f $RailW, $RailH, $RailX, $RailY) +repage `
  -rotate -90 -resize "${RailTileW}x" -write mpr:rail +delete `
  -size "${RailTileW}x${SQ}" tile:mpr:rail $railV
$railR = Join-Path $work 'rail_r.png'
& magick $railV -flop $railR

# 3. One upright composition per role, then rotate per axis, crop, hex-mask.
$leftX = [int][math]::Round($CX - $halfW)
$rightX = [int][math]::Round($CX + $halfW)
$made = 0
foreach ($role in $ROLES.Keys) {
  $kind = $ROLES[$role]
  # deck coverage: the band, extended to the hex edge on the parapet-free side(s)
  $x0 = if ($kind -eq 'right' -or $kind -eq 'none') { 0 } else { $leftX }
  $x1 = if ($kind -eq 'left' -or $kind -eq 'none') { $SQ } else { $rightX }
  $mask = Join-Path $work ("mask{0}.png" -f $role)
  & magick -size "${SQ}x${SQ}" xc:black -fill white `
    -draw ("rectangle {0},0 {1},{2}" -f $x0, $x1, $SQ) -alpha off -colorspace gray $mask
  $rails = @()
  if ($kind -eq 'both' -or $kind -eq 'left') {
    $rails += @($railV, '-geometry', ("+{0}+0" -f $leftX), '-composite')
  }
  if ($kind -eq 'both' -or $kind -eq 'right') {
    $rails += @($railR, '-geometry', ("+{0}+0" -f ($rightX - $RailTileW)), '-composite')
  }
  $upright = Join-Path $work ("upright{0}.png" -f $role)
  $args = @($deckFull, '-alpha', 'off', $mask, '-compose', 'CopyOpacity', '-composite',
    '-compose', 'Over') + $rails + @($upright)
  & magick @args
  foreach ($axis in $AXES.Keys) {
    $out = Join-Path $outDir ("{0}{1}{2}.png" -f $Name, $role, $axis)
    & magick $upright -background none `
      -distort SRT ("{0},{0} 1 {1} {0},{0}" -f ($SQ / 2), $AXES[$axis]) +repage `
      -crop "${W}x${H}+0+$baseY" +repage `
      "(" -size "${W}x${H}" xc:none -fill white -draw $hexPoly ")" `
      -alpha set -compose DstIn -composite -colors $Colors -dither None $out
    $made++
    if ($CombatFront -ne '') {
      Copy-Item $CombatFront (Join-Path $outDir ("{0}{1}{2}_combat_front.png" -f $Name, $role, $axis)) -Force
    }
  }
}
Remove-Item -Recurse -Force $work

Write-Output ("{0}: bite {1} -> band {2:N1}px, rail {3}px, {4} tiles{5}" -f `
  $Name, $Bite, (2 * $halfW), $RailTileW, $made, $(if ($CombatFront -ne '') { " + combat fronts" } else { "" }))
