<#
.SYNOPSIS
  Build a game-ready sound effect (.ogg) from a MuseScore .wav export.

.DESCRIPTION
  Takes assets/sfx-src/<name>.wav and writes assets/sfx/<name>.ogg, applying the
  two steps every SFX needs and neither of them by hand:

    1. Trim silence at both ends. MuseScore pads the export to the full score
       length, so a 0.3s hit ships as a 3.5s file. The tail keeps a pool voice
       busy long after the sound is over, and head silence reads as input lag.
    2. Encode Ogg Vorbis. Godot reads Vorbis only -- an .ogg holding Opus fails
       to import (valid=false). The encoder is pinned to libvorbis so the trap
       cannot happen; the codec is verified after writing.

  Level is NOT applied here. It is built in MuseScore on the mixer master fader,
  the same way BGM is made (doc/audio/bgm.md). The fader lands on the export
  1:1 -- measured: an export sitting at -20.4 dBFS moved to -9.0 dBFS when the
  master was set to +11.4. This script only MEASURES the result and warns when
  it is off target, so a mistake stays visible instead of being silently fixed.

  Do NOT reach for note velocity in MuseScore to change level: sampled
  percussion switches to a harder-struck recording, so the timbre changes and
  not just the level. The mixer fader is pure gain.

  Per-scene balance is not this script's job either -- that lives on the
  Music / SFX buses (default_bus_layout.tres) so the mix can change without
  re-exporting.

  Spec: doc/audio/sfx.md. Requires ffmpeg (searched on PATH, then winget).
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -File tools\gen_sfx.ps1 ui_confirm
  powershell -File tools\gen_sfx.ps1 ui_confirm ui_cancel ui_denied ui_hover
#>

# PositionalBinding=$false keeps the optional switches named-only, so every bare
# argument falls through to $Names (otherwise the 2nd name binds to -Quality).
[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$Names,                 # sfx_id(s); reads assets/sfx-src/<name>.wav
  [double]$TolDb = 1.0,             # how far off the target level still passes
  [int]$Quality = 6,                # libvorbis -q:a (6 is about 192kbps)
  [double]$FadeSec = 0.01,          # fade-out at the trimmed tail (anti-click)
  [string]$SilenceDb = '-60dB'      # what counts as silence when trimming
)
$ErrorActionPreference = 'Stop'

$SrcDir = 'assets/sfx-src'
$OutDir = 'assets/sfx'

# The peak every material aims for, in dBFS. -9 sits a few dB above the BGM peak
# (measured -11 to -12 across the library) so UI sounds cut through the music, and
# eight of them at once still sum to roughly 0 dBFS -- eight being the pool size in
# presentation/ui/sfx_player.gd. How far off still passes is -TolDb.
# Spec: doc/audio/sfx.md.
$TargetDb = -9.0

# Materials deliberately built away from the common level, and where they aim
# instead. ui_hover fires on every mouse-over and every text advance, so it is
# held under the rest on purpose. Listed here so the check stops flagging it.
$IntendedPeak = @{
  'ui_hover' = -11.0
}

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

$offTarget = @()

foreach ($name in $Names) {
  $src = Join-Path $SrcDir "$name.wav"
  $out = Join-Path $OutDir "$name.ogg"
  if (-not (Test-Path $src)) { throw "source not found: $src" }

  # Trim and encode in one pass. No gain filter: the level came off the fader.
  $enc = Invoke-Ffmpeg @('-y', '-loglevel', 'error', '-i', $src,
    '-af', $trim, '-c:a', 'libvorbis', '-q:a', $Quality, $out)
  if ($enc.ExitCode -ne 0) { throw "ffmpeg failed on ${name}: $($enc.Stderr)" }

  # Verify the container really holds Vorbis (Opus imports as valid=false in Godot).
  $codec = (& $Ffprobe -v error -select_streams a:0 -show_entries stream=codec_name `
    -of default=nw=1:nk=1 $out | Out-String).Trim()
  if ($codec -ne 'vorbis') { throw "expected vorbis, got '$codec': $out" }
  $dur = (& $Ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $out | Out-String).Trim()

  # Measure what actually shipped, not the source: the encode moves the peak slightly.
  $probe = Invoke-Ffmpeg @('-hide_banner', '-i', $out, '-af', 'volumedetect', '-f', 'null', '-')
  if ($probe.ExitCode -ne 0) { throw "ffmpeg failed to measure ${name}: $($probe.Stderr)" }
  if ($probe.Stderr -notmatch 'max_volume:\s*(-?[0-9.]+) dB') { throw "could not measure peak: $name" }
  $peak = [double]$Matches[1]

  $want = if ($IntendedPeak.ContainsKey($name)) { [double]$IntendedPeak[$name] } else { $TargetDb }
  $off = $peak - $want
  $note = if ($IntendedPeak.ContainsKey($name)) { ' (own target)' } else { '' }
  $mark = if ([Math]::Abs($off) -gt $TolDb) { ' <-- OFF' } else { '' }
  if ([Math]::Abs($off) -gt $TolDb) { $offTarget += $name }

  '{0,-14} {1,7:0.000}s  peak {2,6:0.0} dBFS  (want {3,5:0.0}{4}, off {5,5:0.0}){6}' -f `
    $name, [double]$dur, $peak, $want, $note, $off, $mark | Write-Host
}

Write-Host ''
if ($offTarget.Count -gt 0) {
  Write-Warning ("Off target by more than $TolDb dB: " + ($offTarget -join ', '))
  Write-Warning "Fix the level on the MuseScore mixer master fader and export again."
  Write-Warning "The fader is 1:1 -- move it by the 'off' value shown above, with the sign flipped."
  Write-Warning "If the difference is deliberate, add the material to `$IntendedPeak in this script."
  Write-Host ''
}
Write-Host 'Run the Godot import so the new files register:'
Write-Host '  godot --headless --path . --import'
