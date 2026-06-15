# Resume a project from existing chapter state.
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\resume_project.ps1 -ProjectId 49 -FromChapter 1 -ToChapter 10 -DoTts -DoExport
param(
    [Parameter(Mandatory = $true)]
    [int]$ProjectId,
    [int]$FromChapter = 1,
    [int]$ToChapter = 999,
    [switch]$DoText,
    [switch]$DoQuality,
    [switch]$DoRewrite,
    [switch]$DoTts,
    [switch]$DoExport,
    [int]$QualityThreshold = 70,
    [string]$VoiceKey = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"

Init-TestLog "v04_resume_project"
Assert-Backend

$ReportFile = Join-Path $script:TestOutDir "V04_RESUME_PROJECT_REPORT.txt"
$startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = New-Object System.Collections.Generic.List[string]

function Add-Line { param([string]$s) $script:lines.Add($s) }

function Add-ListLine {
    param([string]$Label, [System.Collections.IEnumerable]$Items)
    $arr = @($Items)
    $value = if ($arr.Count -gt 0) { $arr -join "," } else { "-" }
    Add-Line "$Label$value"
}

function Get-TargetChapters {
    param([int]$ProjectId, [int]$From, [int]$To)
    $chs = Get-ChapterList -ProjectId $ProjectId
    return @($chs | Where-Object {
        [int]$_.chapter_number -ge $From -and [int]$_.chapter_number -le $To
    } | Sort-Object { [int]$_.chapter_number })
}

function Test-ChapterMp3Exists {
    param($Chapter)
    $path = [string]$Chapter.audio_path
    return ($path -and (Test-Path $path) -and ((Get-Item $path).Length -gt 0))
}

function Get-ProjectVoiceKey {
    param([int]$ProjectId, [string]$FallbackVoice)
    if ($FallbackVoice) { return $FallbackVoice }
    $project = Get-Project -ProjectId $ProjectId
    return Get-DefaultVoiceForLanguage -Language ([string]$project.language)
}

function New-ResultBucket {
    return [ordered]@{
        generated = New-Object System.Collections.Generic.List[int]
        checked = New-Object System.Collections.Generic.List[int]
        rewritten = New-Object System.Collections.Generic.List[int]
        tts = New-Object System.Collections.Generic.List[int]
        skipped = New-Object System.Collections.Generic.List[int]
        failed = New-Object System.Collections.Generic.List[string]
    }
}

$text = New-ResultBucket
$qc = New-ResultBucket
$rewrite = New-ResultBucket
$tts = New-ResultBucket
$zipPath = ""
$zipBytes = 0

$overallOk = $true

try {
    $project = Get-Project -ProjectId $ProjectId
    $voice = Get-ProjectVoiceKey -ProjectId $ProjectId -FallbackVoice $VoiceKey
    $target = Get-TargetChapters -ProjectId $ProjectId -From $FromChapter -To $ToChapter
    if ($target.Count -eq 0) { throw "No chapters in range $FromChapter-$ToChapter" }

    Add-Line "v0.4 Resume Project Report"
    Add-Line "=========================="
    Add-Line "Started: $startedAt"
    Add-Line "Project ID: $ProjectId"
    Add-Line "Project title: $($project.title)"
    Add-Line "Chapter range: $FromChapter-$ToChapter"
    Add-Line "Voice: $voice"
    Add-Line "Quality threshold: $QualityThreshold"
    Add-Line ""

    if ($DoText) {
        foreach ($ch in $target) {
            $num = [int]$ch.chapter_number
            $content = Get-ChapterContentText $ch
            if ($content.Trim().Length -gt 0) {
                $text.skipped.Add($num)
                continue
            }
            try {
                Invoke-GenerateChapter -ChapterId ([int]$ch.id) -TimeoutSec 1800 | Out-Null
                $text.generated.Add($num)
            } catch {
                $overallOk = $false
                $text.failed.Add("ch${num}: $($_.Exception.Message)")
            }
        }
    }

    $target = Get-TargetChapters -ProjectId $ProjectId -From $FromChapter -To $ToChapter
    if ($DoQuality) {
        foreach ($ch in $target) {
            $num = [int]$ch.chapter_number
            $hasScore = $null -ne $ch.quality_score
            if ($ch.quality_status -eq "completed" -and $hasScore) {
                $qc.skipped.Add($num)
                continue
            }
            if ((Get-ChapterContentText $ch).Trim().Length -eq 0) {
                $qc.skipped.Add($num)
                continue
            }
            try {
                Invoke-QualityCheckChapter -ChapterId ([int]$ch.id) -TimeoutSec 900 | Out-Null
                $qc.checked.Add($num)
            } catch {
                $overallOk = $false
                $qc.failed.Add("ch${num}: $($_.Exception.Message)")
            }
        }
    }

    $target = Get-TargetChapters -ProjectId $ProjectId -From $FromChapter -To $ToChapter
    if ($DoRewrite) {
        foreach ($ch in $target) {
            $num = [int]$ch.chapter_number
            if ((Get-ChapterContentText $ch).Trim().Length -eq 0) {
                $rewrite.skipped.Add($num)
                continue
            }
            $score = $ch.quality_score
            if ($null -eq $score -or [int]$score -ge $QualityThreshold) {
                $rewrite.skipped.Add($num)
                continue
            }
            try {
                Invoke-RewriteChapter -ChapterId ([int]$ch.id) -TimeoutSec 1800 | Out-Null
                $rewrite.rewritten.Add($num)
            } catch {
                $overallOk = $false
                $rewrite.failed.Add("ch${num}: $($_.Exception.Message)")
            }
        }
    }

    $target = Get-TargetChapters -ProjectId $ProjectId -From $FromChapter -To $ToChapter
    if ($DoTts) {
        foreach ($ch in $target) {
            $num = [int]$ch.chapter_number
            if ((Get-ChapterContentText $ch).Trim().Length -eq 0) {
                $tts.skipped.Add($num)
                continue
            }
            if ($ch.tts_status -eq "completed" -and (Test-ChapterMp3Exists -Chapter $ch)) {
                $tts.skipped.Add($num)
                continue
            }
            try {
                Invoke-GenerateChapterTts -ChapterId ([int]$ch.id) -VoiceKey $voice -Rate "+0%" -TimeoutSec 1200 | Out-Null
                $tts.tts.Add($num)
            } catch {
                $overallOk = $false
                $tts.failed.Add("ch${num}: $($_.Exception.Message)")
            }
        }
    }

    if ($DoExport) {
        try {
            $project = Get-Project -ProjectId $ProjectId
            $lang = if ($project.language) { [string]$project.language } else { "zh" }
            $zip = Export-FullZip -ProjectId $ProjectId -Language $lang -Prefix "v04_resume"
            $zipPath = $zip.path
            $zipBytes = $zip.bytes
            if ($zipBytes -le 0) { throw "ZIP is empty: $zipPath" }
        } catch {
            $overallOk = $false
            $zipPath = "FAILED: $($_.Exception.Message)"
        }
    }
} catch {
    $overallOk = $false
    Add-Line "Setup error: $($_.Exception.Message)"
}

Add-Line "Text:"
Add-ListLine "  generated: " $text.generated
Add-ListLine "  skipped: " $text.skipped
Add-ListLine "  failed: " $text.failed
Add-Line "Quality:"
Add-ListLine "  checked: " $qc.checked
Add-ListLine "  skipped: " $qc.skipped
Add-ListLine "  failed: " $qc.failed
Add-Line "Rewrite:"
Add-ListLine "  rewritten: " $rewrite.rewritten
Add-ListLine "  skipped: " $rewrite.skipped
Add-ListLine "  failed: " $rewrite.failed
Add-Line "TTS:"
Add-ListLine "  generated: " $tts.tts
Add-ListLine "  skipped: " $tts.skipped
Add-ListLine "  failed: " $tts.failed
Add-Line "ZIP:"
Add-Line "  path: $zipPath"
Add-Line "  bytes: $zipBytes"
Add-Line ""
Add-Line "Finished: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")"
Add-Line "Overall: $(if ($overallOk) { "PASS" } else { "FAIL" })"

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($ReportFile, ($lines -join "`n"), $utf8NoBom)

Write-Host ""
Write-Host "Overall: $(if ($overallOk) { "PASS" } else { "FAIL" })" -ForegroundColor $(if ($overallOk) { "Green" } else { "Red" })
Write-Host "Report: $ReportFile" -ForegroundColor Cyan
if (-not $overallOk) { exit 1 }
