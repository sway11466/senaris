<#
.SYNOPSIS
  Export a gimmick's board standees, one per state, cut from the same range at the same scale.

.DESCRIPTION
  A gimmick (switch, trap; see doc/gdd/gimmicks.md) has one board picture per state:
  assets/gimmicks/<kind>_<state>.png. The board swaps them when the state changes, so every
  state must land at the same size and position; only the part that shows the state (a lever,
  a glowing sigil) may differ.

  Give every state's master at once. Masters must share one canvas size and have a transparent
  background (the recipe makes them from the white-background raw, the same way as terrain
  objects). The script takes the union of all the masters' art bounds, crops every master to
  that one rectangle, scales them all by the same factor and drops them bottom-aligned on the
  384px standee canvas. Trimming each state on its own would scale a lever-left picture and a
  lever-right picture differently, and the object would jump between states.

  The ruler is the terrain objects' one (doc/art/terrain.md 1): the union is scaled to
  204.8px * map_scale wide, where map_scale is the gimmick's row in
  data/gimmicks/gimmick_visual.csv (share of one hexagon's width). An empty map_scale is an
  error, not a default. Art spec: doc/art/gimmicks.md. Requires ImageMagick (magick).

  Each state is placed as the row's "placement" says (state:stand|state:flat; a state missing
  there is an error). Stand states are the standees above. Flat states lie on the floor: their
  union is scaled to 384px * map_scale wide and centred on a 384px-wide canvas (one hexagon wide)
  as tall as the art; the board lays it on a floor plate. Stand and flat states each get their
  own union crop.
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

  -CombatRear writes the combat-scene "rear" standees (<kind>_<state>_combat_rear.png) instead,
  with the same union crop and one scale for every state. The ruler is gen_terrain_tile.ps1
  -CombatRear's (the unit combat ruler): the union is scaled to 384px * combat_scale tall
  (width bounded by the canvas), bottom-aligned on a 704px square canvas. Alpha kept, no colour
  reduction. -RearShift / -RearDrop mean what they mean there and apply to every state.
  An empty combat_scale is an error, not a default.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\gen_gimmick.ps1 production_switch `
    on=assets\gimmicks-src\production_switch\production_switch_on_03_master.png `
    off=assets\gimmicks-src\production_switch\production_switch_off_03_master.png
#>
# PositionalBinding is off so that -RearShift / -RearDrop cannot swallow a state=path argument.
[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Kind,
  [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)][string[]]$States,
  [int]$Colors = 64,
  [switch]$CombatRear,   # write the combat rear standees (see -CombatRear above)
  [int]$RearShift = 0,   # -CombatRear: px toward the back (left) on the canvas
  [int]$RearDrop = 0     # -CombatRear: px the art hangs below the feet line
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot   # godot/
Set-Location $root

# The standee ruler, shared with terrain objects and units (tools/gen_terrain_tile.ps1 -Object).
$Canvas = 384
$Base   = $Canvas * 2.0 / 3.75

$csv = Join-Path $root "data\gimmicks\gimmick_visual.csv"
$row = Import-Csv -Path $csv -Encoding UTF8 | Where-Object { $_.kind -eq $Kind } | Select-Object -First 1
if ($null -eq $row) { throw "$Kind has no row in data/gimmicks/gimmick_visual.csv." }
if ($CombatRear) {
  # The unit combat ruler, the same numbers as gen_terrain_tile.ps1 -CombatRear (and gen_unit_combat.ps1).
  $RearCanvas = 704
  $RearBase   = 384
  if ($row.combat_scale -notmatch "^[0-9]*\.?[0-9]+$" -or [double]$row.combat_scale -le 0) {
    throw "$Kind has no combat_scale in gimmick_visual.csv (found '$($row.combat_scale)'). Fill the column."
  }
  $RearHeight = [int][math]::Round($RearBase * [double]$row.combat_scale)
} else {
  if ($row.map_scale -notmatch "^[0-9]*\.?[0-9]+$" -or [double]$row.map_scale -le 0) {
    throw "$Kind has no map_scale in gimmick_visual.csv (found '$($row.map_scale)'). Fill the column."
  }
  $Width = [int][math]::Round($Base * [double]$row.map_scale)
}

# state=path pairs
$pairs = @()
foreach ($s in $States) {
  $i = $s.IndexOf("=")
  if ($i -lt 1) { throw "Give each state as state=path (got '$s')." }
  $name = $s.Substring(0, $i)
  $path = $s.Substring($i + 1)
  if (-not (Test-Path $path)) { throw "No such file: $path" }
  $pairs += , @($name, $path)
}

# Union of the art bounds. Every master must be on the same canvas, or the union means nothing.
$size = $null
$x0 = [int]::MaxValue; $y0 = [int]::MaxValue; $x1 = -1; $y1 = -1
foreach ($p in $pairs) {
  $wh = (magick $p[1] -format "%w %h" info:) -split " "
  $cur = "$($wh[0])x$($wh[1])"
  if ($null -eq $size) { $size = $cur } elseif ($size -ne $cur) {
    throw "Masters differ in size ($size vs $cur for $($p[0])). Put every state on one canvas."
  }
  $bb = (magick $p[1] -trim -format "%w %h %X %Y" info:) -split " "
  $bx = [int]$bb[2]; $by = [int]$bb[3]
  $x0 = [math]::Min($x0, $bx); $y0 = [math]::Min($y0, $by)
  $x1 = [math]::Max($x1, $bx + [int]$bb[0]); $y1 = [math]::Max($y1, $by + [int]$bb[1])
}
$crop = "$($x1 - $x0)x$($y1 - $y0)+$x0+$y0"

$outDir = Join-Path $root "assets\gimmicks"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if ($CombatRear) {
  # Same union crop and the same box for every state = one scale. Compose bottom-centred on the
  # canvas (square, plus -RearDrop rows below the feet line), slid toward the back (left).
  $rearH = $RearCanvas + $RearDrop
  $work = Join-Path ([System.IO.Path]::GetTempPath()) ("gimmick_rear_" + $Kind)
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  foreach ($p in $pairs) {
    $out = Join-Path $outDir ("{0}_{1}_combat_rear.png" -f $Kind, $p[0])
    $sized = Join-Path $work ("{0}.png" -f $p[0])
    magick $p[1] -crop $crop +repage -resize "${RearCanvas}x${RearHeight}" $sized
    magick -size "${RearCanvas}x${rearH}" xc:none $sized -gravity south -geometry "-${RearShift}+0" -composite $out
    $sz = (magick $sized -format "%w %h" info:) -split " "
    if ([int]$sz[1] -gt $rearH) {
      Write-Warning "${Kind}_$($p[0]): cropped vertically (art $($sz[1])px, canvas ${rearH}px). Lower combat_scale."
    }
    if (($RearCanvas - [int]$sz[0]) / 2.0 -lt [math]::Abs($RearShift)) {
      Write-Warning "${Kind}_$($p[0]): cropped horizontally (art $($sz[0])px, shift ${RearShift}px). Lower -RearShift."
    }
    $kb = [int]((Get-Item $out).Length / 1KB)
    Write-Output ("{0}_{1} <- {2} -> assets/gimmicks/{0}_{1}_combat_rear.png ({3}KB) [crop {4} -> {5}x{6} shift={7} drop={8}]" -f $Kind, $p[0], (Split-Path $p[1] -Leaf), $kb, $crop, $sz[0], $sz[1], $RearShift, $RearDrop)
  }
  exit 0
}

# Placement per state (gimmick_visual.csv "placement" = state:stand|state:flat). Every state given here
# must be listed: a state without a placement is an error, not a default.
$Place = @{}
foreach ($kv in ("$($row.placement)" -split "\|")) {
  $j = $kv.IndexOf(":")
  if ($j -lt 1) { continue }
  $Place[$kv.Substring(0, $j).Trim()] = $kv.Substring($j + 1).Trim()
}
foreach ($p in $pairs) {
  if (-not $Place.ContainsKey($p[0])) {
    throw "$Kind has no placement for state '$($p[0])' in gimmick_visual.csv (found '$($row.placement)')."
  }
}

# Union of the art bounds of the given pairs (one crop rectangle = one scale for all of them).
function Get-UnionCrop($group) {
  $x0 = [int]::MaxValue; $y0 = [int]::MaxValue; $x1 = -1; $y1 = -1
  foreach ($p in $group) {
    $bb = (magick $p[1] -trim -format "%w %h %X %Y" info:) -split " "
    $bx = [int]$bb[2]; $by = [int]$bb[3]
    $x0 = [math]::Min($x0, $bx); $y0 = [math]::Min($y0, $by)
    $x1 = [math]::Max($x1, $bx + [int]$bb[0]); $y1 = [math]::Max($y1, $by + [int]$bb[1])
  }
  return "$($x1 - $x0)x$($y1 - $y0)+$x0+$y0"
}

# Standees: the stand states share one union crop and one scale, bottom-aligned on the standee canvas.
$stand = @($pairs | Where-Object { $Place[$_[0]] -eq "stand" })
if ($stand.Count -gt 0) {
  $crop = Get-UnionCrop $stand
  foreach ($p in $stand) {
    $out = Join-Path $outDir ("{0}_{1}.png" -f $Kind, $p[0])
    magick $p[1] -crop $crop +repage -resize "${Width}x" -background none -gravity south `
      -extent "${Canvas}x${Canvas}" -colors $Colors -dither None $out
    $bh = [int](magick $out -trim -format "%h" info:)
    if ($bh -ge $Canvas) {
      Write-Warning "${Kind}_$($p[0]): fills the ${Canvas}px canvas height (art ${bh}px). Lower map_scale."
    }
    $kb = [int]((Get-Item $out).Length / 1KB)
    Write-Output ("{0}_{1} <- {2} -> assets/gimmicks/{0}_{1}.png ({3}KB) [stand: crop {4} -> W={5}]" -f $Kind, $p[0], (Split-Path $p[1] -Leaf), $kb, $crop, $Width)
  }
}

# Floor pictures: drawn lying on the floor, centred on the hex. The canvas is one hexagon wide
# ($FlatCanvas px = the hex width); the art is map_scale of it wide, centred, the canvas as tall as
# the art. The board sizes the floor plate from the picture (one hex wide), so it never reads
# map_scale. The flat states share one union crop and one scale, like the standees.
$flat = @($pairs | Where-Object { $Place[$_[0]] -eq "flat" })
if ($flat.Count -gt 0) {
  $FlatCanvas = 384
  $FlatWidth = [int][math]::Round($FlatCanvas * [double]$row.map_scale)
  $crop = Get-UnionCrop $flat
  foreach ($p in $flat) {
    $out = Join-Path $outDir ("{0}_{1}.png" -f $Kind, $p[0])
    $h = [int](magick $p[1] -crop $crop +repage -resize "${FlatWidth}x" -format "%h" info:)
    magick $p[1] -crop $crop +repage -resize "${FlatWidth}x" -background none -gravity center `
      -extent "${FlatCanvas}x${h}" -colors $Colors -dither None $out
    $kb = [int]((Get-Item $out).Length / 1KB)
    Write-Output ("{0}_{1} <- {2} -> assets/gimmicks/{0}_{1}.png ({3}KB) [flat: crop {4} -> W={5} of {6}]" -f $Kind, $p[0], (Split-Path $p[1] -Leaf), $kb, $crop, $FlatWidth, $FlatCanvas)
  }
}
