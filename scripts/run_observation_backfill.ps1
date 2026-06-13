$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib_api.ps1"
Assert-Backend

foreach ($proj in @(10, 11)) {
    Write-Host "=== MP3 backfill project $proj ===" -ForegroundColor Cyan
    $chs = Get-ChapterList -ProjectId $proj
    $max = ($chs | ForEach-Object { $_.chapter_number } | Measure-Object -Maximum).Maximum
    for ($s = 1; $s -le $max; $s += 5) {
        $e = [Math]::Min($s + 4, $max)
        $r = Invoke-Api -Method POST -Path "/api/projects/$proj/generate-tts-range" -Body @{
            start_chapter = $s
            end_chapter   = $e
            voice_key     = "zh_female"
            rate          = "+0%"
        } -TimeoutSec 1800
        Write-Host "  batch $s-$e ok=$($r.ok)"
    }
    $stats = Get-MediaStats -ProjectId $proj
    Write-Host "  MP3: $($stats.mp3_ok)/$($stats.total)" -ForegroundColor Green
}

Write-Host "=== Retry R1 project 8 ch3 ===" -ForegroundColor Cyan
$r = Invoke-Api -Method POST -Path "/api/projects/8/generate-chapter-range" -Body @{
    start_chapter = 3
    end_chapter   = 3
    voice_key     = "zh_female"
    rate          = "+0%"
} -TimeoutSec 600
Write-Host "ch3 ok=$($r.ok) gen=$($r.body.generated_chapters -join ',') failed=$($r.body.failed_chapters -join ',')"
