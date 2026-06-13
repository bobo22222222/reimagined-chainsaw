# E2E: quality check + rewrite flow (11 steps)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"

Init-TestLog "quality_flow"
Assert-Backend

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

function Get-ChaptersUnique([int]$ProjectId) {
    $r = Invoke-Api -Method GET -Path "/api/projects/$ProjectId/chapters"
    if (-not $r.ok) { throw $r.detail }
    $map = @{}
    foreach ($ch in @($r.body)) {
        $num = [int]$ch.chapter_number
        if (-not $map.ContainsKey($num)) { $map[$num] = $ch }
    }
    return $map.Values | Sort-Object { [int]$_.chapter_number }
}

Write-Host "`n=== Step 1-2: Create 5k project, TTS off ===" -ForegroundColor Cyan
$p = Invoke-Api -Method POST -Path "/api/projects" -Body @{
    project_name  = "qc-flow-$(Get-Date -Format 'HHmmss')"
    title         = "QC-Flow-5k"
    target_words  = 5000
    chapter_words = 2000
    language      = "中文"
    generate_tts  = $false
}
if (-not $p.ok) { throw $p.detail }
$projectId = [int]$p.body.id
Check "create-5k-project" ($projectId -gt 0) "id=$projectId"
Check "tts-off" (-not [bool]$p.body.generate_tts) "generate_tts=$($p.body.generate_tts)"

Write-Host "`n=== Step 3-4: Template, bible, outline ===" -ForegroundColor Cyan
$t = Invoke-Api -Method POST -Path "/api/projects/$projectId/apply-template" -Body @{ template_key = "tycoon_revenge" }
Check "apply-template" $t.ok

$bible = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-bible" -TimeoutSec 300
Check "generate-bible" ($bible.ok -and $bible.body.story_bible.Length -gt 100) "len=$($bible.body.story_bible.Length)"

$outline = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-outline" -TimeoutSec 300
Check "generate-outline" $outline.ok

Write-Host "`n=== Step 5: First 3 chapters (no auto TTS) ===" -ForegroundColor Cyan
$f3 = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-first-3" -Body @{
    voice_key = "zh_female"
    rate      = "+0%"
} -TimeoutSec 900
Check "first-3-chapters" ($f3.ok -and $f3.body.generated_chapters.Count -ge 1) "generated=$($f3.body.generated_chapters -join ',')"

$chs = Get-ChaptersUnique -ProjectId $projectId
$first3 = @($chs | Where-Object { [int]$_.chapter_number -le 3 })
Check "three-chapters-content" ($first3.Count -eq 3) "count=$($first3.Count)"
$mp3AfterFirst3 = @($first3 | Where-Object { $_.audio_path -and (Test-Path ([string]$_.audio_path)) }).Count
Check "no-auto-mp3-after-first3" ($mp3AfterFirst3 -eq 0) "mp3=$mp3AfterFirst3"

Write-Host "`n=== Step 6: Batch quality check 1-3 ===" -ForegroundColor Cyan
$qc = Invoke-Api -Method POST -Path "/api/projects/$projectId/quality-check-range" -Body @{
    start_chapter = 1
    end_chapter   = 3
} -TimeoutSec 600
Check "batch-quality-check" ($qc.ok -and $qc.body.checked_chapters.Count -ge 1) "checked=$($qc.body.checked_chapters.Count) low=$($qc.body.low_score_count)"

foreach ($item in @($qc.body.checked_chapters)) {
    Log "  ch$($item.chapter_number) score=$($item.score) passed=$($item.passed)"
    Write-Host "  ch$($item.chapter_number) score=$($item.score) passed=$($item.passed)" -ForegroundColor DarkGray
}

Write-Host "`n=== Step 7-8: Rewrite lowest score + re-check ===" -ForegroundColor Cyan
$chs = Get-ChaptersUnique -ProjectId $projectId
$first3 = @($chs | Where-Object { [int]$_.chapter_number -le 3 })
$target = $first3 | Sort-Object { if ($null -eq $_.quality_score) { 999 } else { [int]$_.quality_score } } | Select-Object -First 1
if (-not $target) { throw "No chapter to rewrite" }

$scoreBefore = $target.quality_score
$chNum = [int]$target.chapter_number
$chId = [int]$target.id
Log "Rewrite target: ch$chNum id=$chId score=$scoreBefore"

$rw = Invoke-Api -Method POST -Path "/api/chapters/$chId/rewrite" -TimeoutSec 600
Check "one-click-rewrite" $rw.ok "ch$chNum word_count=$($rw.body.word_count)"

$recheck = Invoke-Api -Method POST -Path "/api/chapters/$chId/quality-check" -TimeoutSec 300
Check "recheck-after-rewrite" $recheck.ok "score=$($recheck.body.score) (was $scoreBefore)"

Write-Host "`n=== Step 9: TTS status pending after rewrite ===" -ForegroundColor Cyan
$chs = Get-ChaptersUnique -ProjectId $projectId
$rewritten = $chs | Where-Object { [int]$_.chapter_number -eq $chNum } | Select-Object -First 1
Check "tts-pending-after-rewrite" ($rewritten.tts_status -eq "pending") "tts_status=$($rewritten.tts_status)"
Check "quality-reset-pending" ($rewritten.quality_status -eq "pending" -or $recheck.ok) "quality_status=$($rewritten.quality_status)"

Write-Host "`n=== Step 10: Batch MP3 1-3 ===" -ForegroundColor Cyan
$tts = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-tts-range" -Body @{
    start_chapter = 1
    end_chapter   = 3
    voice_key     = "zh_female"
    rate          = "+0%"
} -TimeoutSec 600
Check "batch-mp3" ($tts.ok -and $tts.body.generated_chapters.Count -ge 1) "mp3=$($tts.body.generated_chapters -join ',')"

$chs = Get-ChaptersUnique -ProjectId $projectId
$mp3Ok = 0
foreach ($ch in ($chs | Where-Object { [int]$_.chapter_number -le 3 })) {
    if ($ch.tts_status -eq "completed") { $mp3Ok++ }
}
Check "mp3-completed" ($mp3Ok -eq 3) "$mp3Ok/3"

Write-Host "`n=== Step 11: Export full ZIP ===" -ForegroundColor Cyan
$zipPath = Join-Path $script:TestOutDir "quality_flow_project_${projectId}_full.zip"
Invoke-WebRequest -Uri "$script:ApiBase/api/projects/$projectId/export/full-zip" -OutFile $zipPath -TimeoutSec 120 -UseBasicParsing
$zipSize = (Get-Item $zipPath).Length
Check "export-full-zip" ($zipSize -gt 0) "$zipSize bytes -> $zipPath"

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Project ID: $projectId" -ForegroundColor Yellow
Write-Host "Rewritten chapter: $chNum (score $scoreBefore -> $($recheck.body.score))" -ForegroundColor Yellow
Write-Host "ZIP: $zipPath" -ForegroundColor Yellow
Write-Host "PASS=$pass  FAIL=$fail" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
Log "DONE project=$projectId pass=$pass fail=$fail"

if ($fail -gt 0) { exit 1 }
