<#
.SYNOPSIS
  Export the game map.png (stage 3) from a hand master (stage 2) or raw AI image (stage 1).

.DESCRIPTION
  Given one or more skin_ids, looks up map_scale in unit_skin.csv, sets the figure
  height = BaseHeight * map_scale, and writes a 256px square, transparent, 64-color
  assets/units/<id>/<id>_map.png from units-src/<group>/<id>/<id>_03_master.png.
  map_offset_x (same csv, px at map_scale=1.0, + = right) shifts the figure sideways
  so the BODY sits on the hex center; a weapon held out to one side is allowed to
  overhang. Without it the trimmed bounding box is centered and the prop drags the
  body off-center. Rule of record: doc/art/units.md section 3.1.
  <group> is a faction folder (player, goblin, ...); the source dir is found by
  searching assets/units-src/ recursively for a folder named <id>.
  The hand master is _03_master (dew/02 is skipped for units: the transparent trim
  drops the watermark anyway, but the number stays master=03). _02_master is still
  read as a fallback for not-yet-renamed sources.
  If no master is present it falls back to the 01_raw (white bg auto-keyed;
  fringe is meant to be cleaned by hand in the master later).
  Recipe of record: doc/art/units.md section 3.1. Requires ImageMagick (magick).
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
$Canvas     = 384   # output canvas (square). Carries the relative sizes: the board maps the
                    # CANVAS height (not the figure) to a fixed number of tiles, so this must be
                    # the same for every unit and large enough for the biggest map_scale.
                    # 384 / 200 = max scale 1.92 (dragon is 1.4). Changing it means regenerating
                    # every unit AND rescaling the board constant in hex_board_3d.gd (see 3.1).
$SkinIds = @($SkinIds)
if ($SkinIds.Count -eq 0) { throw "usage: gen_unit_map.ps1 <skin_id> [<skin_id> ...] | all" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here                  # parent of tools/ = repo root
$csv     = Join-Path $repo 'data\units\unit_skin.csv'
$srcRoot = Join-Path $repo 'assets\units-src'
$outRoot = Join-Path $repo 'assets\units'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

# Read map_scale / map_offset_x. Row 1 = english keys (Import-Csv header); row 2 = JP labels,
# dropped by the numeric filter.
$scale  = @{}
$offset = @{}
foreach ($r in (Import-Csv -Path $csv -Encoding UTF8)) {
  if ($r.map_scale -match '^[0-9.]+$') { $scale[$r.skin_id] = [double]$r.map_scale }
  if ($r.map_offset_x -match '^-?[0-9]+$') { $offset[$r.skin_id] = [int]$r.map_offset_x }
}

if ($SkinIds.Count -eq 1 -and $SkinIds[0] -eq 'all') { $SkinIds = @($scale.Keys) }

foreach ($id in $SkinIds) {
  $sc = if ($scale.ContainsKey($id)) { $scale[$id] } else { 1.0 }
  $h  = [int][math]::Round($BaseHeight * $sc)
  # Sideways shift, in output px: the csv value is measured at map_scale=1.0, so it scales
  # with the figure. Splicing 2*shift of transparent on one side moves the trimmed art by
  # `shift` once -extent re-centers the canvas (splice alone would only pad, not move it).
  $ox    = if ($offset.ContainsKey($id)) { $offset[$id] } else { 0 }
  $shift = [int][math]::Round($ox * $sc)
  $shiftArgs = @()
  if ($shift -ne 0) {
    $side = if ($shift -gt 0) { 'west' } else { 'east' }
    $shiftArgs = @('-gravity', $side, '-splice', ("{0}x0" -f (2 * [math]::Abs($shift))))
  }
  # source dir = the folder named <id> that actually holds the master/01_raw.
  # Checking file presence matters: a faction folder can share the skin's name
  # (source/goblin/ vs skin goblin -> source/goblin/goblin/).
  $srcDir = Join-Path $srcRoot $id
  $hit = Get-ChildItem -Path $srcRoot -Directory -Recurse |
    Where-Object { $_.Name -eq $id -and (
      (Test-Path (Join-Path $_.FullName "${id}_03_master.png")) -or
      (Test-Path (Join-Path $_.FullName "${id}_02_master.png")) -or
      (Test-Path (Join-Path $_.FullName "${id}_01_raw.png"))) } |
    Select-Object -First 1
  if ($hit) { $srcDir = $hit.FullName }
  # master = _03_master; fall back to the old _02_master name if not renamed yet.
  $master = Join-Path $srcDir "${id}_03_master.png"
  if (-not (Test-Path $master)) { $master = Join-Path $srcDir "${id}_02_master.png" }
  $raw    = Join-Path $srcDir "${id}_01_raw.png"
  $outDir = Join-Path $outRoot $id
  $out    = Join-Path $outDir "${id}_map.png"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  if (Test-Path $master) {
    # the master is already transparent: trim -> scale -> 256 square -> reduce colors
    magick $master -trim +repage -resize "x$h" -background none @shiftArgs -gravity south -extent "${Canvas}x${Canvas}" -colors $Colors -dither None $out
    $srcKind = 'master'
  }
  elseif (Test-Path $raw) {
    # 01_raw is white-bg: key out the background via border floodfill, then same steps (provisional)
    # (only used when no master exists yet)
    magick $raw -fuzz 6% -trim +repage -alpha set -bordercolor white -border 1 -fuzz 14% -fill none -draw "alpha 0,0 floodfill" -shave 1x1 -resize "x$h" -background none @shiftArgs -gravity south -extent "${Canvas}x${Canvas}" -colors $Colors -dither None $out
    $srcKind = 'raw(provisional)'
  }
  else {
    Write-Warning "${id}: no source (${id}_03_master.png / ${id}_01_raw.png) -> skipped"
    continue
  }
  # -extent crops silently when the figure does not fit, so verify what actually landed.
  # The figure must keep its full height; touching the canvas width means the sides were cut.
  # -trim without +repage keeps the page offset, so %X tells whether the art reaches an edge
  # (a shifted figure can be cut on one side while its width still fits).
  $bb = (magick $out -trim -format "%w %h %X" info:) -split ' '
  $bw = [int]$bb[0]
  $bx = [int]($bb[2] -replace '\+', '')
  if ([int]$bb[1] -lt $h) {
    Write-Warning "${id}: cropped vertically (wanted ${h}px, kept $($bb[1])px). Raise `$Canvas or lower map_scale."
  }
  if ($bx -le 0 -or ($bx + $bw) -ge $Canvas) {
    Write-Warning "${id}: touches the ${Canvas}px canvas edge (art $bw px at +$bx). Raise `$Canvas, lower map_scale, or reduce map_offset_x."
  }
  $kb = [int]((Get-Item $out).Length / 1KB)
  Write-Output ("{0,-16} scale={1,-4} H={2,-4} shift={3,-4} src={4,-16} -> assets/units/{5}/{5}_map.png ({6}KB)" -f $id, $sc, $h, $shift, $srcKind, $id, $kb)
}
