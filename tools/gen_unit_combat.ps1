<#
.SYNOPSIS
  Export the game combat images from hand masters (plan A: trim + downscale, keep alpha).

.DESCRIPTION
  For one or more skin_ids (or 'all'), reads the combat-slot masters
  units-src/<group>/<id>/<id>_<slot>_03_master.png (slot = combat, combat_hero)
  and writes assets/units/<id>/<id>_<slot>.png: trim transparent
  margins, set the figure height = BaseHeight * combat_scale (unit_skin.csv), then
  bottom-align it on a fixed 512 square transparent canvas. Alpha kept, no color
  reduction (unlike the map slot).
  The fixed canvas is what carries the relative sizes: the combat scene draws every
  unit into the same square with KEEP_ASPECT and puts the canvas bottom on the feet
  line, so a small unit stays small only if the padding is baked in. Trimming alone
  (the old recipe) made every unit fill the frame at the same size.
  Very wide figures are bounded by the canvas width too, so they shrink instead of
  being clipped. <group> is a faction folder; the source dir is found by
  searching assets/units-src/ recursively for a folder named <id>.
  Only slots whose master exists are written. Recipe of record: doc/art/units.md 3.3.
  Requires ImageMagick (magick). NOTE: keep this file ASCII-only (PowerShell 5.1).

.EXAMPLE
  powershell -File tools\gen_unit_combat.ps1 fighter
  powershell -File tools\gen_unit_combat.ps1 fighter goblin
  powershell -File tools\gen_unit_combat.ps1 all
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$SkinIds        # one or more skin_ids, or 'all'.
)
$ErrorActionPreference = 'Stop'
$Canvas     = 512   # output canvas (square)
$BaseHeight = 384   # figure height (px) at combat_scale=1.0. Baseline = fighter.
                    # 0.75 * Canvas = max scale 1.333. NOTE: dragon is 1.4 and does NOT fit -> its
                    # top gets cropped (the warning below catches it). Deciding the combat canvas
                    # belongs with the combat-scene framing work (backlog feature-22).
$Slots    = @('combat', 'combat_hero')  # attack effects are shared per weapon kind now -> tools\gen_effect.ps1
$SkinIds = @($SkinIds)
if ($SkinIds.Count -eq 0) { throw "usage: gen_unit_combat.ps1 <skin_id> [<skin_id> ...] | all" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$csv     = Join-Path $repo 'data\units\unit_skin.csv'
$srcRoot = Join-Path $repo 'assets\units-src'
$outRoot = Join-Path $repo 'assets\units'

# Read combat_scale. Row 1 = english keys (Import-Csv header); row 2 = JP labels, dropped by the numeric filter.
$scale = @{}
foreach ($r in (Import-Csv -Path $csv -Encoding UTF8)) {
  if ($r.combat_scale -match '^[0-9.]+$') { $scale[$r.skin_id] = [double]$r.combat_scale }
}

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

if ($SkinIds.Count -eq 1 -and $SkinIds[0] -eq 'all') {
  $SkinIds = Get-ChildItem -Path $srcRoot -Directory -Recurse |
    Where-Object { Get-ChildItem $_.FullName -Filter "*_combat*_master.png" -ErrorAction SilentlyContinue } |
    ForEach-Object { $_.Name } | Sort-Object -Unique
}

foreach ($id in $SkinIds) {
  $sc = if ($scale.ContainsKey($id)) { $scale[$id] } else { 1.0 }
  $h  = [int][math]::Round($BaseHeight * $sc)
  # source dir = the folder named <id> that holds a combat master.
  $srcDir = Join-Path $srcRoot $id
  $hit = Get-ChildItem -Path $srcRoot -Directory -Recurse |
    Where-Object { $_.Name -eq $id -and (Get-ChildItem $_.FullName -Filter "*_combat*_master.png" -ErrorAction SilentlyContinue) } |
    Select-Object -First 1
  if ($hit) { $srcDir = $hit.FullName }
  $outDir = Join-Path $outRoot $id
  $any = $false
  foreach ($slot in $Slots) {
    # master = hand-final. Named _03_master (skip dew but keep master=03). Fall back to _02_master.
    $master = Join-Path $srcDir "${id}_${slot}_03_master.png"
    if (-not (Test-Path $master)) { $master = Join-Path $srcDir "${id}_${slot}_02_master.png" }
    if (-not (Test-Path $master)) { continue }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $out = Join-Path $outDir "${id}_${slot}.png"
    # trim -> height = Base * scale (width bounded by the canvas) -> bottom-align on the square canvas
    magick $master -trim +repage -resize "${Canvas}x${h}" -background none -gravity south -extent "${Canvas}x${Canvas}" $out
    # -extent crops silently when the figure does not fit (width is bounded by -resize, height is not).
    $bb = (magick $out -trim +repage -format "%wx%h" info:) -split 'x'
    if ([int]$bb[1] -lt $h) {
      Write-Warning "${id} ${slot}: cropped vertically (wanted ${h}px, kept $($bb[1])px). Raise `$Canvas or lower combat_scale."
    }
    $kb = [int]((Get-Item $out).Length / 1KB)
    Write-Output ("{0,-16} {1,-14} x{2,-5} -> assets/units/{3}/{3}_{1}.png ({4}KB)" -f $id, $slot, $sc, $id, $kb)
    $any = $true
  }
  if (-not $any) { Write-Warning "${id}: no combat master (${id}_combat_03_master.png ...) -> skipped" }
}
