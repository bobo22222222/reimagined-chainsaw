# Phased acceptance tests (4 rounds)
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\run_phased_test.ps1 -Phase 1
#   powershell -ExecutionPolicy Bypass -File scripts\run_phased_test.ps1 -Phase 0   # all phases
#
# Phase 1:  5k  words - full MVP path (first 3 chapters + export)
# Phase 2: 10k words - batch generate ALL chapters to completion
# Phase 3: 20k words - export all formats + audio volume stats
# Phase 4: 50k words - stability (25 chapters, batch loop + timing)

param(
    [int]$Phase = 0
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"

$ReportFile = Join-Path $script:TestOutDir "PHASED_REPORT.txt"
$results = @()

function Add-Result($phase, $name, $pass, $detail) {
    $script:results += [PSCustomObject]@{ Phase = $phase; Item = $name; Pass = $pass; Detail = $detail }
    $mark = if ($pass) { "PASS" } else { "FAIL" }
    Log "[$mark] Phase $phase - $name : $detail"
}

function Write-Report {
    $lines = @("=== PHASED TEST REPORT $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===", "")
    foreach ($r in $script:results) {
        $lines += "Phase $($r.Phase) | $($r.Item) | $($r.Pass) | $($r.Detail)"
    }
    $lines | Set-Content -Path $ReportFile -Encoding UTF8
    Log "Report: $ReportFile"
}

function Run-Phase1 {
    Init-TestLog "phase1"
    Log "=== Phase 1: 5k full MVP ==="
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-Backend
        $id = New-TestProject -Name "phase1-5k" -TargetWords 5000 -ChapterWords 2000
        $f3 = Invoke-Api -Method POST -Path "/api/projects/$id/generate-first-3" -Body @{
            voice_key = "zh_male"; rate = "+0%"
        } -TimeoutSec 900
        if (-not $f3.ok) { throw $f3.detail }
        $stats = Get-MediaStats -ProjectId $id
        $exports = Export-ProjectZips -ProjectId $id -Prefix "phase1"
        $zip = $exports["full-zip"]
        $zipOk = $zip -and $zip.bytes -gt 0
        Add-Result 1 "create+bible+outline" $true "project=$id"
        Add-Result 1 "first-3-chapters" ($f3.body.generated_chapters.Count -eq 3) "generated=$($f3.body.generated_chapters -join ',')"
        Add-Result 1 "mp3-3" ($stats.mp3_ok -ge 3) "mp3=$($stats.mp3_ok)/$($stats.total)"
        Add-Result 1 "full-zip" $zipOk "bytes=$($zip.bytes)"
        Add-Result 1 "elapsed" $true "$([Math]::Round($sw.Elapsed.TotalMinutes,1)) min"
    } catch {
        Add-Result 1 "error" $false $_.Exception.Message
    }
}

function Run-Phase2 {
    Init-TestLog "phase2"
    Log "=== Phase 2: 10k batch to completion ==="
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-Backend
        $id = New-TestProject -Name "phase2-10k" -TargetWords 10000 -ChapterWords 2000
        Invoke-GenerateAllChapters -ProjectId $id
        $stats = Get-MediaStats -ProjectId $id
        $allDone = ($stats.content_ok -eq $stats.total) -and ($stats.mp3_ok -eq $stats.total)
        Add-Result 2 "all-chapters-content" ($stats.content_ok -eq $stats.total) "$($stats.content_ok)/$($stats.total)"
        Add-Result 2 "all-chapters-mp3" ($stats.mp3_ok -eq $stats.total) "$($stats.mp3_ok)/$($stats.total)"
        Add-Result 2 "complete" $allDone "project=$id chapters=$($stats.total)"
        Add-Result 2 "elapsed" $true "$([Math]::Round($sw.Elapsed.TotalMinutes,1)) min"
    } catch {
        Add-Result 2 "error" $false $_.Exception.Message
    }
}

function Run-Phase3 {
    Init-TestLog "phase3"
    Log "=== Phase 3: 20k export + audio volume ==="
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-Backend
        $id = New-TestProject -Name "phase3-20k" -TargetWords 20000 -ChapterWords 2000
        Invoke-GenerateAllChapters -ProjectId $id
        $stats = Get-MediaStats -ProjectId $id
        $avgMp3 = if ($stats.mp3_ok -gt 0) { [Math]::Round($stats.mp3_bytes / $stats.mp3_ok / 1KB, 1) } else { 0 }
        $exports = Export-ProjectZips -ProjectId $id -Prefix "phase3"
        $fullOk = $exports["full-zip"].bytes -gt 0
        $audioOk = $exports["audio-zip"].bytes -gt 0
        Add-Result 3 "chapters-done" ($stats.content_ok -eq $stats.total) "$($stats.content_ok)/$($stats.total)"
        Add-Result 3 "total-audio-mb" ($stats.mp3_mb -gt 0) "$($stats.mp3_mb) MB ($($stats.mp3_ok) files)"
        Add-Result 3 "avg-mp3-kb" ($avgMp3 -gt 0) "${avgMp3} KB/ch"
        Add-Result 3 "full-zip" $fullOk "$($exports['full-zip'].mb) MB"
        Add-Result 3 "audio-zip" $audioOk "$($exports['audio-zip'].mb) MB"
        Add-Result 3 "elapsed" $true "$([Math]::Round($sw.Elapsed.TotalMinutes,1)) min"
    } catch {
        Add-Result 3 "error" $false $_.Exception.Message
    }
}

function Run-Phase4 {
    Init-TestLog "phase4"
    Log "=== Phase 4: 50k stability ==="
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $batchTimes = @()
    try {
        Assert-Backend
        $id = New-TestProject -Name "phase4-50k" -TargetWords 50000 -ChapterWords 2000
        $chs = Get-ChapterList -ProjectId $id
        $max = ($chs | ForEach-Object { $_.chapter_number } | Measure-Object -Maximum).Maximum
        Log "Stability run: $max chapters in batches of 5"
        for ($start = 1; $start -le $max; $start += 5) {
            $end = [Math]::Min($start + 4, $max)
            $bsw = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-BatchRange -ProjectId $id -Start $start -End $end -TimeoutSec 3600 | Out-Null
            $bsw.Stop()
            $batchTimes += $bsw.Elapsed.TotalMinutes
            Log "  batch $start-$end took $([Math]::Round($bsw.Elapsed.TotalMinutes,1)) min"
        }
        $stats = Get-MediaStats -ProjectId $id
        $failed = $stats.total - $stats.content_ok
        Add-Result 4 "chapters-total" $true "$($stats.total)"
        Add-Result 4 "content-complete" ($stats.content_ok -eq $stats.total) "$($stats.content_ok)/$($stats.total) failed=$failed"
        Add-Result 4 "mp3-complete" ($stats.mp3_ok -eq $stats.total) "$($stats.mp3_ok)/$($stats.total)"
        Add-Result 4 "batch-count" $true "$($batchTimes.Count) batches"
        Add-Result 4 "total-audio-mb" $true "$($stats.mp3_mb) MB"
        Add-Result 4 "elapsed" $true "$([Math]::Round($sw.Elapsed.TotalMinutes,1)) min (avg batch $([Math]::Round(($batchTimes | Measure-Object -Average).Average,1)) min)"
        $exports4 = Export-ProjectZips -ProjectId $id -Prefix "phase4"
        $zip4 = $exports4["full-zip"]
        Add-Result 4 "full-zip" ($zip4.bytes -gt 0) "$($zip4.mb) MB"
    } catch {
        Add-Result 4 "error" $false $_.Exception.Message
        Add-Result 4 "elapsed-partial" $true "$([Math]::Round($sw.Elapsed.TotalMinutes,1)) min"
    }
}

Init-TestLog "phased"
New-Item -ItemType Directory -Force -Path $script:TestOutDir | Out-Null

if ($Phase -eq 0 -or $Phase -eq 1) { Run-Phase1 }
if ($Phase -eq 0 -or $Phase -eq 2) { Run-Phase2 }
if ($Phase -eq 0 -or $Phase -eq 3) { Run-Phase3 }
if ($Phase -eq 0 -or $Phase -eq 4) { Run-Phase4 }

Write-Report
Log "=== ALL REQUESTED PHASES DONE ==="
Write-Host ""
Write-Host "Report: $ReportFile" -ForegroundColor Cyan
Get-Content $ReportFile
