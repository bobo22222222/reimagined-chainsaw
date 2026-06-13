# MVP API test (steps 3-9). Requires backend on http://localhost:8000
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\run_mvp_test.ps1

$ErrorActionPreference = "Stop"
$Base = "http://localhost:8000"
$OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) "mvp_test_output"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$LogFile = Join-Path $OutDir "run_mvp_test.log"

function Log($msg) {
    try {
        Add-Content -Path $LogFile -Value $msg -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Avoid failing the test if log file is locked
    }
    Write-Host $msg
}

Log "=== run_mvp_test $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

function Invoke-Api {
    param([string]$Method, [string]$Path, $Body = $null, [int]$TimeoutSec = 600)
    $uri = "$Base$Path"
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
        return @{
            ok   = $true
            status = $resp.StatusCode
            body = ($resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue)
            raw  = $resp.Content
        }
    } catch {
        $detail = $_.Exception.Message
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $detail = $reader.ReadToEnd()
        }
        return @{ ok = $false; detail = $detail }
    }
}

Write-Host "=== Check backend ===" -ForegroundColor Cyan
$health = Invoke-Api -Method GET -Path "/" -TimeoutSec 10
if (-not $health.ok) {
    Write-Host "Backend not running. Start: cd backend; python main.py" -ForegroundColor Red
    Log "FAIL: backend not reachable"
    exit 1
}
Write-Host "Backend OK: $Base" -ForegroundColor Green
Log "Backend OK"

Write-Host "`n=== Step 3: Create 5000-word project ===" -ForegroundColor Cyan
$create = Invoke-Api -Method POST -Path "/api/projects" -Body @{
    project_name  = "MVP-test-5k"
    title         = "Tycoon Returns"
    target_words  = 5000
    chapter_words = 2000
    language      = "中文"
    generate_tts  = $true
}
if (-not $create.ok) {
    Write-Host $create.detail -ForegroundColor Red
    Log "FAIL create: $($create.detail)"
    exit 1
}
$projectId = $create.body.id
Write-Host "Project ID: $projectId" -ForegroundColor Green
Log "project id=$projectId"

Write-Host "`n=== Step 4: Apply template tycoon_revenge ===" -ForegroundColor Cyan
$tpl = Invoke-Api -Method POST -Path "/api/projects/$projectId/apply-template" -Body @{
    template_key = "tycoon_revenge"
}
if (-not $tpl.ok) {
    Write-Host $tpl.detail -ForegroundColor Red
    Log "FAIL template: $($tpl.detail)"
    exit 1
}
Write-Host "Template OK: $($tpl.body.genre)" -ForegroundColor Green
Log "template OK genre=$($tpl.body.genre)"

Write-Host "`n=== Step 5: Generate bible (30-90s) ===" -ForegroundColor Cyan
$bible = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-bible" -TimeoutSec 300
if (-not $bible.ok) {
    Write-Host "Bible failed:" -ForegroundColor Red
    Write-Host $bible.detail
    Log "FAIL bible: $($bible.detail)"
    exit 1
}
$bibleLen = if ($bible.body.story_bible) { $bible.body.story_bible.Length } else { 0 }
Write-Host "Bible OK, length: $bibleLen" -ForegroundColor Green
Log "bible OK len=$bibleLen"

Write-Host "`n=== Step 6: Generate outline ===" -ForegroundColor Cyan
$outline = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-outline" -TimeoutSec 300
if (-not $outline.ok) {
    Write-Host $outline.detail -ForegroundColor Red
    Log "FAIL outline: $($outline.detail)"
    exit 1
}
Write-Host "Outline OK" -ForegroundColor Green
Log "outline OK"

Write-Host "`n=== Step 7: Generate first 3 chapters (3-8 min) ===" -ForegroundColor Cyan
$first3 = Invoke-Api -Method POST -Path "/api/projects/$projectId/generate-first-3" -Body @{
    voice_key = "zh_male"
    rate      = "+0%"
} -TimeoutSec 900
if (-not $first3.ok) {
    Write-Host $first3.detail -ForegroundColor Red
    Log "FAIL first3: $($first3.detail)"
    exit 1
}
Write-Host $first3.body.message -ForegroundColor Yellow
$genCh = $first3.body.generated_chapters -join ", "
Write-Host "Generated chapters: $genCh" -ForegroundColor Green
Log "first3 OK message=$($first3.body.message) chapters=$genCh"

Write-Host "`n=== Step 8: Check MP3 ===" -ForegroundColor Cyan
$chapters = Invoke-Api -Method GET -Path "/api/projects/$projectId/chapters" -TimeoutSec 30
$mp3Ok = 0
foreach ($ch in $chapters.body) {
    if ($ch.chapter_number -gt 3) { continue }
    $mp3 = $ch.audio_path -and (Test-Path $ch.audio_path)
    if ($mp3) { $mp3Ok++ }
    $mp3Mark = if ($mp3) { "OK" } else { "MISSING" }
    $line = "ch $($ch.chapter_number) MP3=$mp3Mark status=$($ch.status)"
    Write-Host "  $line"
    Log $line
}
Write-Host "MP3: $mp3Ok/3" -ForegroundColor $(if ($mp3Ok -eq 3) { "Green" } else { "Yellow" })
Log "MP3=$mp3Ok/3"

Write-Host "`n=== Step 9: Export full ZIP ===" -ForegroundColor Cyan
$zipPath = Join-Path $OutDir "project_${projectId}_full.zip"
try {
    Invoke-WebRequest -Uri "$Base/api/projects/$projectId/export/full-zip" -OutFile $zipPath -TimeoutSec 120 -UseBasicParsing
    $size = (Get-Item $zipPath).Length
    Write-Host "ZIP saved: $zipPath ($size bytes)" -ForegroundColor Green
    Log "zip size=$size path=$zipPath"
} catch {
    Write-Host "Export failed: $($_.Exception.Message)" -ForegroundColor Red
    Log "FAIL zip: $($_.Exception.Message)"
    exit 1
}

Write-Host "`n=== MVP test done ===" -ForegroundColor Cyan
Write-Host "Project ID: $projectId"
Write-Host "UI: http://localhost:3000/chapters?projectId=$projectId"
Log "done id=$projectId"
