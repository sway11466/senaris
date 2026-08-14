<#
.SYNOPSIS
  Build a full set of connecting hex tiles for an AREA terrain (a road, a river
  bed) from ONE source image, by masking a single full-coverage texture.

.DESCRIPTION
  An area terrain is ground, not a structure standing on ground. Cutting one arm
  out of the art and rotating it into six directions (tools/gen_connect_tiles.ps1)
  does not work here: where two arms overlap, the texture of one runs into the
  texture of the other and the mismatch reads as a straight seam. The only way
  to hide it is to flatten the art until there is no texture left to mismatch.

  So this script turns the construction round. The art is ONE full-tile texture,
  identical in all 64 pieces and never rotated or overlaid; only an alpha MASK
  changes from piece to piece. Where the mask says "not road" the neighbouring
  material (-Cut, plain grass by default) is laid over the top. Nothing is ever
  composited texture-on-texture, so there is no seam to hide and the source's
  mottling survives.

  The mask is a band of half-width (110.85 - Bite) reaching from the tile centre
  out to each CONNECTED edge, plus a disc of that radius at the centre to fill
  the inside of a bend. 110.85px is the distance from the hex centre to an edge
  midpoint, the same for all six edges. -Bite is therefore the one number that
  sets the band width: 46 gives a band of 129.7px, just over the 128px length of
  a hex edge, so a connected edge is covered end to end and neighbours always
  meet. Above 46.85 the band no longer reaches the hex corners and a fully
  surrounded tile (c111111) stops being solid ground.

  Output: assets/terrain/<name>_cBBBBBB.png, where each B is 1 if the tile
  connects in that direction, in Hex.DIRECTIONS order (domain/hex/hex.gd)
  = (1,0) (1,-1) (0,-1) (-1,0) (-1,1) (0,1). The straight north-south piece
  (001001) is also written as assets/terrain/<name>.png, which is what the board
  falls back to when a combination has no file. Drop-in: terrain_skin.csv is NOT
  touched apart from its connect column, and the board cannot tell this method
  from gen_connect_tiles.ps1. Art spec: doc/art/terrain.md section 3.3.
  Requires ImageMagick (magick).
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -File tools\gen_area_tiles.ps1 road `
    assets\terrain-src\road\road_01_raw.png -BandX 372 -BandW 276 -Bite 46
#>
param(
  [Parameter(Mandatory = $true)][string]$Name,   # skin id / file stem, e.g. 'road'
  [Parameter(Mandatory = $true)][string]$Source, # source art
  [Parameter(Mandatory = $true)][int]$BandX,     # source X of the clean texture to use
  [Parameter(Mandatory = $true)][int]$BandW,     # its width. Stay inside any drawn outline.
  [int]$BandY = 0,                               # source Y of that region
  [int]$BandH = 0,                               # its height (0 = down to the bottom)
  [int]$Bite = 46,                               # px eaten in from an edge midpoint; sets the band width
  [string]$Cut = 'assets\terrain\plain.png',     # material laid over the parts that are not this terrain
  [switch]$CutTransparent,                       # leave the cut side transparent instead of laying -Cut over
                                                 # it: the board shows whatever is underneath (a bridge over
                                                 # a river). -Cut is then ignored.
  [int]$EdgeWidth = 2,                           # dark outline drawn along the cut, 0 = none
  [string]$EdgeColor = '#2E281C'                 # its colour (sample it from the source's own outline)
)
$ErrorActionPreference = 'Stop'
$W = 256                 # tile width  = 2R
$H = 222                 # tile height = ceil(sqrt3 * R), R=128
$R = 128.0               # hex centre -> vertex. Also the length of one hex edge.
$APOTHEM = 110.85        # hex centre -> edge midpoint. Same for all six edges.
$Colors = 64             # palette reduction (match the other terrain tiles)
$CX = 128.0
$CY = 111.0

# Bit i of the file name maps to Hex.DIRECTIONS[i]; these are the matching edge
# directions, in degrees clockwise from straight up.
$ANGLES = @(120, 60, 0, 300, 240, 180)

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$outDir = Join-Path $repo 'assets\terrain'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (-not [System.IO.Path]::IsPathRooted($Source)) { $Source = Join-Path $repo $Source }
if (-not [System.IO.Path]::IsPathRooted($Cut)) { $Cut = Join-Path $repo $Cut }
if (-not (Test-Path $Source)) { throw "source not found: $Source" }
if ((-not $CutTransparent) -and (-not (Test-Path $Cut))) { throw "cut material not found: $Cut" }

$halfW = $APOTHEM - $Bite
if ($halfW -le 0) { throw "-Bite must be smaller than $APOTHEM" }
if ($halfW -lt ($R / 2)) {
  Write-Warning ("-Bite {0} leaves a {1:N1}px band, under the {2}px hex edge: connected edges will not be covered end to end (max {3:N2})" -f $Bite, (2 * $halfW), [int]$R, ($APOTHEM - $R / 2))
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("area_tiles_" + $Name)
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$inv = [Globalization.CultureInfo]::InvariantCulture
function Pt([double]$x, [double]$y) { $x.ToString('0.##', $inv) + ',' + $y.ToString('0.##', $inv) }
$hexPoly = "polygon 256,111 192,221.85 64,221.85 0,111 64,0.15 192,0.15"

# 1. The base tile: the source texture covering the whole frame. No rotation, no
#    overlay -- every one of the 64 pieces is cut out of this same image.
if ($BandH -le 0) {
  $srcH = [int](& magick $Source -format '%h' info:)
  $BandH = $srcH - $BandY
}
$base = Join-Path $work 'base.png'
& magick $Source -crop ("{0}x{1}+{2}+{3}" -f $BandW, $BandH, $BandX, $BandY) +repage `
  -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" $base

# 2. One band mask per direction, drawn as a half-strip running from the tile
#    centre out past the edge. Overshooting the frame keeps the band's sides from
#    bending in at the hex boundary.
$L = 200.0
$band = @{}
foreach ($a in $ANGLES) {
  $rad = $a * [math]::PI / 180.0
  $ux = [math]::Sin($rad); $uy = -[math]::Cos($rad)   # towards the edge midpoint
  $vx = [math]::Cos($rad); $vy = [math]::Sin($rad)    # along the edge
  $p1 = Pt ($CX - $halfW * $vx) ($CY - $halfW * $vy)
  $p2 = Pt ($CX + $halfW * $vx) ($CY + $halfW * $vy)
  $p3 = Pt ($CX + $halfW * $vx + $L * $ux) ($CY + $halfW * $vy + $L * $uy)
  $p4 = Pt ($CX - $halfW * $vx + $L * $ux) ($CY - $halfW * $vy + $L * $uy)
  $band[$a] = "polygon $p1 $p2 $p3 $p4"
}
# The disc rounds off the inside of a bend and is the whole shape when a tile
# stands alone. Radius = the band's half-width, so it is tangent to every band
# and never bulges out of a straight run.
$disc = "circle " + (Pt $CX $CY) + " " + (Pt $CX ($CY - $halfW))

$mRoad = Join-Path $work 'road.png'
$mEdge = Join-Path $work 'edge.png'
$made = 0
for ($mask = 0; $mask -lt 64; $mask++) {
  $bits = ''
  $draws = @('-fill', 'white', '-draw', $disc)
  for ($i = 0; $i -lt 6; $i++) {
    if ($mask -band (1 -shl $i)) {
      $bits += '1'
      $draws += @('-draw', $band[$ANGLES[$i]])
    } else {
      $bits += '0'
    }
  }
  # white = this terrain, black = cut away and replaced by the neighbouring material
  & magick -size "${W}x${H}" xc:black @draws -alpha off -colorspace gray $mRoad

  $edge = @()
  if ($EdgeWidth -gt 0) {
    # A rim of dark just INSIDE the terrain, along the cut: dilate the cut side
    # and keep only what lands back on the terrain. Grows from the boundary, so
    # the outline never crosses a connected edge and c111111 gets none at all.
    & magick $mRoad -negate -morphology Dilate "Disk:$EdgeWidth" $mRoad `
      -compose Multiply -composite $mEdge
    $edge = @(
      '(', '-size', "${W}x${H}", "xc:$EdgeColor", '-alpha', 'off',
      $mEdge, '-compose', 'CopyOpacity', '-composite', ')',
      '-compose', 'Over', '-composite'
    )
  }

  $out = Join-Path $outDir ("{0}_c{1}.png" -f $Name, $bits)
  # -CutTransparent: the mask becomes the tile's alpha, so the cut side is a hole and the board
  # shows the skin laid underneath (map_ground). Otherwise the cut side is covered by -Cut.
  $cover = if ($CutTransparent) {
    @('-alpha', 'off', $mRoad, '-compose', 'CopyOpacity', '-composite')
  } else {
    @('(', $Cut, '-alpha', 'off', '(', $mRoad, '-negate', ')', '-compose', 'CopyOpacity', '-composite', ')',
      '-compose', 'Over', '-composite')
  }
  $args = @($base) + $cover + $edge + @(
    '(', '-size', "${W}x${H}", 'xc:none', '-fill', 'white', '-draw', $hexPoly, ')',
    '-alpha', 'set', '-compose', 'DstIn', '-composite',
    '-colors', "$Colors", '-dither', 'None', $out
  )
  & magick @args
  $made++
}

# The straight north-south piece doubles as the fallback tile <name>.png
# (used when a combination has no file of its own, and by any code that just
# wants "the" tile for this skin).
Copy-Item (Join-Path $outDir ("{0}_c001001.png" -f $Name)) (Join-Path $outDir ("{0}.png" -f $Name)) -Force
Remove-Item -Recurse -Force $work

$kb = [int](((Get-ChildItem (Join-Path $outDir ("{0}_c*.png" -f $Name)) | Measure-Object Length -Sum).Sum) / 1KB)
Write-Output ("{0}: bite {1} -> band {2:N1}px ({3:N0}% of {4}px across the hex), {5} pieces + {0}.png, {6}KB" -f `
  $Name, $Bite, (2 * $halfW), (100.0 * 2 * $halfW / (2 * $APOTHEM)), [int](2 * $APOTHEM), $made, $kb)
