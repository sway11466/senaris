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

  -Fit centres the remaining art and scales it as large as it will go while
  still sitting inside the hexagon, so no part of it is ever clipped. Fitting the
  hexagon (not its inscribed circle) is enough even for a tile the board rotates:
  orient() turns the hex MESH by 60 degrees and mirrors it with scale.x = -1
  (presentation/board/terrain_tiles.gd), and both are symmetries of a regular
  hexagon, so art inside the hexagon stays inside at every orientation. The size
  is found by binary search on the padded canvas, testing the art's actual
  silhouette against the hexagon, so a ragged outline is allowed to reach into
  the corners instead of being held back by its widest point. -Fit also
  normalises size: every variant comes out at the same scale whatever margin the
  generator happened to leave. -FitMargin below 1 shrinks the art from that
  maximum, which is how you leave a street between neighbouring tiles.

  An object skin (a building, a rock, a fort) is not a tile at all: the board stands it up as a
  billboard, the same way it stands up a unit.

  -Object writes that standee instead of a hex tile. The art is scaled to
  204.8px * map_scale (data/terrain/terrain_skin.csv) WIDE and dropped bottom-aligned on a 384px
  square canvas. The board maps the canvas height to 3.75 tiles, so 204.8px is exactly the width
  of one hexagon (2 tiles) and map_scale is "how much of a hex width the art takes". Units are
  measured the other way (height, in fighters); objects are measured by width because what the
  board must read is whether the thing overflows its own hex. The size difference is carried by
  the transparent padding, as it is for units. An empty map_scale is an error, not a default.
  Cannot be combined with -Fit / -Upright (there is no hexagon to fit and no tile to
  pre-stretch). Rule of record: doc/art/terrain.md.

  -CombatRear writes the combat-scene "rear" standee ({name}_combat_rear.png) instead: the
  object that stands right behind the defending lead figure (a throne). It uses the UNIT
  combat ruler (tools/gen_unit_combat.ps1): art height = 384px * combat_scale
  (terrain_skin.csv, "how many fighters tall"), bottom-aligned on a 704px square canvas.
  The scene draws this square at the same on-screen size as a unit figure, so size and
  any lift off the feet line are carried by the canvas padding, not by scene constants.
  Alpha kept, no colour reduction (same as unit combat images). An empty combat_scale is
  an error, not a default. -RearShift <px> moves the art toward the BACK (away from the
  battle line) inside the canvas, so it stands behind the lead figure instead of under it.
  The art is drawn for a defender on the left (facing right), so back = left; the scene
  mirrors the whole canvas for the right side. 0 = centred on the figure.
  -RearDrop <px> makes the canvas that many px TALLER than the square (704 wide x 704+drop
  tall) with the art still bottom-aligned. The scene pins the canvas TOP to the figure
  canvas top, so the extra rows hang below the feet line = the object sits lower than the
  figure's feet. 0 = feet on the feet line.

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
  [double]$Rotate = 0,                            # turn the art this many degrees clockwise before fitting
  [switch]$Object,                                # write a standee (see -Object above) instead of a hex tile
  [switch]$CombatRear,                            # write the combat rear standee (see -CombatRear above)
  [int]$RearShift = 0,                            # -CombatRear: px toward the back (left) on the canvas
  [int]$RearDrop = 0,                             # -CombatRear: px the art hangs below the feet line
  [switch]$Fit,                                   # centre the art and scale it to the largest that fits the hexagon
  [double]$FitMargin = 1.0,                       # 1 = touch the hexagon; below 1 leaves a gap to the neighbours
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

# -Object: the standee ruler. Both numbers are shared with units (gen_unit_map.ps1) so that one
# scale reads across the whole board; changing either means re-exporting everything and moving
# CANVAS_TILES in presentation/board/board_terrain_renderer.gd with it.
$ObjCanvas = 384   # output canvas (square) = 3.75 tiles tall, the same ruler the board uses
# Art width (px) at map_scale = 1.0 = one hexagon across (2 tiles) on that canvas: 384 * 2 / 3.75.
$ObjBase   = $ObjCanvas * 2.0 / 3.75
$ObjWidth  = 0
# -CombatRear: the unit combat ruler. Both numbers are gen_unit_combat.ps1's $Canvas / $BaseHeight;
# the scene draws this square with FIG_H, so changing either means changing them there too.
$RearCanvas = 704
$RearBase   = 384
$RearHeight = 0
if ($CombatRear) {
  if ($Object -or $Fit -or $Upright) { throw "-CombatRear cannot be combined with -Object / -Fit / -Upright" }
  $csv = Join-Path $repo "data\terrain\terrain_skin.csv"
  $row = Import-Csv -Path $csv -Encoding UTF8 | Where-Object { $_.skin_id -eq $Name } | Select-Object -First 1
  if (-not $row) { throw "$Name is not a skin_id in data/terrain/terrain_skin.csv" }
  # No fallback on purpose: a missing scale would silently ship a fighter-sized object.
  if ($row.combat_scale -notmatch "^[0-9]*\.?[0-9]+$" -or [double]$row.combat_scale -le 0) {
    throw "$Name has no combat_scale in terrain_skin.csv (found '$($row.combat_scale)'). Fill the column."
  }
  $RearHeight = [int][math]::Round($RearBase * [double]$row.combat_scale)
}
if ($Object) {
  if ($Fit -or $Upright) { throw "-Object cannot be combined with -Fit / -Upright" }
  $csv = Join-Path $repo "data\terrain\terrain_skin.csv"
  # A captured base has one image per owning team (<skin>_team0.png, _team1.png) but only one CSV
  # row: the board swaps the image, not the skin. Look the scale up under the base name so every
  # team image comes out at exactly the same size and the swap does not make the object jump.
  $scaleKey = $Name -replace "_team[0-9]+$", ""
  $row = Import-Csv -Path $csv -Encoding UTF8 | Where-Object { $_.skin_id -eq $scaleKey } | Select-Object -First 1
  if (-not $row) { throw "$scaleKey is not a skin_id in data/terrain/terrain_skin.csv" }
  # No fallback on purpose: a missing scale would silently ship a full-size object.
  if ($row.map_scale -notmatch "^[0-9]*\.?[0-9]+$" -or [double]$row.map_scale -le 0) {
    throw "$scaleKey has no map_scale in terrain_skin.csv (found '$($row.map_scale)'). Fill the column."
  }
  $ObjWidth = [int][math]::Round($ObjBase * [double]$row.map_scale)
}

# Flat-top hexagon points on the 256x222 canvas (center 128,111; R=128; half-h=110.85).
$hex = "polygon 256,111 192,221.85 64,221.85 0,111 64,0.15 192,0.15"
# The same hexagon inverted: white OUTSIDE it. -Fit multiplies the art's alpha by this and asks
# whether anything is left, i.e. whether any of the art pokes out of the hexagon.
$outMask = Join-Path $work 'outside.png'
& magick -size "${W}x${H}" xc:white -fill black -draw $hex $outMask

# Fraction of the tile that is both opaque and outside the hexagon, for the art padded to ${n} square.
function Get-Overflow([string]$art, [int]$n) {
  $probe = Join-Path $work 'probe.png'
  & magick $art -trim +repage -background none -gravity center -extent "${n}x${n}" `
    -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" -alpha extract -threshold 50% -strip $probe
  return [double](& magick $probe $outMask -compose Multiply -composite -format "%[fx:mean]" info:)
}

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

  # -Rotate: turn the art before fitting, to make the direction-variant skins of one drawing.
  # The three axes of a flat-top hexagon are 0 (up-down), 60 and 120 degrees; art drawn with an
  # up-down grain therefore gives all three directions from the one source.
  if ($Rotate -ne 0) {
    $turned = Join-Path $work ("turned_{0}.png" -f $i)
    & magick $stage -background none -rotate $Rotate $turned
    $stage = $turned
  }

  # -Fit: trim to the art, then binary-search the padded square canvas for the SMALLEST one
  # (= largest art) that still leaves nothing outside the hexagon. Padding to N scales the art
  # by W/N, so N and the art's size move opposite ways.
  if ($Fit) {
    $dim = (& magick $stage -trim -format "%w %h" info:) -split '\s+'
    $cw = [double]$dim[0]; $ch = [double]$dim[1]
    # hi: half-diagonal inside the apothem. A circle of that radius is inside the hexagon, so this
    # always fits and is a valid upper bound. lo: the art cannot be wider than the hexagon is at
    # its widest, nor taller than the hexagon is tall; below this no N can possibly fit.
    $hi = [int][math]::Ceiling([math]::Sqrt($cw * $cw + $ch * $ch) * ($W / 2.0) / $APOTHEM)
    $lo = [int][math]::Ceiling([math]::Max($cw, $ch * $W / (2.0 * $APOTHEM)))
    $tol = 0.00005   # ~3px of the 256x222 tile, to absorb the antialiased rim
    while ($hi - $lo -gt 1) {
      $mid = [int](($hi + $lo) / 2)
      if ((Get-Overflow $stage $mid) -le $tol) { $hi = $mid } else { $lo = $mid }
    }
    $n = [int][math]::Ceiling($hi / $FitMargin)
    $fitted = Join-Path $work ("fitted_{0}.png" -f $i)
    & magick $stage -trim +repage -background none -gravity center -extent "${n}x${n}" $fitted
    $stage = $fitted
    $note = " [fit {0}x{1} -> {2}sq]" -f [int]$cw, [int]$ch, $n
  }

  # -CombatRear: trim, set the height the csv asks for (width bounded by the canvas), bottom-align
  # on the unit combat square. Same recipe as gen_unit_combat.ps1 so the object and the figures share
  # one ruler. One source only (the scene has no variants for this slot).
  if ($CombatRear) {
    $out = Join-Path $outDir ("{0}_combat_rear.png" -f $Name)
    $sized = Join-Path $work 'rear_sized.png'
    magick $stage -trim +repage -resize "${RearCanvas}x${RearHeight}" $sized
    # Compose onto the canvas (square, plus -RearDrop rows below the feet line): bottom-centred,
    # then slid toward the back (left) by -RearShift.
    $rearH = $RearCanvas + $RearDrop
    magick -size "${RearCanvas}x${rearH}" xc:none $sized -gravity south -geometry "-${RearShift}+0" -composite $out
    $sz = (magick $sized -format "%w %h" info:) -split " "
    $bb = (magick $out -trim -format "%w %h" info:) -split " "
    if ([int]$bb[1] -lt $RearHeight) {
      Write-Warning "${Name}: cropped vertically (wanted ${RearHeight}px, kept $($bb[1])px). Lower combat_scale."
    }
    if ([int]$bb[0] -lt [int]$sz[0]) {
      Write-Warning "${Name}: cropped horizontally (art $($sz[0])px, kept $($bb[0])px). Lower -RearShift."
    }
    $kb = [int]((Get-Item $out).Length / 1KB)
    Write-Output ("{0,-14} <- {1,-28} -> assets/terrain/{0}_combat_rear.png ({2}KB) [rear H={3} shift={4} drop={5}]" -f $Name, (Split-Path $src -Leaf), $kb, $RearHeight, $RearShift, $RearDrop)
    break
  }

  # -Object: trim to the art, scale it to the width the csv asks for, and drop it bottom-aligned
  # on the square canvas. The padding left over is what carries the size difference. No hex mask:
  # nothing here is tiled, the board bills this up facing the camera.
  if ($Object) {
    magick $stage -trim +repage -resize "${ObjWidth}x" -background none -gravity south `
      -extent "${ObjCanvas}x${ObjCanvas}" -colors $Colors -dither None $out
    # -extent crops silently when the art does not fit, so verify what actually landed.
    $bb = (magick $out -trim -format "%w %h" info:) -split " "
    $bw = [int]$bb[0]
    $bh = [int]$bb[1]
    if ($bw -lt $ObjWidth) {
      Write-Warning "${Name}: cropped horizontally (wanted ${ObjWidth}px, kept ${bw}px). Lower map_scale."
    }
    # Tall art can outgrow the canvas even when the width fits; the top is what gets cut.
    if ($bh -ge $ObjCanvas) {
      Write-Warning "${Name}: fills the ${ObjCanvas}px canvas height (art ${bh}px). Lower map_scale or draw it wider."
    }
    $kb = [int]((Get-Item $out).Length / 1KB)
    Write-Output ("{0,-14} <- {1,-28} -> assets/terrain/{2}{3}.png ({4}KB) [standee W={5} H={6}]" -f $Name, (Split-Path $src -Leaf), $Name, $suffix, $kb, $ObjWidth, $bh)
    continue
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
