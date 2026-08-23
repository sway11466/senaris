<#
.SYNOPSIS
  Build a distributable package for one export preset.

.DESCRIPTION
  Runs the three steps that must not drift apart, in order:

    1. Regenerate the export filters from the content list
       (tools/build/contents.json -> export_presets.cfg exclude_filter).
       Doing this inside the build makes it impossible to ship stale filters.
       The rewritten export_presets.cfg is tracked by git, so any change to what
       ships shows up as a diff.
    2. Export the preset. Godot writes only the executable and the pack file.
    3. Copy THIRD-PARTY-LICENSES.txt next to the executable. Godot will not do
       this, and the license text is a distribution obligation, so it is part of
       the same command instead of a separate thing to remember.

  Uploading is deliberately NOT part of this script. Pushing to a store page
  cannot be undone, so making a build and publishing it stay separate steps with
  a human check in between (doc/tech/build.md).

  The build log is written beside the output folder (build/<preset>.build.log),
  not inside it, so the folder holds only what ships. Read it: the export succeeds
  even when files are silently dropped, so "it built" is not evidence that it works.

  Spec: doc/tech/build.md. Requires the Godot editor binary and the matching
  export templates.
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -File godot\tools\build\build.ps1 windows-itch-demo
  powershell -File godot\tools\build\build.ps1 windows-itch-demo -Godot "C:\path\to\Godot.exe"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Preset,

  # Godot editor binary. Defaults to $env:GODOT, then whatever is on PATH, then
  # a winget install. The path is machine-specific and stays out of the repo.
  [string]$Godot = ''
)

$ErrorActionPreference = 'Stop'

function Find-Godot([string]$explicit) {
  foreach ($candidate in @($explicit, $env:GODOT)) {
    if ($candidate -and (Test-Path $candidate)) { return (Resolve-Path $candidate).Path }
  }
  $cmd = Get-Command 'godot' -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path $winget) {
    $hit = Get-ChildItem -Path $winget -Filter 'Godot_v*.exe' -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike '*console*' } |
      Sort-Object Name -Descending |
      Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  throw "Godot not found. Pass -Godot <path>, set `$env:GODOT, or add it to PATH."
}

# Repo root is two levels above godot/tools/build/.
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$project = Join-Path $repo 'godot'
$outDir = Join-Path $repo "build\$Preset"
$exe = Join-Path $outDir 'Senaris.exe'
$licenseSrc = Join-Path $project 'assets\licenses\THIRD-PARTY-LICENSES.txt'
# The log sits beside the output folder, not inside it: butler uploads the folder
# as-is, and the log is not part of what players download.
$log = Join-Path $repo "build\$Preset.build.log"

$godotExe = Find-Godot $Godot
Write-Host "Godot:  $godotExe"
Write-Host "Preset: $Preset"
Write-Host "Output: $outDir"

if (-not (Test-Path $licenseSrc)) {
  throw "Missing $licenseSrc. Run gen_licenses.gd first (see doc/tech/build.md)."
}

# Godot refuses to write into a directory that does not exist.
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host ''
Write-Host '--- 1/3 export filters ---'
& $godotExe --headless --path $project --script res://tools/build/gen_export_filters.gd |
  Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "gen_export_filters.gd failed ($LASTEXITCODE)." }

Write-Host ''
Write-Host '--- 2/3 export ---'
& $godotExe --headless --path $project --export-release $Preset $exe |
  Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw "Export failed ($LASTEXITCODE)." }
if (-not (Test-Path $exe)) { throw "Export reported success but $exe is missing." }

Write-Host ''
Write-Host '--- 3/3 licenses ---'
Copy-Item -Path $licenseSrc -Destination $outDir -Force
Write-Host "copied $(Split-Path $licenseSrc -Leaf)"

Write-Host ''
Write-Host '--- output ---'
Get-ChildItem -Path $outDir |
  Select-Object Name, @{ Name = 'MB'; Expression = { [math]::Round($_.Length / 1MB, 1) } } |
  Format-Table -AutoSize | Out-String | Write-Host

Write-Host 'Next: run the executable and check that the stages load, that no'
Write-Host 'unreleased campaign is on the board, and that the stamp is right.'
Write-Host 'Only then upload (doc/sales/itch_page.md).'
