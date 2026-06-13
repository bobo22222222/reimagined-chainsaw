# v0.3 full-work production test: generate -> QC -> rewrite -> TTS -> ZIP
# Usage: powershell -ExecutionPolicy Bypass -File scripts\run_v03_full_work_test.ps1
# Optional env: $env:V03_WORK_ONLY = "zh"  # run single language
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"

Init-TestLog "v03_full_work"
Assert-Backend

$ReportFile = Join-Path $script:TestOutDir "V03_FULL_WORK_REPORT.txt"
$startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$THRESHOLD = 70

# Production-scale targets (adjustable)
$WORKS = @(
    @{ lang = "zh"; target = 20000; chapter_words = 2000; title = "V03-Work-ZH-20k" }
    @{ lang = "en"; target = 10000; chapter_words = 2000; title = "V03-Work-EN-10k" }
    @{ lang = "es"; target = 10000; chapter_words = 2000; title = "V03-Work-ES-10k" }
    @{ lang = "ja"; target = 10000; chapter_words = 2000; title = "V03-Work-JA-10k" }
)

if ($env:V03_WORK_ONLY) {
    $only = $env:V03_WORK_ONLY
    $WORKS = @($WORKS | Where-Object { $_.lang -eq $only })
    if (-not $WORKS) { throw "Unknown V03_WORK_ONLY=$only" }
}

function Get-ChaptersUnique {
    param([int]$ProjectId)
    $chs = Get-ChapterList -ProjectId $ProjectId
    $map = @{}
    foreach ($ch in $chs) {
        $n = [int]$ch.chapter_number
        if (-not $map.ContainsKey($n)) { $map[$n] = $ch }
    }
    return @($map.Values | Sort-Object { [int]$_.chapter_number })
}

function Get-QualityStats {
    param($Chapters, [int]$Threshold)
    $checked = @($Chapters | Where-Object { $null -ne $_.quality_score })
    $scores = @($checked | ForEach-Object { [int]$_.quality_score })
    if ($scores.Count -eq 0) {
        return @{ checked = 0; avg = 0; low = 0; min = 0; max = 0 }
    }
    return @{
        checked = $scores.Count
        avg     = [Math]::Round(($scores | Measure-Object -Average).Average, 1)
        low     = @($scores | Where-Object { $_ -lt $Threshold }).Count
        min     = ($scores | Measure-Object -Minimum).Minimum
        max     = ($scores | Measure-Object -Maximum).Maximum
    }
}

function Invoke-QualityCheckAll {
    param([int]$ProjectId, [int]$MaxChapter)
    for ($s = 1; $s -le $MaxChapter; $s += 5) {
        $e = [Math]::Min($s + 4, $MaxChapter)
        $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/quality-check-range" -Body @{
            start_chapter   = $s
            end_chapter     = $e
            score_threshold = $THRESHOLD
        } -TimeoutSec 1800
        if (-not $r.ok) { throw "QC $s-$e failed: $($r.detail)" }
        Log "  QC batch $s-$e checked=$($r.body.checked_chapters.Count)"
    }
}

function Invoke-RewriteLowScore {
    param([int]$ProjectId, [int]$MaxChapter)
    $total = 0
    for ($s = 1; $s -le $MaxChapter; $s += 5) {
        $e = [Math]::Min($s + 4, $MaxChapter)
        $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/rewrite-issues" -Body @{
            start_chapter   = $s
            end_chapter     = $e
            score_threshold = $THRESHOLD
            max_rounds      = 1
        } -TimeoutSec 3600
        if (-not $r.ok) { throw "Rewrite $s-$e failed: $($r.detail)" }
        $total += @($r.body.rewritten_chapters).Count
        Log "  Rewrite $s-$e rewritten=$($r.body.rewritten_chapters -join ',')"
    }
    return $total
}

function Invoke-TtsAll {
    param([int]$ProjectId, [int]$MaxChapter, [string]$VoiceKey)
    for ($s = 1; $s -le $MaxChapter; $s += 5) {
        $e = [Math]::Min($s + 4, $MaxChapter)
        $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/generate-tts-range" -Body @{
            start_chapter = $s
            end_chapter   = $e
            voice_key     = $VoiceKey
            rate          = "+0%"
        } -TimeoutSec 3600
        if (-not $r.ok) { throw "TTS $s-$e failed: $($r.detail)" }
        Log "  TTS batch $s-$e generated=$($r.body.generated_chapters -join ',')"
    }
}

function Invoke-FullWorkForLanguage {
    param($Spec)

    $lang = $Spec.lang
    $target = [int]$Spec.target
    $cw = [int]$Spec.chapter_words
    $maxCh = [int][Math]::Ceiling($target / $cw)
    $voice = Get-DefaultVoiceForLanguage -Language $lang
    $ts = Get-Date -Format "HHmmss"

    $result = [ordered]@{
        Language     = $lang
        TargetWords  = $target
        Chapters     = $maxCh
        ProjectId    = $null
        ContentOk    = 0
        QcAvgBefore  = $null
        QcAvgAfter   = $null
        Rewritten    = 0
        Mp3Ok        = 0
        ZipPath      = ""
        ZipBytes     = 0
        Result       = "FAIL"
        Error        = ""
        ElapsedMin   = 0
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Log "[$lang] === Full work test: ${target} words, $maxCh chapters ==="
        $proj = Create-Project `
            -ProjectName "v03-work-$lang-$ts" `
            -Title $Spec.title `
            -TargetWords $target `
            -ChapterWords $cw `
            -Language $lang `
            -GenerateTts $false
        $projectId = [int]$proj.id
        $result.ProjectId = $projectId

        Invoke-ApplyTemplate -ProjectId $projectId | Out-Null
        Invoke-GenerateBible -ProjectId $projectId -TimeoutSec 300 | Out-Null
        Invoke-GenerateOutline -ProjectId $projectId -TimeoutSec 300 | Out-Null

        $chs = Get-ChaptersUnique -ProjectId $projectId
        if ($chs.Count -lt $maxCh) {
            throw "Expected $maxCh chapters, got $($chs.Count)"
        }

        for ($s = 1; $s -le $maxCh; $s += 5) {
            $e = [Math]::Min($s + 4, $maxCh)
            Invoke-BatchRange -ProjectId $projectId -Start $s -End $e -TimeoutSec 7200 | Out-Null
        }

        $chs = Get-ChaptersUnique -ProjectId $projectId
        $contentOk = @($chs | Where-Object { (Get-ChapterContentText $_).Length -gt 0 }).Count
        $result.ContentOk = $contentOk
        if ($contentOk -ne $maxCh) {
            throw "Content incomplete: $contentOk/$maxCh chapters"
        }
        Log "[$lang] Content OK $contentOk/$maxCh"

        Invoke-QualityCheckAll -ProjectId $projectId -MaxChapter $maxCh
        $chs = Get-ChaptersUnique -ProjectId $projectId
        $before = Get-QualityStats -Chapters $chs -Threshold $THRESHOLD
        $result.QcAvgBefore = $before.avg
        Log "[$lang] QC before rewrite: avg=$($before.avg) low=$($before.low)"

        $result.Rewritten = Invoke-RewriteLowScore -ProjectId $projectId -MaxChapter $maxCh

        Invoke-QualityCheckAll -ProjectId $projectId -MaxChapter $maxCh
        $chs = Get-ChaptersUnique -ProjectId $projectId
        $after = Get-QualityStats -Chapters $chs -Threshold $THRESHOLD
        $result.QcAvgAfter = $after.avg
        Log "[$lang] QC after rewrite: avg=$($after.avg) low=$($after.low)"

        Invoke-TtsAll -ProjectId $projectId -MaxChapter $maxCh -VoiceKey $voice
        $chs = Get-ChaptersUnique -ProjectId $projectId
        $mp3Ok = @($chs | Where-Object { $_.tts_status -eq "completed" }).Count
        $result.Mp3Ok = $mp3Ok
        if ($mp3Ok -ne $maxCh) {
            throw "MP3 incomplete: $mp3Ok/$maxCh"
        }

        $zip = Export-FullZip -ProjectId $projectId -Language $lang -Prefix "v03_work"
        $result.ZipPath = $zip.path
        $result.ZipBytes = $zip.bytes
        if ($zip.bytes -lt 1000) {
            throw "ZIP too small: $($zip.path)"
        }

        $result.Result = "PASS"
        Log "[$lang] PASS project=$projectId zip=$($zip.path)"
    } catch {
        $result.Error = $_.Exception.Message
        $result.Result = "FAIL"
        Log "[$lang] FAIL: $($result.Error)"
    }

    $sw.Stop()
    $result.ElapsedMin = [Math]::Round($sw.Elapsed.TotalMinutes, 1)
    return [pscustomobject]$result
}

Write-Host ""
Write-Host "=== v0.3 Full Work Production Test ===" -ForegroundColor Cyan
Write-Host "Started: $startedAt"
Write-Host "Flow: content -> QC -> rewrite -> QC -> TTS -> ZIP"
Write-Host ""

$rows = @()
foreach ($w in $WORKS) {
    Write-Host "--- $($w.lang) $($w.target) words ---" -ForegroundColor Yellow
    $rows += Invoke-FullWorkForLanguage -Spec $w
}

$failCount = @($rows | Where-Object { $_.Result -ne "PASS" }).Count
$overall = if ($failCount -eq 0) { "PASS" } else { "FAIL" }
$endedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$reportLines = @(
    "v0.3 Full Work Production Test Report"
    "====================================="
    "Started:  $startedAt"
    "Finished: $endedAt"
    "Overall:  $overall"
    ""
    "Lang | ProjectId | Target | Chapters | Content | QC before | QC after | Rewritten | MP3 | ZIP bytes | Min | Result"
    "-----+-----------+--------+----------+---------+-----------+----------+-----------+-----+-----------+-----+------"
)

foreach ($r in $rows) {
    $reportLines += (
        "{0,-4} | {1,-9} | {2,-6} | {3,-8} | {4,-7} | {5,-9} | {6,-8} | {7,-9} | {8,-3} | {9,-9} | {10,-3} | {11}" -f `
            $r.Language, $r.ProjectId, $r.TargetWords, $r.Chapters, $r.ContentOk, `
            $r.QcAvgBefore, $r.QcAvgAfter, $r.Rewritten, $r.Mp3Ok, $r.ZipBytes, $r.ElapsedMin, $r.Result
    )
    if ($r.ZipPath) { $reportLines += "  ZIP: $($r.ZipPath)" }
    if ($r.Error) { $reportLines += "  ERROR: $($r.Error)" }
    $reportLines += ""
}

$reportLines += "Summary: $($rows.Count - $failCount)/$($rows.Count) passed"
Set-Content -Path $ReportFile -Value ($reportLines -join "`n") -Encoding UTF8

Write-Host ""
Write-Host "Overall: $overall ($($rows.Count - $failCount)/$($rows.Count))" -ForegroundColor $(if ($overall -eq "PASS") { "Green" } else { "Red" })
Write-Host "Report: $ReportFile"
Log "Report written: $ReportFile"

if ($failCount -gt 0) { exit 1 }
exit 0
