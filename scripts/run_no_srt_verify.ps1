# Verify: no SRT/subtitles; TTS toggle; ZIP contents (TXT + MP3 only)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"

Init-TestLog "no_srt_verify"
Assert-Backend

$outDir = $script:TestOutDir
$backendRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "backend"
$pass = 0
$fail = 0

function Check([string]$name, [bool]$ok, [string]$detail = "") {
    if ($ok) {
        $script:pass++
        Log "PASS $name $(if ($detail) { "- $detail" })"
        Write-Host "  [PASS] $name $detail" -ForegroundColor Green
    } else {
        $script:fail++
        Log "FAIL $name $(if ($detail) { "- $detail" })"
        Write-Host "  [FAIL] $name $detail" -ForegroundColor Red
    }
}

function New-ProjectRaw([bool]$GenerateTts) {
    $r = Invoke-Api -Method POST -Path "/api/projects" -Body @{
        project_name  = "verify-tts-$(Get-Date -Format 'HHmmss')"
        title         = "Verify-NoSRT"
        target_words  = 5000
        chapter_words = 2000
        language      = "中文"
        generate_tts  = $GenerateTts
    }
    if (-not $r.ok) { throw "Create failed: $($r.detail)" }
    return $r.body
}

function Get-Chapters([int]$ProjectId) {
    $r = Invoke-Api -Method GET -Path "/api/projects/$ProjectId/chapters"
    if (-not $r.ok) { throw "List chapters failed: $($r.detail)" }
    return @($r.body)
}

function Inspect-OutputDir([int]$ProjectId) {
    $dir = Join-Path $backendRoot "output\project_$ProjectId"
    $hasSubtitles = Test-Path (Join-Path $dir "subtitles")
    $srtFiles = @()
    if (Test-Path $dir) {
        $srtFiles = Get-ChildItem -Path $dir -Recurse -Filter "*.srt" -ErrorAction SilentlyContinue
    }
    return @{
        dir          = $dir
        hasSubtitles = $hasSubtitles
        srtCount     = @($srtFiles).Count
        mp3Count     = if (Test-Path $dir) { @(Get-ChildItem -Path $dir -Recurse -Filter "*.mp3" -ErrorAction SilentlyContinue).Count } else { 0 }
    }
}

function Inspect-Zip([string]$ZipPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        $srt = @($entries | Where-Object { $_ -match '\.srt$' -or $_ -match '^subtitles/' })
        $txt = @($entries | Where-Object { $_ -match '\.txt$' })
        $mp3 = @($entries | Where-Object { $_ -match '\.mp3$' })
        return @{
            entries = $entries
            srt     = $srt
            txt     = $txt
            mp3     = $mp3
        }
    } finally {
        $zip.Dispose()
    }
}

Write-Host "`n=== Step 1-2: Create projects, test TTS toggle ===" -ForegroundColor Cyan

# OFF: create + verify flag + first 3 without auto MP3
$pOff = New-ProjectRaw -GenerateTts $false
Check "create-project-tts-off" ($null -ne $pOff.id) "id=$($pOff.id) generate_tts=$($pOff.generate_tts)"

$tOff = Invoke-Api -Method POST -Path "/api/projects/$($pOff.id)/apply-template" -Body @{ template_key = "tycoon_revenge" }
Check "apply-template-off" $tOff.ok

$f3Off = Invoke-Api -Method POST -Path "/api/projects/$($pOff.id)/generate-first-3" -Body @{
    voice_key = "zh_female"
    rate      = "+0%"
} -TimeoutSec 900
Check "first3-off-content" ($f3Off.ok -and $f3Off.body.generated_chapters.Count -ge 1) "generated=$($f3Off.body.generated_chapters -join ',')"

$chsOff = Get-Chapters -ProjectId $pOff.id
$mp3Off = 0
foreach ($ch in ($chsOff | Select-Object -First 3)) {
    if ($ch.audio_path -and (Test-Path ([string]$ch.audio_path))) { $mp3Off++ }
}
Check "tts-off-no-auto-mp3" ($mp3Off -eq 0) "mp3_files=$mp3Off (expect 0)"

# ON: create + verify flag
$pOn = New-ProjectRaw -GenerateTts $true
Check "create-project-tts-on" ($null -ne $pOn.id) "id=$($pOn.id) generate_tts=$($pOn.generate_tts)"

# Toggle test on same project: turn OFF then ON via PUT
$putOff = Invoke-Api -Method PUT -Path "/api/projects/$($pOn.id)" -Body @{ generate_tts = $false }
$gotOff = [bool]$putOff.body.generate_tts -eq $false
$putOn = Invoke-Api -Method PUT -Path "/api/projects/$($pOn.id)" -Body @{ generate_tts = $true }
$gotOn = [bool]$putOn.body.generate_tts -eq $true
Check "toggle-tts-off" $gotOff "PUT generate_tts=false"
Check "toggle-tts-on" $gotOn "PUT generate_tts=true"

Write-Host "`n=== Step 3-5: Bible, outline, first 3 (TTS on) ===" -ForegroundColor Cyan

$tOn = Invoke-Api -Method POST -Path "/api/projects/$($pOn.id)/apply-template" -Body @{ template_key = "tycoon_revenge" }
Check "apply-template-on" $tOn.ok

$bible = Invoke-Api -Method POST -Path "/api/projects/$($pOn.id)/generate-bible" -TimeoutSec 300
Check "generate-bible" ($bible.ok -and $bible.body.story_bible.Length -gt 100) "len=$($bible.body.story_bible.Length)"

$outline = Invoke-Api -Method POST -Path "/api/projects/$($pOn.id)/generate-outline" -TimeoutSec 300
Check "generate-outline" $outline.ok

$f3On = Invoke-Api -Method POST -Path "/api/projects/$($pOn.id)/generate-first-3" -Body @{
    voice_key = "zh_female"
    rate      = "+0%"
} -TimeoutSec 900
Check "first3-on" ($f3On.ok -and $f3On.body.generated_chapters.Count -eq 3) "chapters=$($f3On.body.generated_chapters -join ',')"

Write-Host "`n=== Step 6-7: Status fields + no SRT/subtitles ===" -ForegroundColor Cyan

$chsOn = Get-Chapters -ProjectId $pOn.id
$sample = $chsOn | Select-Object -First 1
$fields = $sample.PSObject.Properties.Name
Check "chapter-has-status" ($fields -contains "status") "status=$($sample.status)"
Check "chapter-has-tts_status" ($fields -contains "tts_status") "tts_status=$($sample.tts_status)"
# API may still return legacy srt_status from DB; frontend must not use it
$noSrtInUi = -not ($fields -contains "srt_status" -and $sample.srt_status -eq "completed")
Check "no-srt-completed-in-api" $noSrtInUi "srt_status=$($sample.srt_status)"

$statusLines = @()
$mp3On = 0
foreach ($ch in ($chsOn | Where-Object { $_.chapter_number -le 3 })) {
    $hasMp3 = $ch.audio_path -and (Test-Path ([string]$ch.audio_path))
    if ($hasMp3) { $mp3On++ }
    $line = "ch$($ch.chapter_number) status=$($ch.status) tts=$($ch.tts_status)"
    $statusLines += $line
    Log $line
}
Write-Host ($statusLines -join "`n")
Check "only-content-tts-status" ($statusLines.Count -eq 3) "3 chapters checked"
Check "mp3-generated-on" ($mp3On -eq 3) "mp3=$mp3On/3"

$outInspect = Inspect-OutputDir -ProjectId $pOn.id
Check "no-subtitles-dir" (-not $outInspect.hasSubtitles) $outInspect.dir
Check "no-srt-files" ($outInspect.srtCount -eq 0) "srt_count=$($outInspect.srtCount)"

# Legacy SRT endpoints should 404
$srtEp = Invoke-Api -Method POST -Path "/api/projects/$($pOn.id)/generate-srt-range" -Body @{ start_chapter = 1; end_chapter = 1 }
Check "srt-range-endpoint-gone" (-not $srtEp.ok) $srtEp.detail

Write-Host "`n=== Step 8-9: Export full ZIP, inspect contents ===" -ForegroundColor Cyan

$zipPath = Join-Path $outDir "verify_project_$($pOn.id)_full.zip"
Invoke-WebRequest -Uri "$script:ApiBase/api/projects/$($pOn.id)/export/full-zip" -OutFile $zipPath -TimeoutSec 120 -UseBasicParsing
Check "export-full-zip" (Test-Path $zipPath) "$((Get-Item $zipPath).Length) bytes"

$zi = Inspect-Zip -ZipPath $zipPath
Log "ZIP entries: $($zi.entries -join ' | ')"
Check "zip-no-srt" ($zi.srt.Count -eq 0) "srt_entries=$($zi.srt.Count)"
Check "zip-has-txt" ($zi.txt.Count -gt 0) "txt=$($zi.txt.Count)"
Check "zip-has-mp3" ($zi.mp3.Count -gt 0) "mp3=$($zi.mp3.Count)"

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Project TTS-OFF id=$($pOff.id)  Project TTS-ON id=$($pOn.id)" -ForegroundColor Yellow
Write-Host "ZIP: $zipPath" -ForegroundColor Yellow
Write-Host "PASS=$pass  FAIL=$fail" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
Log "DONE pass=$pass fail=$fail zip=$zipPath"

if ($fail -gt 0) { exit 1 }
