<#
.SYNOPSIS
  Build a game-ready sound effect (.ogg) from a MuseScore .wav export.

.DESCRIPTION
  Takes assets/sfx-src/<name>.wav and writes assets/sfx/<name>.ogg, applying the
  three steps every SFX needs and none of them by hand:

    1. Trim silence at both ends. MuseScore pads the export to the full score
       length, so a 0.3s hit ships as a 3.5s file. The tail keeps a pool voice
       busy long after the sound is over, and head silence reads as input lag.
    2. Peak-normalize to a common target (default -3 dBFS). MuseScore exports
       conservatively (measured around -20 dBFS), which is far below the music.
       Do NOT fix this by raising velocity in MuseScore: for percussion that
       switches to a harder-struck sample and changes the timbre, not just the
       level. Gain here is level only.
    3. Encode Ogg Vorbis. Godot reads Vorbis only -- an .ogg holding Opus fails
       to import (valid=false). The encoder is pinned to libvorbis so the trap
       cannot happen; the codec is verified after writing.

  Per-scene balance is NOT this script's job -- that lives on the Music / SFX
  buses (default_bus_layout.tres) so the mix can change without re-exporting.
  Materials get a common level here; the mix is made in Godot.

  Spec: doc/audio/sfx.md. Requires ffmpeg (searched on PATH, then winget).
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -File tools\gen_sfx.ps1 ui_confirm
  powershell -File tools\gen_sfx.ps1 ui_confirm ui_cancel ui_denied
  powershell -File tools\gen_sfx.ps1 ui_hover -PeakDb -6
#>

# PositionalBinding=$false keeps the optional switches named-only, so every bare
# argument falls through to $Names (otherwise the 2nd name binds to -PeakDb).
[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$Names,                 # sfx_id(s); reads assets/sfx-src/<name>.wav
  [double]$PeakDb = -3.0,           # target peak level (dBFS) shared by every material
  [int]$Quality = 6,                # libvorbis -q:a (6 is about 192kbps)
  [double]$FadeSec = 0.01,          # fade-out at the trimmed tail (anti-click)
  [string]$SilenceDb = '-60dB'      # what counts as silence when trimming
)
$ErrorActionPreference = 'Stop'

$SrcDir = 'assets/sfx-src'
$OutDir = 'assets/sfx'

function Find-Ffmpeg([string]$exe) {
  $cmd = Get-Command $exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path $winget) {
    $hit = Get-ChildItem -Path $winget -Filter "$exe.exe" -Recurse -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  throw "$exe not found. Install it (winget install Gyan.FFmpeg) or add it to PATH."
}

$Ffmpeg = Find-Ffmpeg 'ffmpeg'
$Ffprobe = Find-Ffmpeg 'ffprobe'

# ffmpeg reports everything on stderr. Piping that through PowerShell 5.1 with 2>&1
# wraps each line in an ErrorRecord and trips $ErrorActionPreference='Stop' even on a
# clean exit, so route stderr to a file instead and read it back.
function Invoke-Ffmpeg([string[]]$FfArgs) {
  $errFile = [System.IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath $Ffmpeg -ArgumentList $FfArgs -NoNewWindow -Wait `
                       -RedirectStandardError $errFile -PassThru
    return [pscustomobject]@{
      ExitCode = $p.ExitCode
      Stderr   = (Get-Content $errFile -Raw)
    }
  } finally {
    Remove-Item $errFile -Force -ErrorAction SilentlyContinue
  }
}

# Trim head silence, then reverse to trim the tail the same way. The fade is applied
# as a fade-IN while reversed, which lands as a fade-out at the end without having to
# know the trimmed duration up front.
$trim = "silenceremove=start_periods=1:start_silence=0:start_threshold=$SilenceDb," +
        "areverse," +
        "silenceremove=start_periods=1:start_silence=0:start_threshold=$SilenceDb," +
        "afade=t=in:d=$FadeSec," +
        "areverse"

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

foreach ($name in $Names) {
  $src = Join-Path $SrcDir "$name.wav"
  $out = Join-Path $OutDir "$name.ogg"
  if (-not (Test-Path $src)) { throw "source not found: $src" }

  # Pass 1: measure the peak of the trimmed signal so pass 2 can hit the target exactly.
  $probe = Invoke-Ffmpeg @('-hide_banner', '-i', $src, '-af', "$trim,volumedetect", '-f', 'null', '-')
  if ($probe.ExitCode -ne 0) { throw "ffmpeg failed to analyze ${name}: $($probe.Stderr)" }
  if ($probe.Stderr -notmatch 'max_volume:\s*(-?[0-9.]+) dB') { throw "could not measure peak: $name" }
  $peak = [double]$Matches[1]
  $gain = $PeakDb - $peak

  # Pass 2: trim, apply the measured gain, encode Vorbis.
  $enc = Invoke-Ffmpeg @('-y', '-loglevel', 'error', '-i', $src,
    '-af', "$trim,volume=$($gain.ToString('0.00'))dB",
    '-c:a', 'libvorbis', '-q:a', $Quality, $out)
  if ($enc.ExitCode -ne 0) { throw "ffmpeg failed on ${name}: $($enc.Stderr)" }

  # Verify the container really holds Vorbis (Opus imports as valid=false in Godot).
  $codec = (& $Ffprobe -v error -select_streams a:0 -show_entries stream=codec_name `
    -of default=nw=1:nk=1 $out | Out-String).Trim()
  if ($codec -ne 'vorbis') { throw "expected vorbis, got '$codec': $out" }
  $dur = (& $Ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $out | Out-String).Trim()

  '{0,-14} {1,7:0.000}s  peak {2,6:0.0} -> {3,5:0.0} dBFS  (gain {4,5:0.0} dB)' -f `
    $name, [double]$dur, $peak, $PeakDb, $gain | Write-Host
}

Write-Host ''
Write-Host 'Done. Run the Godot import so the new files register:'
Write-Host '  godot --headless --path . --import'
