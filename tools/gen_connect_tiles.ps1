<#
.SYNOPSIS
  Build a full set of connecting hex tiles (fence / road / wall lines) from ONE
  straight-run source image.

.DESCRIPTION
  A line terrain (a fence, a road) has to meet its neighbours at the middle of a
  hex edge. Rather than drawing every corner and junction by hand, this script
  cuts ONE arm out of a single straight-run drawing and rotates it into the six
  hex directions, so every piece is made of the same art and therefore always
  lines up. All 64 edge combinations are written out.

  The source art is a straight run drawn vertically, dead centre, on the same
  grass as the plain tile. It needs a post at the centre of the frame and a post
  further up the run; the arm is cut from post centre to post centre, so the
  outer post lands exactly on the hex edge and is shared, half and half, with
  the neighbouring tile.

  Output: assets/terrain/<name>_cBBBBBB.png, where each B is 1 if the tile
  connects in that direction, in Hex.DIRECTIONS order (domain/hex/hex.gd)
  = (1,0) (1,-1) (0,-1) (-1,0) (-1,1) (0,1). The straight north-south piece
  (001001) is also written as assets/terrain/<name>.png, which is what the board
  falls back to when a combination has no file. Drop-in: terrain_skin.csv is NOT
  touched apart from its connect column. Art spec: doc/art/terrain.md.
  Requires ImageMagick (magick).
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -File tools\gen_connect_tiles.ps1 fence `
    assets\terrain-src\fence\fence_01_raw.png -ArmFrom 136 -ArmTo 512 `
    -BandX 460 -BandW 104 -PostHalf 32
#>
param(
  [Parameter(Mandatory = $true)][string]$Name,      # skin id / file stem, e.g. 'fence'
  [Parameter(Mandatory = $true)][string]$Source,    # straight-run source art (square)
  [Parameter(Mandatory = $true)][int]$ArmFrom,      # source Y of the OUTER post centre
  [Parameter(Mandatory = $true)][int]$ArmTo,        # source Y of the CENTRE post centre
  [Parameter(Mandatory = $true)][int]$BandX,        # source X where the run's band starts
  [Parameter(Mandatory = $true)][int]$BandW,        # width of that band
  [Parameter(Mandatory = $true)][int]$PostHalf,     # half height of the centre post, in source px
  [string]$Base = 'assets\terrain\plain.png',       # ground the pieces are composed onto
  [int]$Threshold = 66,                             # gray % above which a pixel counts as ground
  [string]$EdgeColor = '#2F3028',                   # colour bled into the cut edge (the art's outline)
  [switch]$NoShadow,
  [string]$ShadowOffset = '+4+3',
  [double]$ShadowBlur = 1.2,
  [double]$ShadowAlpha = 0.33
)
$ErrorActionPreference = 'Stop'
$W = 256                 # tile width  = 2R
$H = 222                 # tile height = ceil(sqrt3 * R), R=128
$APOTHEM = 110.85        # hex centre -> edge midpoint. Same for all six edges.
$Colors = 64             # palette reduction (match the other terrain tiles)

# Bit i of the file name maps to Hex.DIRECTIONS[i]; these are the matching
# rotations of the arm, in degrees clockwise from straight up.
$ANGLES = @(120, 60, 0, 300, 240, 180)

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$outDir = Join-Path $repo 'assets\terrain'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (-not [System.IO.Path]::IsPathRooted($Source)) { $Source = Join-Path $repo $Source }
if (-not [System.IO.Path]::IsPathRooted($Base)) { $Base = Join-Path $repo $Base }
if (-not (Test-Path $Source)) { throw "source not found: $Source" }
if (-not (Test-Path $Base)) { throw "base tile not found: $Base" }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("connect_tiles_" + $Name)
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$armSrcH = $ArmTo - $ArmFrom
if ($armSrcH -le 0) { throw "-ArmTo must be below -ArmFrom in the source image" }
$scale = $APOTHEM / $armSrcH
# Keep the widths even so the art sits centred on the 256px tile.
$stubW = 2 * [int][math]::Round($BandW * $scale / 2.0)
$stubH = [int][math]::Round($APOTHEM)
$postH = 2 * [int][math]::Round($PostHalf * $scale)
$hexPoly = "polygon 256,111 192,221.85 64,221.85 0,111 64,0.15 192,0.15"

# Cut the grass away and keep only the timber. The mask is hard (not a ramp) and
# the cleared pixels are filled with the art's outline colour, so shrinking the
# cut-out afterwards bleeds dark into the edge instead of the source's grass
# green -- a pale fringe around the fence is the thing that gives this away.
function Cut([string]$crop, [string]$size, [string]$dest) {
  $args = @(
    $Source, '-crop', $crop, '+repage',
    '(', '+clone', '-colorspace', 'gray', '-threshold', "$Threshold%", '-negate', ')',
    '-alpha', 'off', '-compose', 'CopyOpacity', '-composite',
    '-background', $EdgeColor, '-alpha', 'background',
    '-resize', $size, $dest
  )
  & magick @args
}
$stub = Join-Path $work 'stub.png'
$post = Join-Path $work 'post.png'
Cut ("{0}x{1}+{2}+{3}" -f $BandW, $armSrcH, $BandX, $ArmFrom) ("{0}x{1}!" -f $stubW, $stubH) $stub
Cut ("{0}x{1}+{2}+{3}" -f $BandW, (2 * $PostHalf), $BandX, ($ArmTo - $PostHalf)) ("{0}x{1}!" -f $stubW, $postH) $post

# One arm layer per direction: the arm standing up from the tile centre, rotated.
$armX = [int](($W / 2) - ($stubW / 2))
$armY = [int](($W / 2) - $stubH)          # square work canvas: centre is (128,128)
$arm = @{}
foreach ($a in $ANGLES) {
  $f = Join-Path $work ("arm_{0}.png" -f $a)
  & magick -size "${W}x${W}" xc:none $stub -geometry "+$armX+$armY" -composite `
    -distort SRT "$($W/2),$($W/2) 1 $a $($W/2),$($W/2)" +repage $f
  $arm[$a] = $f
}
$postX = $armX
$postY = [int](($W / 2) - ($postH / 2))
$baseY = [int](($W - $H) / 2)             # centre the tile in the square work canvas

$made = 0
for ($mask = 0; $mask -lt 64; $mask++) {
  $bits = ''
  $layers = @()
  for ($i = 0; $i -lt 6; $i++) {
    if ($mask -band (1 -shl $i)) {
      $bits += '1'
      $layers += @($arm[$ANGLES[$i]], '-geometry', '+0+0', '-composite')
    } else {
      $bits += '0'
    }
  }
  $out = Join-Path $outDir ("{0}_c{1}.png" -f $Name, $bits)
  $shadow = @()
  if (-not $NoShadow) {
    $shadow = @(
      '(', 'mpr:L', '-channel', 'A', '-blur', "0x$ShadowBlur", '-evaluate', 'multiply', "$ShadowAlpha",
      '+channel', '-fill', 'black', '-colorize', '100', ')', '-geometry', $ShadowOffset, '-composite'
    )
  }
  $args = @('-size', "${W}x${W}", 'xc:none') + $layers + @(
    $post, '-geometry', "+$postX+$postY", '-composite',
    '-write', 'mpr:L', '+delete',
    '-size', "${W}x${W}", 'xc:none', $Base, '-geometry', "+0+$baseY", '-composite'
  ) + $shadow + @(
    'mpr:L', '-geometry', '+0+0', '-composite',
    '-crop', "${W}x${H}+0+$baseY", '+repage',
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
Write-Output ("{0}: arm {1}x{2}px (scale {3:N3}), {4} pieces + {0}.png, {5}KB" -f $Name, $stubW, $stubH, $scale, $made, $kb)
