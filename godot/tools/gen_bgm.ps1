<#
.SYNOPSIS
  Build a game-ready looping BGM track (.ogg) from a MuseScore .wav export.

.DESCRIPTION
  Takes assets/bgm-src/<name>.wav and writes assets/bgm/<name>.ogg, doing the
  whole loop dance that every track needs and none of it by hand:

    1. Derive the loop length from the score. MuseScore pads the export with the
       reverb tail, so the file is always longer than one time round. Reading
       assets/bgm-src/<name>.mscz (a zip holding .mscx) for bar count, time
       signature and tempo gives the exact length -- guessing from the waveform
       does not, because the tail fades smoothly into nothing.
         L = bars * (sigN * 4 / sigD) / tempo      (tempo is quarters per second)
    2. Fold the tail back onto the head. Cutting at L alone leaves a silent gap
       every time round; a real loop is "one time round" PLUS "the reverb bleeding
       in from the previous pass", so the cut-off tail is added at the start.
       The sum is checked for clipping against the source peak.
    3. Encode Ogg Vorbis. Godot reads Vorbis only -- an .ogg holding Opus fails to
       import (valid=false). The encoder is pinned to libvorbis and the codec is
       verified after writing.
    4. Import into Godot with loop=true. The importer defaults to loop=false, and
       a plain re-import will NOT pick up a hand-edited flag, so the generated
       files under .godot/imported/ are deleted first to force regeneration.

  Loudness is reported, not corrected. Level belongs in the MuseScore mixer (see
  doc/audio/bgm.md): build the balance with the per-track faders, set the overall
  level with master. Applying gain here would put the .ogg out of step with the
  score it came from.

  Stingers (victory / defeat) do not loop: pass -Stinger to skip steps 1-2 and
  keep the tail. loop stays false.

  Spec: doc/audio/bgm.md. Requires ffmpeg (searched on PATH, then winget).
  NOTE: keep this file ASCII-only. Windows PowerShell 5.1 mis-decodes UTF-8 .ps1.

.EXAMPLE
  powershell -File tools\gen_bgm.ps1 dungeon
  powershell -File tools\gen_bgm.ps1 journey raid dungeon graveyard
  powershell -File tools\gen_bgm.ps1 victory -Stinger
  powershell -File tools\gen_bgm.ps1 forest -LoopSec 76.8   # score has repeats/pickup
  powershell -File tools\gen_bgm.ps1 dungeon -NoImport      # files only, no Godot
#>

# PositionalBinding=$false keeps the optional switches named-only, so every bare
# argument falls through to $Names (otherwise the 2nd name binds to -LoopSec).
[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$Names,               # track_id(s); reads assets/bgm-src/<name>.wav
  [switch]$Stinger,               # one-shot (victory/defeat): no loop fold, keep the tail
  [double]$LoopSec = 0,           # override the derived loop length (0 = derive from .mscz)
  [int]$Quality = 6,              # libvorbis -q:a (6 is about 160kbps)
  [double]$TargetLufs = -23.0,    # library target; reported only, never applied
  [double]$LufsTolerance = 1.5,   # how far off before the line is flagged
  [switch]$NoImport               # skip the Godot import step
)
$ErrorActionPreference = 'Stop'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture

$SrcDir = 'assets/bgm-src'
$OutDir = 'assets/bgm'

function Find-Exe([string]$exe) {
  $cmd = Get-Command $exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path $winget) {
    $hit = Get-ChildItem -Path $winget -Filter "$exe*.exe" -Recurse -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

$Ffmpeg = Find-Exe 'ffmpeg'
if (-not $Ffmpeg) { throw "ffmpeg not found. Install it (winget install Gyan.FFmpeg) or add it to PATH." }
$Ffprobe = Find-Exe 'ffprobe'
if (-not $Ffprobe) { throw "ffprobe not found (ships with ffmpeg)." }

# ffmpeg reports everything on stderr. Piping that through PowerShell 5.1 with 2>&1
# wraps each line in an ErrorRecord and trips $ErrorActionPreference='Stop' even on a
# clean exit, so route stderr to a file instead and read it back.
function Invoke-Ffmpeg([string[]]$FfArgs) {
  $errFile = [System.IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath $Ffmpeg -ArgumentList $FfArgs -NoNewWindow -Wait `
                       -RedirectStandardError $errFile -PassThru
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Stderr = (Get-Content $errFile -Raw) }
  } finally {
    Remove-Item $errFile -Force -ErrorAction SilentlyContinue
  }
}

function Get-Duration([string]$path) {
  [double]::Parse((& $Ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $path |
                   Out-String).Trim(), $Inv)
}

# Sample peak in dBFS. Reading a float file lets the sum exceed 0 without being clamped
# first, which is the whole point of the clipping check.
function Get-Peak([string]$path) {
  $r = Invoke-Ffmpeg @('-hide_banner', '-i', $path, '-af', 'volumedetect', '-f', 'null', '-')
  if ($r.Stderr -notmatch 'max_volume:\s*(-?[0-9.]+) dB') { throw "could not measure peak: $path" }
  [double]::Parse($Matches[1], $Inv)
}

# Integrated loudness (EBU R128 / ITU-R BS.1770). This is what decides whether two
# tracks sound equally loud; peak does not.
function Get-Lufs([string]$path) {
  $r = Invoke-Ffmpeg @('-hide_banner', '-i', $path, '-af', 'ebur128', '-f', 'null', '-')
  $m = [regex]::Matches($r.Stderr, 'I:\s*(-?[0-9.]+)\s*LUFS')
  if ($m.Count -eq 0) { return [double]::NaN }
  [double]::Parse($m[$m.Count - 1].Groups[1].Value, $Inv)   # last block = the summary
}

# Read bar count / time signature / tempo out of the .mscz (a zip holding one .mscx).
# Assumes a single tempo, a single time signature and no repeats or pickup bars --
# true for every track so far. Use -LoopSec when that stops holding.
function Get-LoopSecondsFromScore([string]$mscz) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $mscz))
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName -like '*.mscx' -and $_.FullName -notlike 'META-INF/*' } |
             Select-Object -First 1
    if (-not $entry) { throw "no .mscx inside: $mscz" }
    $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try { $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally { $zip.Dispose() }

  if ($xml -notmatch '<sigN>(\d+)</sigN>') { throw "no time signature in: $mscz" }
  $sigN = [int]$Matches[1]
  if ($xml -notmatch '<sigD>(\d+)</sigD>') { throw "no time signature in: $mscz" }
  $sigD = [int]$Matches[1]
  if ($xml -notmatch '<tempo>([0-9.]+)</tempo>') { throw "no tempo in: $mscz" }
  $tempo = [double]::Parse($Matches[1], $Inv)      # quarter notes per second

  # Part definitions carry <Staff id=..> too, but without measures. Take the widest
  # staff so those empty ones cannot win.
  $bars = 0
  foreach ($blk in [regex]::Matches($xml, '<Staff id="[^"]+">(.*?)</Staff>', 'Singleline')) {
    $n = ([regex]::Matches($blk.Groups[1].Value, '<Measure')).Count
    if ($n -gt $bars) { $bars = $n }
  }
  if ($bars -eq 0) { throw "no measures found in: $mscz" }

  $quartersPerBar = $sigN * 4.0 / $sigD
  return [pscustomobject]@{
    Bars    = $bars
    SigN    = $sigN
    SigD    = $sigD
    Bpm     = $tempo * 60.0
    Seconds = $bars * $quartersPerBar / $tempo
  }
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$made = @()

foreach ($name in $Names) {
  $src = Join-Path $SrcDir "$name.wav"
  $out = Join-Path $OutDir "$name.ogg"
  if (-not (Test-Path $src)) { throw "source not found: $src" }

  $srcDur  = Get-Duration $src
  $srcPeak = Get-Peak $src

  # Head silence would be baked into every pass of the loop, and reads as a stall.
  $sil = Invoke-Ffmpeg @('-hide_banner', '-i', $src, '-af', 'silencedetect=noise=-60dB:d=0.1', '-f', 'null', '-')
  if ($sil.Stderr -match 'silence_start:\s*(-?[0-9.]+)') {
    if ([double]::Parse($Matches[1], $Inv) -lt 0.05) {
      Write-Warning "${name}: starts with silence -- trim it before looping."
    }
  }

  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "genbgm_$name.wav"
  try {
    if ($Stinger) {
      $loopSecs = $srcDur          # no fold: the tail is the point
      $encIn = $src
    } else {
      if ($LoopSec -gt 0) {
        $loopSecs = $LoopSec
        $from = 'given'
      } else {
        $mscz = Join-Path $SrcDir "$name.mscz"
        if (-not (Test-Path $mscz)) { throw "no score to derive the loop length from: $mscz (pass -LoopSec)" }
        $score = Get-LoopSecondsFromScore $mscz
        $loopSecs = $score.Seconds
        $from = '{0} bars {1}/{2} {3:0.#}bpm' -f $score.Bars, $score.SigN, $score.SigD, $score.Bpm
      }
      $tail = $srcDur - $loopSecs
      if ($tail -le 0.001) {
        throw ("{0}: export ({1:0.000}s) is not longer than the loop ({2:0.000}s) -- wrong score or wrong -LoopSec." -f $name, $srcDur, $loopSecs)
      }
      if ($tail -ge $loopSecs) {
        throw ("{0}: reverb tail ({1:0.000}s) is not shorter than the loop ({2:0.000}s). Export two times round and cut [L,2L] instead (doc/audio/bgm.md)." -f $name, $tail, $loopSecs)
      }

      $L = $loopSecs.ToString('0.000000', $Inv)
      $filter = "[0]atrim=0:$L,asetpts=PTS-STARTPTS[body];" +
                "[1]atrim=$L,asetpts=PTS-STARTPTS,apad=whole_dur=$L[tail];" +
                "[body][tail]amix=inputs=2:normalize=0:duration=first[out]"
      # normalize=0 is required: amix halves the level otherwise. Float out so the
      # clipping check below sees the true sum instead of a clamped one.
      $fold = Invoke-Ffmpeg @('-y', '-loglevel', 'error', '-i', $src, '-i', $src,
        '-filter_complex', $filter, '-map', '[out]', '-c:a', 'pcm_f32le', $tmp)
      if ($fold.ExitCode -ne 0) { throw "ffmpeg failed to fold ${name}: $($fold.Stderr)" }

      $foldPeak = Get-Peak $tmp
      if ($foldPeak -gt $srcPeak + 0.1) {
        throw ("{0}: folding the tail raised the peak {1:0.0} -> {2:0.0} dBFS (clipping). Lower the master in MuseScore and export again." -f $name, $srcPeak, $foldPeak)
      }
      $encIn = $tmp
    }

    $enc = Invoke-Ffmpeg @('-y', '-loglevel', 'error', '-i', $encIn,
      '-c:a', 'libvorbis', '-q:a', $Quality, $out)
    if ($enc.ExitCode -ne 0) { throw "ffmpeg failed to encode ${name}: $($enc.Stderr)" }
  } finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }

  # An .ogg holding Opus imports as valid=false in Godot, so check what actually landed.
  $codec = (& $Ffprobe -v error -select_streams a:0 -show_entries stream=codec_name `
    -of default=nw=1:nk=1 $out | Out-String).Trim()
  if ($codec -ne 'vorbis') { throw "expected vorbis, got '$codec': $out" }

  $outDur = Get-Duration $out
  if (-not $Stinger -and [math]::Abs($outDur - $loopSecs) -gt 0.01) {
    throw ("{0}: encoded length {1:0.000}s does not match the loop {2:0.000}s." -f $name, $outDur, $loopSecs)
  }

  # Stingers are one-shot events and deliberately sit apart from the loop tracks, so
  # the library target does not apply to them -- report the number, do not flag it.
  $lufs = Get-Lufs $out
  $flag = ''
  if (-not $Stinger -and -not [double]::IsNaN($lufs) -and [math]::Abs($lufs - $TargetLufs) -gt $LufsTolerance) {
    $flag = '  <-- off target ({0:0.0})' -f $TargetLufs
  }
  $kind = if ($Stinger) { 'stinger' } else { $from }
  '{0,-12} {1,8:0.000}s  {2,6:0.0} LUFS  peak {3,6:0.0} dBFS  [{4}]{5}' -f `
    $name, $outDur, $lufs, $srcPeak, $kind, $flag | Write-Host

  $made += [pscustomobject]@{ Name = $name; Out = $out; Loop = (-not $Stinger) }
}

# --- Godot import (loop=true) ---
# The importer writes loop=false, and re-running --import will NOT pick up a hand-edited
# flag: it treats the existing generated file as current. Deleting the generated files
# under .godot/imported/ is what forces the flag to take effect.
if ($NoImport) {
  Write-Host ''
  Write-Host 'Skipped the import. Run it yourself, then set loop=true in the .import:'
  Write-Host '  godot --headless --path . --import'
  return
}

$Godot = Find-Exe 'Godot'
if (-not $Godot) {
  Write-Host ''
  Write-Warning 'Godot not found -- files are written but not imported. Run:'
  Write-Host '  godot --headless --path . --import'
  Write-Host '  then set loop=true in assets/bgm/<name>.ogg.import, delete the matching'
  Write-Host '  .godot/imported/<name>.ogg-* files, and import once more.'
  return
}

function Invoke-GodotImport {
  $p = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', '.', '--import') `
                     -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "godot --import failed (exit $($p.ExitCode))" }
}

Write-Host ''
Write-Host 'Importing...'
Invoke-GodotImport

$needsSecondPass = $false
foreach ($m in $made) {
  if (-not $m.Loop) { continue }
  $importFile = "$($m.Out).import"
  if (-not (Test-Path $importFile)) { Write-Warning "no .import produced for $($m.Name)"; continue }
  $text = [System.IO.File]::ReadAllText($importFile)
  if ($text -notmatch 'loop=false') { continue }   # already true

  # Drop the generated files so the new flag actually regenerates them.
  if ($text -match 'path="res://\.godot/imported/([^"]+)"') {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Matches[1])
    Get-ChildItem '.godot/imported' -Filter "$stem.*" -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue
  }
  $text = $text -replace 'loop=false', 'loop=true'
  [System.IO.File]::WriteAllText($importFile, $text, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("  {0}: loop=true" -f $m.Name)
  $needsSecondPass = $true
}

if ($needsSecondPass) { Invoke-GodotImport }

Write-Host ''
Write-Host 'Done. Commit the .ogg and the .import (both are generated but tracked).'
