<#
.SYNOPSIS
  Export the board impact art of formation skills from hand masters (trim, keep alpha).

.DESCRIPTION
  For one or more recipe_ids (or 'all'), reads
  formations-src/<id>/<id>_impact_03_master.png and writes
  assets/formations/<id>_impact.png: trim transparent margins, then fit inside a
  fixed square box. Alpha kept, no color reduction.

  This is the small graphic that drops onto the hit pieces on the board, NOT the
  one-second cut-in (that one is <id>.png, exported by hand). The board never
  rotates it, so the master must already be drawn pointing DOWN.

  No padding is baked in: the art is trimmed tight and the on-screen size comes
  from HIT_BURST_TILES in hex_board_3d.gd at draw time.

  Only ids whose master exists are written. Recipe of record: doc/art/keyvisual.md 3.
  Requires ImageMagick (magick). NOTE: keep this file ASCII-only (PowerShell 5.1).

.EXAMPLE
  powershell -File tools\gen_formation_impact.ps1 trinity_spell
  powershell -File tools\gen_formation_impact.ps1 all
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RecipeIds      # one or more recipe_ids, or 'all'.
)
$ErrorActionPreference = 'Stop'
$Box = 512   # longest side of the trimmed art (px). Display size comes from the board.

$RecipeIds = @($RecipeIds)
if ($RecipeIds.Count -eq 0) { throw "usage: gen_formation_impact.ps1 <recipe_id> [<recipe_id> ...] | all" }

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$srcRoot = Join-Path $repo 'assets\formations-src'
$outRoot = Join-Path $repo 'assets\formations'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick) not found. Install: winget install ImageMagick.ImageMagick"
}

if ($RecipeIds.Count -eq 1 -and $RecipeIds[0] -eq 'all') {
  $RecipeIds = Get-ChildItem -Path $srcRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name)_impact_03_master.png") } |
    ForEach-Object { $_.Name } | Sort-Object
}

foreach ($id in $RecipeIds) {
  $master = Join-Path (Join-Path $srcRoot $id) "${id}_impact_03_master.png"
  if (-not (Test-Path $master)) {
    Write-Warning "${id}: no master (${id}_impact_03_master.png) -> skipped"
    continue
  }
  $out = Join-Path $outRoot "${id}_impact.png"
  & magick $master -background none -trim +repage -resize "${Box}x${Box}>" -strip PNG32:$out
  if ($LASTEXITCODE -ne 0) { throw "magick failed on ${id}" }

  $size = (& magick identify -format '%wx%h' $out | Out-String).Trim()
  '{0,-18} {1,9} -> {2}' -f $id, $size, "assets/formations/${id}_impact.png" | Write-Host
}

Write-Host ''
Write-Host 'Run the Godot import so the new files register:'
Write-Host '  godot --headless --path . --import'
