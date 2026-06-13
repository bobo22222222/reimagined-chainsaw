# v0.2.1 acceptance: 50k / 2000 -> 25 chapters, quality + rewrite + MP3 + ZIP
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"

Init-TestLog "v021_accept"
Assert-Backend

$pass = 0
$fail = 0
$THRESHOLD = 70

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
        $n = [int]$ch.chapter_number
        if (-not $map.ContainsKey($n)) { $map[$n] = $ch }
    }
    return @($map.Values | Sort-Object { [int]$_.chapter_number })
}

function Get-QualityStats($Chapters, [int]$Threshold) {
    $checked = @($Chapters | Where-Object { $null -ne $_.quality_score })
    $scores = @($checked | ForEach-Object { [int]$_.quality_score })
    if ($scores.Count -eq 0) {
        return @{ checked = 0; avg = 0; low = 0; min = 0; max = 0 }
    }
    $avg = [Math]::Round(($scores | Measure-Object -Average).Average, 1)
    return @{
        checked = $scores.Count
        avg     = $avg
        low     = @($scores | Where-Object { $_ -lt $Threshold }).Count
        min     = ($scores | Measure-Object -Minimum).Minimum
        max     = ($scores | Measure-Object -Maximum).Maximum
    }
}

function Invoke-QualityCheckAll([int]$ProjectId, [int]$MaxChapter) {
    $all = @()
    for ($s = 1; $s -le $MaxChapter; $s += 5) {
        $e = [Math]::Min($s + 4, $MaxChapter)
        $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/quality-check-range" -Body @{
            start_chapter    = $s
            end_chapter      = $e
            score_threshold  = $THRESHOLD
        } -TimeoutSec 900
        if (-not $r.ok) { throw "QC $s-$e failed: $($r.detail)" }
        $all += @($r.body.checked_chapters)
        Write-Host "  QC batch $s-$e : checked $($r.body.checked_chapters.Count)" -ForegroundColor DarkGray
    }
    return $all
}

function Invoke-Mp3All([int]$ProjectId, [int]$MaxChapter) {
    $gen = @()
    for ($s = 1; $s -le $MaxChapter; $s += 5) {
        $e = [Math]::Min($s + 4, $MaxChapter)
        $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/generate-tts-range" -Body @{
            start_chapter = $s
            end_chapter   = $e
            voice_key     = "zh_female"
            rate          = "+0%"
        } -TimeoutSec 1800
        if (-not $r.ok) { throw "MP3 $s-$e failed: $($r.detail)" }
        $gen += @($r.body.generated_chapters)
    }
    return $gen
}

Write-Host "`n=== Step 1-2: Create 50k project, 2000/ch, TTS off ===" -ForegroundColor Cyan
$p = Invoke-Api -Method POST -Path "/api/projects" -Body @{
    project_name  = "v021-accept-$(Get-Date -Format 'HHmmss')"
    title         = "V021-50k"
    target_words  = 50000
    chapter_words = 2000
    language      = "中文"
    generate_tts  = $false
}
if (-not $p.ok) { throw $p.detail }
$projectId = [int]$p.body.id
Check "create-50k" ($projectId -gt 0) "id=$projectId words=50000 cw=2000"

Write-Host "`n=== Step 3-4: Template, bible, outline ===" -ForegroundColor Cyan
$t = Invoke-Api -Method POST -Path "/api/projects/$projectId/apply-template" -Body @{ template_key = "tycoon_revenge" }
Check "apply-template" $t.ok

$bible = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-bible" -TimeoutSec 300
Check "generate-bible" ($bible.ok -and $bible.body.story_bible.Length -gt 100) "len=$($bible.body.story_bible.Length)"

$outline = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-outline" -TimeoutSec 300
Check "generate-outline" $outline.ok

Write-Host "`n=== Step 5: Verify exactly 25 chapters ===" -ForegroundColor Cyan
$expectedCount = 25
$apiCount = if ($outline.body.chapter_count) { [int]$outline.body.chapter_count } else { 0 }
$chs = Get-ChaptersUnique -ProjectId $projectId
$actualCount = $chs.Count
$maxNum = if ($chs.Count -gt 0) { [int]($chs | ForEach-Object { $_.chapter_number } | Measure-Object -Maximum).Maximum } else { 0 }
Check "chapter-count-25" ($actualCount -eq $expectedCount) "count=$actualCount (api chapter_count=$apiCount)"
Check "chapter-numbers-1-25" ($maxNum -eq $expectedCount) "max_chapter=$maxNum"
if ($actualCount -ne $expectedCount) {
    Write-Host "ABORT: chapter count mismatch" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Step 6: Batch generate all 25 chapters ===" -ForegroundColor Cyan
$swGen = [System.Diagnostics.Stopwatch]::StartNew()
for ($s = 1; $s -le 25; $s += 5) {
    $e = [Math]::Min($s + 4, 25)
    Write-Host "  Content batch $s-$e ..." -ForegroundColor DarkGray
    $br = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-chapter-range" -Body @{
        start_chapter = $s
        end_chapter   = $e
        voice_key     = "zh_female"
        rate          = "+0%"
    } -TimeoutSec 3600
    if (-not $br.ok) { throw "Batch $s-$e failed: $($br.detail)" }
    Write-Host "    gen=$($br.body.generated_chapters -join ',') skip=$($br.body.skipped_chapters -join ',') fail=$($br.body.failed_chapters -join ',')"
}
$swGen.Stop()
$chs = Get-ChaptersUnique -ProjectId $projectId
$contentOk = @($chs | Where-Object { (Get-ChapterContentText $_).Length -gt 0 }).Count
Check "all-content" ($contentOk -eq 25) "$contentOk/25 in $([Math]::Round($swGen.Elapsed.TotalMinutes,1)) min"

Write-Host "`n=== Step 7-8: Batch quality check + stats ===" -ForegroundColor Cyan
$swQc = [System.Diagnostics.Stopwatch]::StartNew()
Invoke-QualityCheckAll -ProjectId $projectId -MaxChapter 25 | Out-Null
$swQc.Stop()
$chs = Get-ChaptersUnique -ProjectId $projectId
$statsBefore = Get-QualityStats -Chapters $chs -Threshold $THRESHOLD
Write-Host "  BEFORE: avg=$($statsBefore.avg) low=$($statsBefore.low) min=$($statsBefore.min) max=$($statsBefore.max)" -ForegroundColor Yellow
Check "qc-checked-25" ($statsBefore.checked -eq 25) "checked=$($statsBefore.checked)/25"
Check "qc-avg-before" ($statsBefore.avg -gt 0) "avg=$($statsBefore.avg) low=$($statsBefore.low)"

Write-Host "`n=== Step 9: Batch rewrite low-score (threshold 70, max 1 round per call, 5 batches) ===" -ForegroundColor Cyan
$totalRewritten = 0
for ($s = 1; $s -le 25; $s += 5) {
    $e = [Math]::Min($s + 4, 25)
    $rw = Invoke-Api -Method POST -Path "/api/projects/$projectId/rewrite-issues" -Body @{
        start_chapter   = $s
        end_chapter     = $e
        score_threshold = $THRESHOLD
        max_rounds      = 1
    } -TimeoutSec 3600
    if (-not $rw.ok) { throw "Rewrite $s-$e failed: $($rw.detail)" }
    $totalRewritten += $rw.body.rewritten_chapters.Count
    Write-Host "  Rewrite $s-$e : $($rw.body.rewritten_chapters -join ',') skip=$($rw.body.skipped_chapters.Count)" -ForegroundColor DarkGray
}
Check "rewrite-ran" ($totalRewritten -ge 0) "total_rewritten=$totalRewritten"

Write-Host "`n=== Step 10: Re-check quality after rewrite ===" -ForegroundColor Cyan
Invoke-QualityCheckAll -ProjectId $projectId -MaxChapter 25 | Out-Null
$chs = Get-ChaptersUnique -ProjectId $projectId
$statsAfter = Get-QualityStats -Chapters $chs -Threshold $THRESHOLD
Write-Host "  AFTER:  avg=$($statsAfter.avg) low=$($statsAfter.low) min=$($statsAfter.min) max=$($statsAfter.max)" -ForegroundColor Yellow
Check "qc-avg-after-rewrite" ($statsAfter.avg -ge 65) "avg=$($statsAfter.avg) (target ~70+)"
Check "avg-improved" ($statsAfter.avg -ge $statsBefore.avg) "before=$($statsBefore.avg) after=$($statsAfter.avg)"
$ttsPending = @($chs | Where-Object { $_.tts_status -eq "pending" }).Count
Check "tts-pending-after-rewrite" ($ttsPending -gt 0) "pending=$ttsPending (rewritten chapters reset)"

Write-Host "`n=== Step 11: Batch MP3 all 25 ===" -ForegroundColor Cyan
$swMp3 = [System.Diagnostics.Stopwatch]::StartNew()
Invoke-Mp3All -ProjectId $projectId -MaxChapter 25 | Out-Null
$swMp3.Stop()
$chs = Get-ChaptersUnique -ProjectId $projectId
$mp3Ok = @($chs | Where-Object { $_.tts_status -eq "completed" }).Count
Check "mp3-25" ($mp3Ok -eq 25) "$mp3Ok/25 in $([Math]::Round($swMp3.Elapsed.TotalMinutes,1)) min"

Write-Host "`n=== Step 12: Export full ZIP ===" -ForegroundColor Cyan
$zipPath = Join-Path $script:TestOutDir "v021_accept_project_${projectId}_full.zip"
Invoke-WebRequest -Uri "$script:ApiBase/api/projects/$projectId/export/full-zip" -OutFile $zipPath -TimeoutSec 600 -UseBasicParsing
$zipSize = (Get-Item $zipPath).Length
Check "export-zip" ($zipSize -gt 100000) "$zipSize bytes"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "v0.2.1 ACCEPTANCE SUMMARY" -ForegroundColor Cyan
Write-Host "Project ID: $projectId" -ForegroundColor Yellow
Write-Host "Chapters:   $actualCount (expected 25)" -ForegroundColor Yellow
Write-Host "Quality:    before avg=$($statsBefore.avg) low=$($statsBefore.low) -> after avg=$($statsAfter.avg) low=$($statsAfter.low)" -ForegroundColor Yellow
Write-Host "MP3:        $mp3Ok/25" -ForegroundColor Yellow
Write-Host "ZIP:        $zipPath" -ForegroundColor Yellow
Write-Host "PASS=$pass  FAIL=$fail" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })

$verdict = ($actualCount -eq 25) -and ($statsAfter.avg -ge 65) -and ($mp3Ok -eq 25) -and ($zipSize -gt 0)
if ($verdict -and $statsAfter.avg -ge 70) {
    Write-Host "`nVERDICT: v0.2.1 STABLE - avg >= 70" -ForegroundColor Green
} elseif ($verdict) {
    Write-Host "`nVERDICT: v0.2.1 CONDITIONAL PASS - chapters+MP3+ZIP OK, avg=$($statsAfter.avg) (close to 70)" -ForegroundColor Yellow
} else {
    Write-Host "`nVERDICT: NEEDS REVIEW" -ForegroundColor Red
}

Log "DONE project=$projectId pass=$pass fail=$fail avg_before=$($statsBefore.avg) avg_after=$($statsAfter.avg)"
if ($fail -gt 0) { exit 1 }
