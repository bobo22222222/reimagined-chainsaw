# Shared API helpers for test scripts (dot-source from other .ps1)
#   . "$PSScriptRoot\lib_api.ps1"

$script:ApiBase = "http://localhost:8000"
$script:TestOutDir = Join-Path (Split-Path $PSScriptRoot -Parent) "mvp_test_output"

function Init-TestLog([string]$name) {
    New-Item -ItemType Directory -Force -Path $script:TestOutDir | Out-Null
    $script:TestLogFile = Join-Path $script:TestOutDir "$name.log"
    if (Test-Path $script:TestLogFile) { Remove-Item $script:TestLogFile -Force -ErrorAction SilentlyContinue }
}

function Log([string]$msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    try { Add-Content -Path $script:TestLogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
    Write-Host $line
}

function ConvertFrom-JsonUtf8 {
    param([string]$JsonText)
    if (-not $JsonText) { return $null }
    return ($JsonText | ConvertFrom-Json -ErrorAction SilentlyContinue)
}

function Get-ResponseJsonText {
    param($WebResponse)
    if ($null -eq $WebResponse) { return $null }
    $raw = $WebResponse.Content
    if (-not $raw) { return $null }
    try {
        # PS 5.1 may mis-decode UTF-8; re-decode via ISO-8859-1 byte round-trip
        $bytes = [System.Text.Encoding]::GetEncoding(28591).GetBytes($raw)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return $raw
    }
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null,
        [int]$TimeoutSec = 600
    )
    $uri = "$script:ApiBase$Path"
    $params = @{
        Uri             = $uri
        Method          = $Method
        TimeoutSec      = $TimeoutSec
        UseBasicParsing = $true
    }
    if ($Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }
    try {
        $resp = Invoke-WebRequest @params
        $jsonText = Get-ResponseJsonText -WebResponse $resp
        return @{
            ok     = $true
            status = $resp.StatusCode
            body   = (ConvertFrom-JsonUtf8 -JsonText $jsonText)
            raw    = $jsonText
        }
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $rawBody = $reader.ReadToEnd()
                if ($rawBody) {
                    $parsed = $rawBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($parsed.detail) {
                        if ($parsed.detail -is [string]) { $detail = $parsed.detail }
                        else { $detail = ($parsed.detail | ConvertTo-Json -Compress) }
                    } else { $detail = $rawBody }
                }
            } catch { }
        }
        return @{ ok = $false; detail = $detail }
    }
}

function Ensure-Backend {
    param([int]$WaitSec = 60)
    try {
        $r = Invoke-WebRequest -Uri "$script:ApiBase/" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { Log "Backend already running"; return }
    } catch { }

    $backend = Join-Path (Split-Path $PSScriptRoot -Parent) "backend"
    Log "Backend not running - starting python main.py ..."
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$backend'; python main.py" -WindowStyle Minimized

    for ($i = 1; $i -le $WaitSec; $i++) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-WebRequest -Uri "$script:ApiBase/" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) {
                Log "Backend ready (attempt $i)"
                return
            }
        } catch {
            if ($i % 5 -eq 0) { Log "Waiting for backend... ($i)" }
        }
    }
    throw "Backend not running at $script:ApiBase after ${WaitSec}s"
}

function Assert-Backend {
    Ensure-Backend
    Log "Backend OK"
}

function New-TestProject {
    param(
        [string]$Name,
        [int]$TargetWords,
        [int]$ChapterWords = 2000
    )
    $r = Invoke-Api -Method POST -Path "/api/projects" -Body @{
        project_name  = $Name
        title         = "Phased-$TargetWords"
        target_words  = $TargetWords
        chapter_words = $ChapterWords
        language      = "中文"
        generate_tts  = $true
        generate_srt  = $true
    }
    if (-not $r.ok) { throw "Create project failed: $($r.detail)" }
    $id = $r.body.id
    Log "Created project id=$id target_words=$TargetWords chapter_words=$ChapterWords"

    $t = Invoke-Api -Method POST -Path "/api/projects/$id/apply-template" -Body @{ template_key = "tycoon_revenge" }
    if (-not $t.ok) { throw "Template failed: $($t.detail)" }

    $b = Invoke-Api -Method POST -Path "/api/projects/$id/generate-bible" -TimeoutSec 300
    if (-not $b.ok) { throw "Bible failed: $($b.detail)" }
    Log "Bible OK len=$($b.body.story_bible.Length)"

    $o = Invoke-Api -Method POST -Path "/api/projects/$id/generate-outline" -TimeoutSec 300
    if (-not $o.ok) { throw "Outline failed: $($o.detail)" }
    Log "Outline OK"

    return $id
}

function Get-ChapterList {
    param([int]$ProjectId)
    $r = Invoke-Api -Method GET -Path "/api/projects/$ProjectId/chapters" -TimeoutSec 60
    if (-not $r.ok) { throw "List chapters failed: $($r.detail)" }
    return @($r.body)
}

function Invoke-BatchRange {
    param(
        [int]$ProjectId,
        [int]$Start,
        [int]$End,
        [int]$TimeoutSec = 1800
    )
    Log "Batch generate ch $Start-$End ..."
    $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/generate-chapter-range" -Body @{
        start_chapter = $Start
        end_chapter   = $End
        voice_key     = "zh_male"
        rate          = "+0%"
    } -TimeoutSec $TimeoutSec
    if (-not $r.ok) { throw "Batch $Start-$End failed: $($r.detail)" }
    Log "  generated=$($r.body.generated_chapters -join ',') skipped=$($r.body.skipped_chapters -join ',') failed=$($r.body.failed_chapters -join ',')"
    if ($r.body.failed_chapters -and $r.body.failed_chapters.Count -gt 0) {
        throw "Batch had failures: $($r.body.failed_chapters -join ',')"
    }
    return $r.body
}

function Invoke-GenerateAllChapters {
    param([int]$ProjectId)
    $chs = Get-ChapterList -ProjectId $ProjectId
    $max = ($chs | ForEach-Object { $_.chapter_number } | Measure-Object -Maximum).Maximum
    Log "Total chapters: $max"
    for ($start = 1; $start -le $max; $start += 5) {
        $end = [Math]::Min($start + 4, $max)
        Invoke-BatchRange -ProjectId $ProjectId -Start $start -End $end | Out-Null
    }
}

function Get-ChapterContentText($Chapter) {
    if ($null -ne $Chapter.content -and ([string]$Chapter.content).Trim().Length -gt 0) {
        return [string]$Chapter.content
    }
    if ($null -ne $Chapter.content_cn) {
        return [string]$Chapter.content_cn
    }
    return ""
}

# --------------------------------------------------------------------------- #
# v0.3 单语言冒烟测试 API 封装
# --------------------------------------------------------------------------- #
$script:DefaultVoiceByLanguage = @{
    zh = "zh_male"
    en = "en_male"
    es = "es_male"
    ja = "ja_male"
}

function Create-Project {
    param(
        [string]$ProjectName,
        [string]$Title,
        [int]$TargetWords = 5000,
        [int]$ChapterWords = 2000,
        [string]$Language = "zh",
        [bool]$GenerateTts = $false
    )
    $r = Invoke-Api -Method POST -Path "/api/projects" -Body @{
        project_name  = $ProjectName
        title         = $Title
        target_words  = $TargetWords
        chapter_words = $ChapterWords
        language      = $Language
        generate_tts  = $GenerateTts
    }
    if (-not $r.ok) { throw "CreateProject failed: $($r.detail)" }
    return $r.body
}

function Save-UrbanSettings {
    param([int]$ProjectId, [hashtable]$Settings)
    $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/save-urban-settings" -Body $Settings
    if (-not $r.ok) { throw "SaveUrbanSettings failed: $($r.detail)" }
    return $r.body
}

function Invoke-GenerateBible {
    param([int]$ProjectId, [int]$TimeoutSec = 300)
    $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/generate-bible" -TimeoutSec $TimeoutSec
    if (-not $r.ok) { throw "GenerateBible failed: $($r.detail)" }
    return $r.body
}

function Invoke-GenerateOutline {
    param([int]$ProjectId, [int]$TimeoutSec = 300)
    $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/generate-outline" -TimeoutSec $TimeoutSec
    if (-not $r.ok) { throw "GenerateOutline failed: $($r.detail)" }
    return $r.body
}

function Get-Chapter {
    param([int]$ChapterId)
    $r = Invoke-Api -Method GET -Path "/api/chapters/$ChapterId" -TimeoutSec 60
    if (-not $r.ok) { throw "GetChapter failed: $($r.detail)" }
    return $r.body
}

function Get-Project {
    param([int]$ProjectId)
    $r = Invoke-Api -Method GET -Path "/api/projects/$ProjectId" -TimeoutSec 60
    if (-not $r.ok) { throw "GetProject failed: $($r.detail)" }
    return $r.body
}

function Invoke-ApplyTemplate {
    param([int]$ProjectId, [string]$TemplateKey = "tycoon_revenge")
    $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/apply-template" -Body @{
        template_key = $TemplateKey
    }
    if (-not $r.ok) { throw "ApplyTemplate failed: $($r.detail)" }
    return $r.body
}

function Invoke-GenerateChapter {
    param([int]$ChapterId, [int]$TimeoutSec = 900)
    $r = Invoke-Api -Method POST -Path "/api/chapters/$ChapterId/generate" -TimeoutSec $TimeoutSec
    if (-not $r.ok) { throw "GenerateChapter failed: $($r.detail)" }
    return $r.body
}

function Invoke-QualityCheckChapter {
    param([int]$ChapterId, [int]$TimeoutSec = 600)
    $r = Invoke-Api -Method POST -Path "/api/chapters/$ChapterId/quality-check" -TimeoutSec $TimeoutSec
    if (-not $r.ok) { throw "QualityCheckChapter failed: $($r.detail)" }
    return $r.body
}

function Invoke-GenerateChapterTts {
    param(
        [int]$ChapterId,
        [string]$VoiceKey = "zh_male",
        [string]$Rate = "+0%",
        [int]$TimeoutSec = 600
    )
    $r = Invoke-Api -Method POST -Path "/api/chapters/$ChapterId/tts" -Body @{
        voice_key = $VoiceKey
        rate      = $Rate
    } -TimeoutSec $TimeoutSec
    if (-not $r.ok) { throw "GenerateChapterTts failed: $($r.detail)" }
    return $r.body
}

function Export-FullZip {
    param(
        [int]$ProjectId,
        [string]$Language = "zh",
        [string]$OutDir = $script:TestOutDir,
        [string]$Prefix = "v03_smoke"
    )
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $outPath = Join-Path $OutDir "${Prefix}_project_${ProjectId}_${Language}_full.zip"
    $uri = "$script:ApiBase/api/projects/$ProjectId/export/full-zip"
    try {
        Invoke-WebRequest -Uri $uri -OutFile $outPath -TimeoutSec 600 -UseBasicParsing | Out-Null
    } catch {
        throw "ExportFullZip failed: $($_.Exception.Message)"
    }
    if (-not (Test-Path $outPath)) { throw "ExportFullZip: file not created" }
    $bytes = (Get-Item $outPath).Length
    return @{ path = $outPath; bytes = $bytes; language = $Language }
}

function Get-FirstChapter {
    param([int]$ProjectId)
    $chs = Get-ChapterList -ProjectId $ProjectId
    $ch = @($chs | Where-Object { [int]$_.chapter_number -eq 1 } | Select-Object -First 1)
    if (-not $ch) { throw "Chapter 1 not found for project $ProjectId" }
    return $ch
}

function Invoke-RewriteChapter {
    param([int]$ChapterId, [int]$TimeoutSec = 900)
    $r = Invoke-Api -Method POST -Path "/api/chapters/$ChapterId/rewrite" -TimeoutSec $TimeoutSec
    if (-not $r.ok) { throw "RewriteChapter failed: $($r.detail)" }
    return $r.body
}

function Invoke-GenerateFirst3 {
    param(
        [int]$ProjectId,
        [string]$VoiceKey = "zh_male",
        [int]$TimeoutSec = 3600
    )
    $r = Invoke-Api -Method POST -Path "/api/projects/$ProjectId/generate-first-3" -Body @{
        voice_key = $VoiceKey
        rate      = "+0%"
    } -TimeoutSec $TimeoutSec
    if (-not $r.ok) { throw "GenerateFirst3 failed: $($r.detail)" }
    return $r.body
}

function Get-ChaptersByNumber {
    param([int]$ProjectId, [int[]]$Numbers)
    $chs = Get-ChapterList -ProjectId $ProjectId
    return @($chs | Where-Object { $Numbers -contains [int]$_.chapter_number } | Sort-Object chapter_number)
}

function Get-DefaultVoiceForLanguage {
    param([string]$Language)
    $key = $script:DefaultVoiceByLanguage[$Language]
    if (-not $key) { return "zh_male" }
    return $key
}

function Get-MediaStats {
    param([int]$ProjectId)
    $chs = Get-ChapterList -ProjectId $ProjectId
    $total = $chs.Count
    $contentOk = 0
    $mp3Ok = 0
    $mp3Bytes = 0
    foreach ($ch in $chs) {
        $text = Get-ChapterContentText $ch
        if ($text.Trim().Length -gt 0) { $contentOk++ }
        if ($ch.audio_path -and (Test-Path ([string]$ch.audio_path))) {
            $mp3Ok++
            $mp3Bytes += (Get-Item ([string]$ch.audio_path)).Length
        }
    }
    return @{
        total       = $total
        content_ok  = $contentOk
        mp3_ok      = $mp3Ok
        mp3_bytes   = $mp3Bytes
        mp3_mb      = [Math]::Round($mp3Bytes / 1MB, 2)
    }
}

function Export-ProjectZips {
    param([int]$ProjectId, [string]$Prefix)
    $results = @{}
    $types = @("full-zip", "audio-zip", "chapters-zip", "txt")
    foreach ($t in $types) {
        $out = Join-Path $script:TestOutDir "${Prefix}_project_${ProjectId}_$($t.Replace('-','_'))"
        if ($t -eq "txt") { $out += ".txt" } else { $out += ".zip" }
        try {
            Invoke-WebRequest -Uri "$script:ApiBase/api/projects/$ProjectId/export/$t" -OutFile $out -TimeoutSec 600 -UseBasicParsing
            $sz = (Get-Item $out).Length
            $results[$t] = @{ path = $out; bytes = $sz; mb = [Math]::Round($sz / 1MB, 2) }
            Log "Export $t : $sz bytes ($([Math]::Round($sz/1MB,2)) MB)"
        } catch {
            Log "Export $t FAILED: $($_.Exception.Message)"
            $results[$t] = @{ error = $_.Exception.Message }
        }
    }
    return $results
}
