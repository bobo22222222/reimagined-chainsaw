# Observation run: 5k / 10k / 20k / 50k with quality + rewrite + MP3 + ZIP metrics
# Usage: powershell -ExecutionPolicy Bypass -File scripts\run_observation_test.ps1 [-Phase 0|1|2|3|4]
param([int]$Phase = 0)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"

$ReportFile = Join-Path $script:TestOutDir "OBSERVATION_REPORT.txt"
$observations = @()

function Log-Obs([string]$phase, [string]$metric, [string]$value, [string]$note = "") {
    $script:observations += [PSCustomObject]@{
        Phase  = $phase
        Metric = $metric
        Value  = $value
        Note   = $note
    }
    Log "[$phase] $metric = $value $(if ($note) { "($note)" })"
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

function New-ObsProject {
    param([string]$Name, [int]$TargetWords)
    $r = Invoke-Api -Method POST -Path "/api/projects" -Body @{
        project_name  = $Name
        title         = "Obs-$TargetWords"
        target_words  = $TargetWords
        chapter_words = 2000
        language      = "中文"
        generate_tts  = $false
    }
    if (-not $r.ok) { throw $r.detail }
    $id = [int]$r.body.id
    Invoke-Api -Method POST -Path "/api/projects/$id/apply-template" -Body @{ template_key = "tycoon_revenge" } | Out-Null
    Invoke-Api -Method POST -Path "/api/projects/$id/generate-bible" -TimeoutSec 300 | Out-Null
    Invoke-Api -Method POST -Path "/api/projects/$id/generate-outline" -TimeoutSec 300 | Out-Null
    return $id
}

function Invoke-GenerateAllContent {
    param([int]$ProjectId, [int]$TimeoutSec = 3600)
    $chs = Get-ChaptersUnique -ProjectId $ProjectId
    $max = ($chs | ForEach-Object { [int]$_.chapter_number } | Measure-Object -Maximum).Maximum
    for ($start = 1; $start -le $max; $start += 5) {
        $end = [Math]::Min($start + 4, $max)
        Invoke-BatchRange -ProjectId $ProjectId -Start $start -End $end -TimeoutSec $TimeoutSec | Out-Null
    }
}

function Test-ChapterContinuity {
    param($Chapters)
    $nums = @($Chapters | ForEach-Object { [int]$_.chapter_number } | Sort-Object)
    $expected = 1..($nums[-1])
    $missing = @($expected | Where-Object { $_ -notin $nums })
    $withContent = @($Chapters | Where-Object { (Get-ChapterContentText $_).Length -gt 0 })
    $gaps = @()
    foreach ($n in $expected) {
        $ch = $Chapters | Where-Object { [int]$_.chapter_number -eq $n } | Select-Object -First 1
        if (-not $ch -or -not (Get-ChapterContentText $ch)) { $gaps += $n }
    }
    return @{
        total       = $nums.Count
        max_num     = $nums[-1]
        missing_nums = ($missing -join ",")
        content_gaps = ($gaps -join ",")
        continuous  = ($missing.Count -eq 0 -and $gaps.Count -eq 0)
        content_ok  = $withContent.Count
    }
}

function Get-TextOverlapRatio([string]$a, [string]$b) {
    if (-not $a -or -not $b) { return 0 }
    $wa = @([regex]::Matches($a, "[\u4e00-\u9fff]{2,}") | ForEach-Object { $_.Value })
    $wb = @([regex]::Matches($b, "[\u4e00-\u9fff]{2,}") | ForEach-Object { $_.Value })
    if ($wa.Count -eq 0 -or $wb.Count -eq 0) { return 0 }
    $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$wa)
    $inter = ($wb | Where-Object { $setA.Contains($_) }).Count
    $union = $setA.Count + ($wb | Where-Object { -not $setA.Contains($_) }).Count
    if ($union -eq 0) { return 0 }
    return [Math]::Round($inter / $union, 3)
}

function Test-PlotRepetition {
    param($Chapters)
    $sorted = @($Chapters | Sort-Object { [int]$_.chapter_number })
    $highPairs = @()
    for ($i = 0; $i -lt $sorted.Count - 1; $i++) {
        $aText = Get-ChapterContentText $sorted[$i]
        $bText = Get-ChapterContentText $sorted[$i + 1]
        $a = $aText.Substring(0, [Math]::Min(400, $aText.Length))
        $b = $bText.Substring(0, [Math]::Min(400, $bText.Length))
        $ratio = Get-TextOverlapRatio $a $b
        if ($ratio -ge 0.35) {
            $highPairs += "$($sorted[$i].chapter_number)-$($sorted[$i+1].chapter_number):$ratio"
        }
    }
    return @{
        high_overlap_pairs = ($highPairs -join "; ")
        suspicious         = ($highPairs.Count -gt 0)
    }
}

function Invoke-QualityCheckAll {
    param([int]$ProjectId, [int]$MaxChapter)
    $allResults = @()
    for ($start = 1; $start -le $MaxChapter; $start += 5) {
        $end = [Math]::Min($start + 4, $MaxChapter)
        $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/quality-check-range" -Body @{
            start_chapter = $start
            end_chapter   = $end
        } -TimeoutSec 900
        if (-not $r.ok) { throw "QC batch $start-$end failed: $($r.detail)" }
        $allResults += @($r.body.checked_chapters)
        Start-Sleep -Seconds 1
    }
    return $allResults
}

function Get-QualityStats($Results) {
    if (-not $Results -or $Results.Count -eq 0) {
        return @{ count = 0; min = 0; max = 0; avg = 0; low_count = 0; scores = "" }
    }
    $scores = @($Results | ForEach-Object { [int]$_.score })
    $avg = [Math]::Round(($scores | Measure-Object -Average).Average, 1)
    return @{
        count     = $scores.Count
        min       = ($scores | Measure-Object -Minimum).Minimum
        max       = ($scores | Measure-Object -Maximum).Maximum
        avg       = $avg
        low_count = @($scores | Where-Object { $_ -lt 70 }).Count
        scores    = ($scores -join ",")
    }
}

function Run-ObsPhase {
    param([int]$Round, [int]$TargetWords, [string]$Label)
    Init-TestLog "obs-phase$Round"
    Log "========== Observation Phase $Round : $Label =========="
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $phaseTag = "R$Round"

    try {
        Assert-Backend
        $id = New-ObsProject -Name "obs-$Label" -TargetWords $TargetWords
        Log-Obs $phaseTag "project_id" $id

        Invoke-GenerateAllContent -ProjectId $id -TimeoutSec 7200
        $chs = Get-ChaptersUnique -ProjectId $id
        $cont = Test-ChapterContinuity -Chapters $chs
        Log-Obs $phaseTag "chapter_continuity" $(if ($cont.continuous) { "OK" } else { "GAP" }) `
            "content $($cont.content_ok)/$($cont.total) gaps=$($cont.content_gaps)"

        $rep = Test-PlotRepetition -Chapters $chs
        Log-Obs $phaseTag "plot_repetition" $(if ($rep.suspicious) { "SUSPICIOUS" } else { "OK" }) $rep.high_overlap_pairs

        $qcResults = Invoke-QualityCheckAll -ProjectId $id -MaxChapter $cont.max_num
        $qStats = Get-QualityStats $qcResults
        Log-Obs $phaseTag "quality_scores" $qStats.scores "min=$($qStats.min) max=$($qStats.max) avg=$($qStats.avg)"
        Log-Obs $phaseTag "quality_low_count" $qStats.low_count "below 70"

        $characterFlags = @()
        foreach ($item in $qcResults) {
            foreach ($issue in @($item.issues)) {
                $msg = [string]$issue.message
                if ($msg -match "人物|设定|一致|偏离|大纲") {
                    $characterFlags += "ch$($item.chapter_number):$msg"
                }
            }
        }
        Log-Obs $phaseTag "character_consistency" $(if ($characterFlags.Count -eq 0) { "OK" } else { "WARN" }) `
            (($characterFlags | Select-Object -First 3) -join " | ")

        $rewriteNote = "skipped"
        if ($qStats.low_count -gt 0) {
            $lowest = $qcResults | Sort-Object { [int]$_.score } | Select-Object -First 1
            $chId = ($chs | Where-Object { [int]$_.chapter_number -eq [int]$lowest.chapter_number }).id
            $scoreBefore = [int]$lowest.score
            $rw = Invoke-Api -Method POST -Path "/api/chapters/$chId/rewrite" -TimeoutSec 600
            if ($rw.ok) {
                $recheck = Invoke-Api -Method POST -Path "/api/chapters/$chId/quality-check" -TimeoutSec 300
                $scoreAfter = if ($recheck.ok) { [int]$recheck.body.score } else { -1 }
                $delta = $scoreAfter - $scoreBefore
                $rewriteNote = "ch$($lowest.chapter_number) $scoreBefore->$scoreAfter (delta $delta) tts=$($rw.body.tts_status)"
                Log-Obs $phaseTag "rewrite_improvement" $(if ($delta -gt 0) { "IMPROVED" } else { "FLAT/DOWN" }) $rewriteNote
                Log-Obs $phaseTag "tts_after_rewrite" $rw.body.tts_status "expect pending"
            } else {
                Log-Obs $phaseTag "rewrite_improvement" "FAIL" $rw.detail
            }
        } else {
            Log-Obs $phaseTag "rewrite_improvement" "N/A" "all scores >= 70"
        }

        $maxCh = $cont.max_num
        $mp3Generated = @()
        for ($start = 1; $start -le $maxCh; $start += 5) {
            $end = [Math]::Min($start + 4, $maxCh)
            $tts = Invoke-Api -Method POST -Path "/api/projects/$id/generate-tts-range" -Body @{
                start_chapter = $start
                end_chapter   = $end
                voice_key     = "zh_female"
                rate          = "+0%"
            } -TimeoutSec 7200
            if ($tts.ok) {
                $mp3Generated += @($tts.body.generated_chapters)
            } else {
                Log "MP3 batch $start-$end failed: $($tts.detail)"
            }
        }
        $chs2 = Get-ChaptersUnique -ProjectId $id
        $mp3Ok = @($chs2 | Where-Object { $_.tts_status -eq "completed" }).Count
        Log-Obs $phaseTag "mp3_generated" "$mp3Ok/$($chs2.Count)" "batches ok=$($mp3Generated.Count) ch"

        $zipPath = Join-Path $script:TestOutDir "obs_${Label}_project_${id}_full.zip"
        Invoke-WebRequest -Uri "$script:ApiBase/api/projects/$id/export/full-zip" -OutFile $zipPath -TimeoutSec 600 -UseBasicParsing
        $zipBytes = (Get-Item $zipPath).Length
        Log-Obs $phaseTag "zip_export" $(if ($zipBytes -gt 0) { "OK" } else { "FAIL" }) "$zipBytes bytes"

        $sw.Stop()
        Log-Obs $phaseTag "elapsed_min" ([Math]::Round($sw.Elapsed.TotalMinutes, 1))
        Log-Obs $phaseTag "status" "DONE" "http://localhost:3000/chapters?projectId=$id"
    } catch {
        $sw.Stop()
        Log-Obs $phaseTag "status" "ERROR" $_.Exception.Message
        Log-Obs $phaseTag "elapsed_min" ([Math]::Round($sw.Elapsed.TotalMinutes, 1))
    }
}

New-Item -ItemType Directory -Force -Path $script:TestOutDir | Out-Null
Init-TestLog "observation"

if ($Phase -eq 0 -or $Phase -eq 1) { Run-ObsPhase -Round 1 -TargetWords 5000 -Label "5k" }
if ($Phase -eq 0 -or $Phase -eq 2) { Run-ObsPhase -Round 2 -TargetWords 10000 -Label "10k" }
if ($Phase -eq 0 -or $Phase -eq 3) { Run-ObsPhase -Round 3 -TargetWords 20000 -Label "20k" }
if ($Phase -eq 0 -or $Phase -eq 4) { Run-ObsPhase -Round 4 -TargetWords 50000 -Label "50k" }

$lines = @(
    "=== OBSERVATION REPORT $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===",
    "",
    "Metrics: continuity | character | repetition | quality | rewrite | mp3 | zip",
    ""
)
foreach ($o in $observations) {
    $lines += "Phase $($o.Phase) | $($o.Metric) | $($o.Value) | $($o.Note)"
}
$lines += ""
$lines += "=== SUMMARY BY ROUND ==="
foreach ($r in 1..4) {
    if ($Phase -ne 0 -and $Phase -ne $r) { continue }
    $tag = "R$r"
    $rows = $observations | Where-Object { $_.Phase -eq $tag }
    if (-not $rows) { continue }
    $lines += ""
    $lines += "--- Round $r ---"
    foreach ($m in @("chapter_continuity", "character_consistency", "plot_repetition", "quality_scores", "quality_low_count", "rewrite_improvement", "mp3_generated", "zip_export", "elapsed_min", "status")) {
        $row = $rows | Where-Object { $_.Metric -eq $m } | Select-Object -First 1
        if ($row) { $lines += "$m : $($row.Value)  $($row.Note)" }
    }
}
$lines | Set-Content -Path $ReportFile -Encoding UTF8
Write-Host "`nReport saved: $ReportFile" -ForegroundColor Cyan
Get-Content $ReportFile
