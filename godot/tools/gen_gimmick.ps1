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
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\gen_gimmick.ps1 production_switch `
    on=assets\gimmicks-src\production_switch\production_switch_on_03_master.png `
    off=assets\gimmicks-src\production_switch\production_switch_off_03_master.png
#>
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Kind,
  [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)][string[]]$States,
  [int]$Colors = 64
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
if ($row.map_scale -notmatch "^[0-9]*\.?[0-9]+$" -or [double]$row.map_scale -le 0) {
  throw "$Kind has no map_scale in gimmick_visual.csv (found '$($row.map_scale)'). Fill the column."
}
$Width = [int][math]::Round($Base * [double]$row.map_scale)

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
foreach ($p in $pairs) {
  $out = Join-Path $outDir ("{0}_{1}.png" -f $Kind, $p[0])
  magick $p[1] -crop $crop +repage -resize "${Width}x" -background none -gravity south `
    -extent "${Canvas}x${Canvas}" -colors $Colors -dither None $out
  $bh = [int](magick $out -trim -format "%h" info:)
  if ($bh -ge $Canvas) {
    Write-Warning "${Kind}_$($p[0]): fills the ${Canvas}px canvas height (art ${bh}px). Lower map_scale."
  }
  $kb = [int]((Get-Item $out).Length / 1KB)
  Write-Output ("{0}_{1} <- {2} -> assets/gimmicks/{0}_{1}.png ({3}KB) [crop {4} -> W={5}]" -f $Kind, $p[0], (Split-Path $p[1] -Leaf), $kb, $crop, $Width)
}
