<#
.SYNOPSIS
  Export the board art of formation skills from hand masters (trim, keep alpha).

.DESCRIPTION
  For one or more recipe_ids (or 'all'), reads every board-art master under
  formations-src/<id>/ and writes the matching file into assets/formations/:
  trim transparent margins, then fit inside a fixed square box. Alpha kept, no
  color reduction.

  Two slots, one master each. Both are small graphics drawn without a character
  or a background, NOT the one-second cut-in (that one is <id>.png, exported by
  hand):
    impact  <id>_impact_03_master.png -> <id>_impact.png
            drops onto the hit pieces. The board never rotates it, so the master
            must already be drawn pointing DOWN.
    mark    <id>_mark_03_master.png   -> <id>_mark.png
            appears on the participants at the moment a recipe with no impact
            goes off, and fades out. Drawn upright and face-on.

  No padding is baked in: the art is trimmed tight and the on-screen size comes
  from the board at draw time.

  Only slots whose master exists are written. Recipe of record: doc/art/keyvisual.md 3.
  Requires ImageMagick (magick). NOTE: keep this file ASCII-only (PowerShell 5.1).

.EXAMPLE
  powershell -File tools\gen_formation_board_art.ps1 trinity_nova
  powershell -File tools\gen_formation_board_art.ps1 all
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RecipeIds      # one or more recipe_ids, or 'all'.
)
$ErrorActionPreference = 'Stop'
$Box = 512   # longest side of the trimmed art (px). Display size comes from the board.
$Slots = @('impact', 'mark')   # board-art slots, in export order. One master each.

$RecipeIds = @($RecipeIds)
if ($RecipeIds.Count -eq 0) { throw "usage: gen_formation_board_art.ps1 <recipe_id> [<recipe_id> ...] | all" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$srcRoot = Join-Path $repo 'assets\formations-src'
$outRoot = Join-Path $repo 'assets\formations'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

if ($RecipeIds.Count -eq 1 -and $RecipeIds[0] -eq 'all') {
  $RecipeIds = Get-ChildItem -Path $srcRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object {
      $dir = $_
      @($Slots | Where-Object { Test-Path (Join-Path $dir.FullName "$($dir.Name)_${_}_03_master.png") }).Count -gt 0
    } |
    ForEach-Object { $_.Name } | Sort-Object
}

foreach ($id in $RecipeIds) {
  $written = 0
  foreach ($slot in $Slots) {
    $master = Join-Path (Join-Path $srcRoot $id) "${id}_${slot}_03_master.png"
    if (-not (Test-Path $master)) { continue }
    $out = Join-Path $outRoot "${id}_${slot}.png"
    & magick $master -background none -trim +repage -resize "${Box}x${Box}>" -strip PNG32:$out
    if ($LASTEXITCODE -ne 0) { throw "magick failed on ${id}_${slot}" }

    $size = (& magick identify -format '%wx%h' $out | Out-String).Trim()
    '{0,-22} {1,9} -> {2}' -f "${id}_${slot}", $size, "assets/formations/${id}_${slot}.png" | Write-Host
    $written++
  }
  if ($written -eq 0) { Write-Warning "${id}: no board-art master found -> skipped" }
}

Write-Host ''
Write-Host 'Run the Godot import so the new files register:'
Write-Host '  godot --headless --path . --import'
