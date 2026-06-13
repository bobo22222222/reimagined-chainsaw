# v0.3 single-language smoke: zh / en / es / ja -- 1 chapter each
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\lib_api.ps1"

Init-TestLog "v03_language_smoke"
Assert-Backend

$ReportFile = Join-Path $script:TestOutDir "V03_LANGUAGE_SMOKE_REPORT.txt"
$startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$LANGUAGES = @(
    @{ code = "zh"; label = "Chinese" }
    @{ code = "en"; label = "English" }
    @{ code = "es"; label = "Spanish" }
    @{ code = "ja"; label = "Japanese" }
)

function Count-CharsInRange {
    param([string]$Text, [int]$Lo, [int]$Hi)
    if (-not $Text) { return 0 }
    $n = 0
    foreach ($c in $Text.ToCharArray()) {
        $code = [int][char]$c
        if ($code -ge $Lo -and $code -le $Hi) { $n++ }
    }
    return $n
}

function Test-LanguageContent {
    param([string]$Lang, [string]$Text)
    if (-not $Text -or $Text.Trim().Length -lt 50) { return $false }

    $cjk = Count-CharsInRange -Text $Text -Lo 0x4E00 -Hi 0x9FFF
    $kana = Count-CharsInRange -Text $Text -Lo 0x3040 -Hi 0x30FF
    $latin = ([regex]::Matches($Text, '[A-Za-z]')).Count

    switch ($Lang) {
        'zh' {
            return ($cjk -ge 20)
        }
        'en' {
            return ($latin -ge 80 -and $cjk -lt 20)
        }
        'es' {
            $accent = Count-CharsInRange -Text $Text -Lo 0x00C0 -Hi 0x024F
            if ($accent -ge 2) { return $true }
            $lower = $Text.ToLower()
            $pat = '\b(el|la|de|que|y|en|una|un|los|las|por|con|su|es|al|del)\b'
            return ([regex]::Matches($lower, $pat).Count -ge 3)
        }
        'ja' {
            if ($kana -ge 5) { return $true }
            if ($cjk -ge 30 -and $kana -ge 1) { return $true }
            return ($kana -ge 2 -and $cjk -ge 10)
        }
        default { return $false }
    }
}

function Test-ContentFieldPrimary {
    param($Chapter)
    $content = if ($null -ne $Chapter.content) { ([string]$Chapter.content).Trim() } else { "" }
    return ($content.Length -gt 0)
}

function Invoke-SingleLanguageSmoke {
    param([string]$LangCode, [string]$LangLabel)

    $result = [ordered]@{
        Language      = $LangCode
        Label         = $LangLabel
        ProjectId     = $null
        ChapterLen    = 0
        QualityScore  = $null
        Tts           = 'FAIL'
        Zip           = 'FAIL'
        LangCheck     = 'FAIL'
        ContentField  = 'FAIL'
        ProjectLangOk = 'FAIL'
        Result        = 'FAIL'
        Error         = ''
        Retried       = 'NO'
        LastError     = ''
    }

    try {
        $chapterId = $null
        $ts = Get-Date -Format "HHmmss"
        $proj = Create-Project `
            -ProjectName "v03-smoke-$LangCode-$ts" `
            -Title "V03-Smoke-$LangCode" `
            -TargetWords 5000 `
            -ChapterWords 2000 `
            -Language $LangCode `
            -GenerateTts $false
        $projectId = [int]$proj.id
        $result.ProjectId = $projectId
        Log "[$LangCode] Created project id=$projectId"

        Invoke-ApplyTemplate -ProjectId $projectId -TemplateKey "tycoon_revenge" | Out-Null
        Log "[$LangCode] Template applied"

        $bible = Invoke-GenerateBible -ProjectId $projectId
        Log "[$LangCode] Bible len=$($bible.story_bible.Length)"

        Invoke-GenerateOutline -ProjectId $projectId | Out-Null
        Log "[$LangCode] Outline OK"

        $ch1 = Get-FirstChapter -ProjectId $projectId
        $chapterId = [int]$ch1.id
        Log "[$LangCode] Generating chapter 1 id=$chapterId ..."
        $genResp = Invoke-GenerateChapter -ChapterId $chapterId -TimeoutSec 900
        if ($genResp.generation_retried -eq $true) {
            $result.Retried = 'YES'
        }

        $fresh = Get-Chapter -ChapterId $chapterId
        $text = Get-ChapterContentText $fresh
        $result.ChapterLen = $text.Length

        if (-not (Test-ContentFieldPrimary -Chapter $fresh)) {
            throw "Chapter content empty or not in chapters.content"
        }
        $result.ContentField = 'OK'

        $projFresh = Get-Project -ProjectId $projectId
        if ($projFresh.language -eq $LangCode) {
            $result.ProjectLangOk = 'OK'
        } else {
            throw "Project language mismatch: expected $LangCode got $($projFresh.language)"
        }

        Log "[$LangCode] Quality check ..."
        $qc = Invoke-QualityCheckChapter -ChapterId $chapterId
        $result.QualityScore = $qc.score

        $voice = Get-DefaultVoiceForLanguage -Language $LangCode
        Log "[$LangCode] TTS voice=$voice ..."
        $ttsCh = Invoke-GenerateChapterTts -ChapterId $chapterId -VoiceKey $voice
        if ($ttsCh.tts_status -eq 'completed') {
            $result.Tts = 'OK'
        } else {
            throw "TTS status=$($ttsCh.tts_status)"
        }

        Log "[$LangCode] Export ZIP ..."
        $zip = Export-FullZip -ProjectId $projectId -Language $LangCode -Prefix "v03_smoke"
        $result.ZipPath = $zip.path
        if ($zip.bytes -gt 1000 -and $zip.path -match "_${LangCode}_full\.zip") {
            $result.Zip = 'OK'
        } else {
            throw "ZIP invalid or missing language in filename: $($zip.path)"
        }

        if (Test-LanguageContent -Lang $LangCode -Text $text) {
            $result.LangCheck = 'OK'
        } else {
            throw "Language content validation failed for $LangCode len=$($text.Length)"
        }

        $result.Result = 'PASS'
        Log "[$LangCode] PASS project=$projectId score=$($result.QualityScore) len=$($result.ChapterLen)"
    } catch {
        $result.Error = $_.Exception.Message
        $result.Result = 'FAIL'
        try {
            if ($chapterId) {
                $errCh = Get-Chapter -ChapterId $chapterId
                if ($errCh.last_error) { $result.LastError = [string]$errCh.last_error }
            }
        } catch { }
        Log "[$LangCode] FAIL: $($result.Error)"
    }

    return [pscustomobject]$result
}

Write-Host ""
Write-Host "=== v0.3 Single-Language Smoke Test ===" -ForegroundColor Cyan
Write-Host "Started: $startedAt"
Write-Host ""

$rows = @()
foreach ($lang in $LANGUAGES) {
    Write-Host "--- Testing $($lang.code) ($($lang.label)) ---" -ForegroundColor Yellow
    $rows += Invoke-SingleLanguageSmoke -LangCode $lang.code -LangLabel $lang.label
}

$failCount = @($rows | Where-Object { $_.Result -ne 'PASS' }).Count
$overall = if ($failCount -eq 0) { 'PASS' } else { 'FAIL' }
$endedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host ""
Write-Host "Language | ProjectId | ChapterLen | QualityScore | TTS | ZIP | LangCheck | Retried | Result" -ForegroundColor Cyan
foreach ($r in $rows) {
    $qs = if ($null -ne $r.QualityScore) { $r.QualityScore } else { '-' }
    $line = ('{0,-8} | {1,-9} | {2,-10} | {3,-12} | {4,-3} | {5,-3} | {6,-9} | {7,-7} | {8}' -f `
        $r.Language, $r.ProjectId, $r.ChapterLen, $qs, $r.Tts, $r.Zip, $r.LangCheck, $r.Retried, $r.Result)
    $color = if ($r.Result -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host $line -ForegroundColor $color
}

$reportLines = @(
    'v0.3 Single-Language Smoke Test Report'
    '========================================'
    "Started:  $startedAt"
    "Finished: $endedAt"
    "Overall:  $overall"
    ''
    'Language | ProjectId | ChapterLen | QualityScore | TTS | ZIP | LangCheck | Retried | ContentField | ProjectLang | Result'
    '--------+-----------+------------+--------------+-----+-----+-----------+---------+--------------+-------------+------'
)

foreach ($r in $rows) {
    $qs = if ($null -ne $r.QualityScore) { $r.QualityScore } else { '-' }
    $reportLines += ('{0,-8} | {1,-9} | {2,-10} | {3,-12} | {4,-3} | {5,-3} | {6,-9} | {7,-7} | {8,-12} | {9,-11} | {10}' -f `
        $r.Language, $r.ProjectId, $r.ChapterLen, $qs, $r.Tts, $r.Zip, $r.LangCheck, $r.Retried, $r.ContentField, $r.ProjectLangOk, $r.Result)
    if ($r.ZipPath) { $reportLines += "  ZIP: $($r.ZipPath)" }
    if ($r.LastError) { $reportLines += "  LAST_ERROR: $($r.LastError)" }
    if ($r.Error) { $reportLines += "  ERROR: $($r.Error)" }
    $reportLines += ''
}

$passed = $rows.Count - $failCount
$reportLines += "Summary: $passed/$($rows.Count) languages passed"
if ($failCount -gt 0) {
    $failed = ($rows | Where-Object { $_.Result -ne 'PASS' } | ForEach-Object { $_.Language }) -join ', '
    $reportLines += "Failed languages: $failed"
}

Set-Content -Path $ReportFile -Value ($reportLines -join "`n") -Encoding UTF8
Log "Report written: $ReportFile"

Write-Host ""
Write-Host "Overall: $overall ($passed/$($rows.Count) passed)" -ForegroundColor $(if ($overall -eq 'PASS') { 'Green' } else { 'Red' })
Write-Host "Report: $ReportFile"

if ($failCount -gt 0) { exit 1 }
exit 0
