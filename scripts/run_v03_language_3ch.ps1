# v0.3 extended test: zh/en/es/ja -- 5000 words, first 3 chapters each
# Length policy: only EXTREME over-limit fails; acceptable-range drift = WARNING, continue pipeline
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\lib_api.ps1"

Init-TestLog "v03_language_3ch"
Assert-Backend

$ReportFile = Join-Path $script:TestOutDir "V03_LANGUAGE_3CH_REPORT.txt"
$startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$LANGUAGES = @(
    @{ code = "zh"; label = "Chinese" }
    @{ code = "en"; label = "English" }
    @{ code = "es"; label = "Spanish" }
    @{ code = "ja"; label = "Japanese" }
)

# acceptable_* = soft range (WARNING only); extreme_max = hard FAIL
$LENGTH_BOUNDS = @{
    zh = @{ acceptable_min = 1400; acceptable_max = 3000; extreme_max = 5000 }
    en = @{ acceptable_min = 800; acceptable_max = 3000; extreme_max = 4000 }
    es = @{ acceptable_min = 800; acceptable_max = 3000; extreme_max = 4000 }
    ja = @{ acceptable_min = 1400; acceptable_max = 4500; extreme_max = 6000 }
}

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

function Measure-ChapterLength {
    param([string]$Lang, [string]$Text)
    if (-not $Text) { return 0 }
    if ($Lang -eq 'en' -or $Lang -eq 'es') {
        return ([regex]::Matches($Text, '\b[\w'']+\b')).Count
    }
    return ($Text -replace '\s', '').Length
}

function Test-LanguageContent {
    param([string]$Lang, [string]$Text)
    if (-not $Text -or $Text.Trim().Length -lt 50) { return $false }

    $cjk = Count-CharsInRange -Text $Text -Lo 0x4E00 -Hi 0x9FFF
    $kana = Count-CharsInRange -Text $Text -Lo 0x3040 -Hi 0x30FF
    $latin = ([regex]::Matches($Text, '[A-Za-z]')).Count

    switch ($Lang) {
        'zh' { return ($cjk -ge 20) }
        'en' { return ($latin -ge 80 -and $cjk -lt 20) }
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

function Get-ChapterLengthTier {
    param([string]$Lang, [int]$Len)
    $b = $LENGTH_BOUNDS[$Lang]
    if (-not $b) { return "unknown" }
    if ($Len -gt $b.extreme_max) { return "extreme" }
    if ($Len -gt $b.acceptable_max) { return "warning" }
    if ($Len -lt $b.acceptable_min) { return "warning" }
    return "ok"
}

function Resolve-LengthStatus {
    param([string[]]$Tiers)
    if ($Tiers -contains 'extreme') { return 'EXTREME_FAIL' }
    if ($Tiers -contains 'warning') { return 'WARNING' }
    return 'OK'
}

function Format-QcLength {
    param($QcResponse, [int]$ChapterNumber)
    if ($null -eq $QcResponse -or $null -eq $QcResponse.length) {
        return "ch${ChapterNumber}=N/A"
    }
    $L = $QcResponse.length
    $val = if ($null -ne $L.value) { $L.value } else { '?' }
    $unit = if ($L.unit) { $L.unit } else { '' }
    $judgment = if ($L.judgment) { $L.judgment } else { if ($L.status) { $L.status } else { '' } }
    return "ch${ChapterNumber}=${val} ${unit} ${judgment}".Trim()
}

function Invoke-SingleLanguage3ChTest {
    param([string]$LangCode, [string]$LangLabel)

    $result = [ordered]@{
        Language        = $LangCode
        Label           = $LangLabel
        ProjectId       = $null
        ChaptersOk      = 'FAIL'
        LengthStatus    = 'OK'
        QualityOk       = 'FAIL'
        RewriteOk       = 'FAIL'
        RewriteLangOk   = 'FAIL'
        TtsOk           = 'FAIL'
        ZipOk           = 'FAIL'
        LangCheckOk     = 'FAIL'
        ChapterLengths  = ''
        LengthWarnings  = ''
        QualityScores   = ''
        QualityLength   = 'N/A'
        Retried         = 'NO'
        RetryReason     = ''
        Result          = 'FAIL'
        Error           = ''
        ZipPath         = ''
    }

    try {
        $ts = Get-Date -Format "HHmmss"
        $proj = Create-Project `
            -ProjectName "v03-3ch-$LangCode-$ts" `
            -Title "V03-3Ch-$LangCode" `
            -TargetWords 5000 `
            -ChapterWords 2000 `
            -Language $LangCode `
            -GenerateTts $false
        $projectId = [int]$proj.id
        $result.ProjectId = $projectId
        Log "[$LangCode] Created project id=$projectId"

        Invoke-ApplyTemplate -ProjectId $projectId -TemplateKey "tycoon_revenge" | Out-Null
        Invoke-GenerateBible -ProjectId $projectId | Out-Null
        Invoke-GenerateOutline -ProjectId $projectId | Out-Null
        Log "[$LangCode] Bible + outline OK"

        $voice = Get-DefaultVoiceForLanguage -Language $LangCode
        Invoke-BatchRange -ProjectId $projectId -Start 1 -End 3 -TimeoutSec 3600 | Out-Null
        Log "[$LangCode] Chapters 1-3 generated"

        $chs = Get-ChaptersByNumber -ProjectId $projectId -Numbers @(1, 2, 3)
        if ($chs.Count -lt 3) { throw "Expected 3 chapters, got $($chs.Count)" }

        foreach ($ch in $chs) {
            $fresh = Get-Chapter -ChapterId ([int]$ch.id)
            if ($fresh.generation_retry_reason -eq 'JA_EXTREME_LENGTH') {
                $result.Retried = 'YES'
                $result.RetryReason = 'JA_EXTREME_LENGTH'
                Log "[$LangCode] Detected JA_EXTREME_LENGTH retry on ch$($fresh.chapter_number)"
            }
        }

        $lenParts = @()
        $warnParts = @()
        $tiers = @()
        $allLangOk = $true
        foreach ($ch in $chs) {
            $text = Get-ChapterContentText $ch
            if (-not $text -or $text.Trim().Length -lt 50) {
                throw "Chapter $($ch.chapter_number) content empty"
            }
            $m = Measure-ChapterLength -Lang $LangCode -Text $text
            $lenParts += "ch$($ch.chapter_number)=$m"
            $tier = Get-ChapterLengthTier -Lang $LangCode -Len $m
            $tiers += $tier
            if ($tier -eq 'extreme') {
                $warnParts += "ch$($ch.chapter_number)=EXTREME($m)"
            } elseif ($tier -eq 'warning') {
                $warnParts += "ch$($ch.chapter_number)=WARN($m)"
            }
            if (-not (Test-LanguageContent -Lang $LangCode -Text $text)) { $allLangOk = $false }
        }

        $result.ChapterLengths = ($lenParts -join ', ')
        $result.LengthWarnings = ($warnParts -join ', ')
        $result.LengthStatus = Resolve-LengthStatus -Tiers $tiers

        if ($result.LengthStatus -eq 'EXTREME_FAIL') {
            throw "Length extreme (over hard limit): $($result.ChapterLengths)"
        }
        if ($result.LengthStatus -eq 'WARNING') {
            Log "[$LangCode] LengthStatus=WARNING (continuing QC/Rewrite/TTS/ZIP): $($result.LengthWarnings)"
        }

        if ($allLangOk) {
            $result.LangCheckOk = 'OK'
        } else {
            throw "Language check failed for one or more chapters"
        }
        $result.ChaptersOk = 'OK'

        $scoreParts = @()
        $qcLenParts = @()
        foreach ($ch in $chs) {
            $qc = Invoke-QualityCheckChapter -ChapterId ([int]$ch.id)
            $scoreParts += "ch$($ch.chapter_number)=$($qc.score)"
            if ($null -eq $qc.score) { throw "QC returned no score for ch $($ch.chapter_number)" }
            $qcLenParts += (Format-QcLength -QcResponse $qc -ChapterNumber ([int]$ch.chapter_number))
        }
        $result.QualityScores = ($scoreParts -join ', ')
        $result.QualityLength = ($qcLenParts -join '; ')
        $result.QualityOk = 'OK'
        Log "[$LangCode] QC scores: $($result.QualityScores)"
        Log "[$LangCode] QualityLength: $($result.QualityLength)"

        $rewriteCh = $chs | Where-Object { [int]$_.chapter_number -eq 2 } | Select-Object -First 1
        $rw = Invoke-RewriteChapter -ChapterId ([int]$rewriteCh.id) -TimeoutSec 900
        $rwText = Get-ChapterContentText $rw
        if (-not $rwText -or $rwText.Trim().Length -lt 50) {
            throw "Rewrite chapter 2 returned empty content"
        }
        $result.RewriteOk = 'OK'
        if (Test-LanguageContent -Lang $LangCode -Text $rwText) {
            $result.RewriteLangOk = 'OK'
        } else {
            throw "Rewrite output failed language check"
        }
        Log "[$LangCode] Rewrite ch2 OK len=$(Measure-ChapterLength -Lang $LangCode -Text $rwText)"

        foreach ($ch in $chs) {
            $ttsCh = Invoke-GenerateChapterTts -ChapterId ([int]$ch.id) -VoiceKey $voice
            if ($ttsCh.tts_status -ne 'completed') {
                throw "TTS failed ch $($ch.chapter_number) status=$($ttsCh.tts_status)"
            }
        }
        $result.TtsOk = 'OK'
        Log "[$LangCode] TTS 1-3 OK voice=$voice"

        $zip = Export-FullZip -ProjectId $projectId -Language $LangCode -Prefix "v03_3ch"
        if ($zip.bytes -gt 1000 -and $zip.path -match "_${LangCode}_full\.zip") {
            $result.ZipOk = 'OK'
            $result.ZipPath = $zip.path
        } else {
            throw "ZIP invalid: $($zip.path)"
        }

        $result.Result = 'PASS'
        Log "[$LangCode] PASS project=$projectId LengthStatus=$($result.LengthStatus) lengths=$($result.ChapterLengths)"
    } catch {
        $result.Error = $_.Exception.Message
        $result.Result = 'FAIL'
        if ($result.LengthStatus -eq 'OK' -and $result.Error -match 'extreme|hard limit') {
            $result.LengthStatus = 'EXTREME_FAIL'
        }
        try {
            if ($result.ProjectId) {
                $failChs = Get-ChaptersByNumber -ProjectId ([int]$result.ProjectId) -Numbers @(1, 2, 3)
                foreach ($fc in $failChs) {
                    $det = Get-Chapter -ChapterId ([int]$fc.id)
                    if ($det.generation_retry_reason -eq 'JA_EXTREME_LENGTH') {
                        $result.Retried = 'YES'
                        $result.RetryReason = 'JA_EXTREME_LENGTH'
                    }
                    if ($det.last_error -and -not $result.Error) {
                        $result.Error = [string]$det.last_error
                    }
                }
            }
        } catch { }
        Log "[$LangCode] FAIL: $($result.Error)"
    }

    return [pscustomobject]$result
}

Write-Host ""
Write-Host "=== v0.3 Language 3-Chapter Extended Test ===" -ForegroundColor Cyan
Write-Host "Started: $startedAt"
Write-Host "Target: 5000 words / 3 chapters per language (zh, en, es, ja)"
Write-Host ""

$rows = @()
foreach ($lang in $LANGUAGES) {
    Write-Host "--- Testing $($lang.code) ($($lang.label)) ---" -ForegroundColor Yellow
    $rows += Invoke-SingleLanguage3ChTest -LangCode $lang.code -LangLabel $lang.label
}

$failCount = @($rows | Where-Object { $_.Result -ne 'PASS' }).Count
$overall = if ($failCount -eq 0) { 'PASS' } else { 'FAIL' }
$endedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host ""
Write-Host "Lang | ProjectId | Lengths | LengthStatus | QC | Rewrite | TTS | ZIP | Result" -ForegroundColor Cyan
foreach ($r in $rows) {
    $line = ('{0,-4} | {1,-9} | {2,-22} | {3,-12} | {4,-3} | {5,-7} | {6,-3} | {7,-3} | {8}' -f `
        $r.Language, $r.ProjectId, $r.ChapterLengths, $r.LengthStatus, `
        $r.QualityOk, $r.RewriteLangOk, $r.TtsOk, $r.ZipOk, $r.Result)
    $color = if ($r.Result -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host $line -ForegroundColor $color
}

$reportLines = @(
    'v0.3 Language 3-Chapter Extended Test Report'
    '=============================================='
    "Started:  $startedAt"
    "Finished: $endedAt"
    "Overall:  $overall"
    ''
    'Length FAIL only on extreme: zh>5000 | en/es>4000 words | ja>6000 chars'
    'LengthStatus: OK | WARNING | EXTREME_FAIL (WARNING does not block pipeline)'
    ''
    'Lang | ProjectId | Chapters | LengthStatus | QC | Rewrite | TTS | ZIP | LangCheck | Result'
    '-----+-----------+----------+--------------+----+---------+-----+-----+-----------+------'
)

foreach ($r in $rows) {
    $reportLines += ('{0,-4} | {1,-9} | {2,-8} | {3,-12} | {4,-2} | {5,-7} | {6,-3} | {7,-3} | {8,-9} | {9}' -f `
        $r.Language, $r.ProjectId, $r.ChaptersOk, $r.LengthStatus, $r.QualityOk, `
        $r.RewriteOk, $r.TtsOk, $r.ZipOk, $r.LangCheckOk, $r.Result)
    $reportLines += "  Lengths: $($r.ChapterLengths)"
    if ($r.LengthWarnings) { $reportLines += "  LengthWarnings: $($r.LengthWarnings)" }
    if ($r.Retried -ne 'NO') {
        $reportLines += "  Retried: $($r.Retried)"
        $reportLines += "  RetryReason: $($r.RetryReason)"
    }
    $reportLines += "  QC: $($r.QualityScores)"
    $reportLines += "  QualityLength: $($r.QualityLength)"
    if ($r.ZipPath) { $reportLines += "  ZIP: $($r.ZipPath)" }
    if ($r.Error) { $reportLines += "  ERROR: $($r.Error)" }
    $reportLines += ''
}

$passed = $rows.Count - $failCount
$reportLines += "Summary: $passed/$($rows.Count) languages passed"
Set-Content -Path $ReportFile -Value ($reportLines -join "`n") -Encoding UTF8
Log "Report written: $ReportFile"

Write-Host ""
Write-Host "Overall: $overall ($passed/$($rows.Count) passed)" -ForegroundColor $(if ($overall -eq 'PASS') { 'Green' } else { 'Red' })
Write-Host "Report: $ReportFile"

if ($failCount -gt 0) { exit 1 }
exit 0
