# v0.4 TTS text cleaner validation
# Usage: powershell -ExecutionPolicy Bypass -File scripts\run_v04_tts_cleaner_test.ps1
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"

Init-TestLog "v04_tts_cleaner"
Assert-Backend

$ReportFile = Join-Path $script:TestOutDir "V04_TTS_CLEANER_REPORT.txt"
$BackendDir = Join-Path (Split-Path $PSScriptRoot -Parent) "backend"
$startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = New-Object System.Collections.Generic.List[string]

function Add-Line { param([string]$s) $script:lines.Add($s) }

Add-Line "v0.4 TTS Text Cleaner Report"
Add-Line "============================"
Add-Line "Started: $startedAt"
Add-Line ""

# --- 1. Python unit tests (4 languages + zh abbreviations) ---
Push-Location $BackendDir
try {
    $unitOut = python tts_cleaner_selftest.py unit 2>&1
    if ($LASTEXITCODE -ne 0 -or ($unitOut | Out-String) -notmatch "PASS") { throw "Unit test failed: $unitOut" }
}
finally {
    Pop-Location
}
Add-Line "Unit tests: PASS (zh/en/es/ja + zh PPT abbreviation)"
Add-Line ""

# --- 2. Self-contained fixture chapter with markdown residue ---
Push-Location $BackendDir
try {
    $fixtureJson = python tts_cleaner_selftest.py fixture 2>&1
    if ($LASTEXITCODE -ne 0) { throw "fixture creation failed: $fixtureJson" }
}
finally {
    Pop-Location
}

$fixture = ($fixtureJson | Out-String).Trim() | ConvertFrom-Json
Add-Line "Fixture sample: zh project_$($fixture.project_id) chapter_1 (id=$($fixture.chapter_id))"
Add-Line "  raw_len=$($fixture.raw_len) clean_len=$($fixture.clean_len)"
Add-Line "  markdown_removed=$($fixture.markdown_removed) forbid_hits=$($fixture.forbid_hits -join ',')"
Add-Line ""
Add-Line "Before clean sample:"
Add-Line $fixture.raw_sample
Add-Line ""
Add-Line "After clean sample:"
Add-Line $fixture.clean_sample
Add-Line ""

if ($fixture.forbid_hits.Count -gt 0) { throw "Markdown residue in cleaned text: $($fixture.forbid_hits)" }

# --- 3. Preserve DB content + regenerate MP3 ---
$projectId = [int]$fixture.project_id
$chapterId = [int]$fixture.chapter_id
$chs = Get-ChapterList -ProjectId $projectId
$chapterRow = $chs | Where-Object { [int]$_.id -eq $chapterId } | Select-Object -First 1
if (-not $chapterRow) { throw "fixture chapter not found" }
$contentBefore = Get-ChapterContentText $chapterRow

$tts = Invoke-Api -Method POST -Path "/api/chapters/$chapterId/tts" -Body @{
    voice_key = "zh_male"
    rate      = "+0%"
} -TimeoutSec 900

if (-not $tts.ok) { throw "TTS regen failed: $($tts.detail)" }

$chsAfter = Get-ChapterList -ProjectId $projectId
$chapterAfter = $chsAfter | Where-Object { [int]$_.id -eq $chapterId } | Select-Object -First 1
$contentAfter = Get-ChapterContentText $chapterAfter
$contentPreserved = ($contentBefore -eq $contentAfter)

$mp3Path = $chapterAfter.audio_path
$mp3Ok = (Test-Path $mp3Path) -and ((Get-Item $mp3Path).Length -gt 0)

Add-Line "Content preserved in DB: $contentPreserved"
Add-Line "MP3 regenerated: $mp3Ok path=$mp3Path"
Add-Line "TTS status: $($chapterAfter.tts_status)"
Add-Line ""

if (-not $contentPreserved) { throw "chapter.content was modified — must stay raw" }
if (-not $mp3Ok) { throw "MP3 not generated" }

$finishedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Line "Finished: $finishedAt"
Add-Line "Overall: PASS"

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($ReportFile, ($lines -join "`n"), $utf8NoBom)
Write-Host ""
Write-Host "Overall: PASS"
Write-Host "Report: $ReportFile"
