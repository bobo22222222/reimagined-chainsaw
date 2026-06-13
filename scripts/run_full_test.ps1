# Full MVP test: start backend/frontend, run run_mvp_test.ps1, write logs.
# Usage (project root):
#   powershell -ExecutionPolicy Bypass -File scripts\run_full_test.ps1

$ErrorActionPreference = "Continue"
$Root = Split-Path $PSScriptRoot -Parent
$LogDir = Join-Path $Root "mvp_test_output"
$LogFile = Join-Path $LogDir "run_full_test.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

Log "=== run_full_test START ==="
Log "Root: $Root"

$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"

if (-not (Test-Path (Join-Path $Backend ".env"))) {
    Copy-Item (Join-Path $Backend ".env.example") (Join-Path $Backend ".env")
    Log "Created backend/.env from .env.example"
}

$envLine = Select-String -Path (Join-Path $Backend ".env") -Pattern "^DEEPSEEK_API_KEY=" | Select-Object -First 1
$keyVal = if ($envLine) { ($envLine.Line -split "=", 2)[1].Trim() } else { "" }
$exampleKey = (Select-String -Path (Join-Path $Backend ".env.example") -Pattern "^DEEPSEEK_API_KEY=" | Select-Object -First 1)
$placeholder = if ($exampleKey) { ($exampleKey.Line -split "=", 2)[1].Trim() } else { "你的_deepseek_api_key" }
$keyOk = $keyVal -and ($keyVal -ne $placeholder) -and ($keyVal.Length -ge 20) -and ($keyVal -like "sk-*")
if ($keyOk) {
    Log "DEEPSEEK_API_KEY: configured (len=$($keyVal.Length))"
} else {
    Log "DEEPSEEK_API_KEY: PLACEHOLDER or invalid - edit backend/.env with real sk-... key"
}

if (-not $keyOk) {
    Log "STOP: Set DEEPSEEK_API_KEY in backend/.env (sk-... , len>=20)"
    Log "  notepad backend\.env"
    exit 2
}

if (-not (Test-Path (Join-Path $Frontend ".env.local"))) {
    Copy-Item (Join-Path $Frontend ".env.local.example") (Join-Path $Frontend ".env.local")
    Log "Created frontend/.env.local"
}

Log "Installing backend deps..."
Push-Location $Backend
pip install -r requirements.txt -q 2>&1 | Out-Null
Pop-Location

$backendUp = $false
try {
    $r = Invoke-WebRequest -Uri "http://localhost:8000/" -UseBasicParsing -TimeoutSec 3
    $backendUp = ($r.StatusCode -eq 200)
    Log "Backend already running (200)"
} catch {
    Log "Starting backend..."
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$Backend'; python main.py" -WindowStyle Minimized
    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8000/" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) {
                $backendUp = $true
                Log "Backend ready (attempt $i)"
                break
            }
        } catch {
            Log "Waiting for backend... ($i/30)"
        }
    }
}
if (-not $backendUp) {
    Log "FAIL: backend did not start"
    exit 1
}

$frontendUp = $false
try {
    $r = Invoke-WebRequest -Uri "http://localhost:3000/" -UseBasicParsing -TimeoutSec 3
    $frontendUp = ($r.StatusCode -eq 200)
    Log "Frontend already running (200)"
} catch {
    Log "Starting frontend..."
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$Frontend'; if (-not (Test-Path node_modules)) { npm install }; npm run dev" -WindowStyle Minimized
    for ($i = 1; $i -le 60; $i++) {
        Start-Sleep -Seconds 3
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:3000/" -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200) {
                $frontendUp = $true
                Log "Frontend ready (attempt $i)"
                break
            }
        } catch {
            if ($i % 5 -eq 0) { Log "Waiting for frontend... ($i/60)" }
        }
    }
}
if ($frontendUp) { Log "Frontend: OK" } else { Log "Frontend: not ready (API test can still run)" }

Log "Running run_mvp_test.ps1 ..."
$mvpLog = Join-Path $LogDir "run_mvp_test.log"
if (Test-Path $mvpLog) { Remove-Item $mvpLog -Force -ErrorAction SilentlyContinue }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\run_mvp_test.ps1")
$mvpExit = $LASTEXITCODE
if ($null -eq $mvpExit) { $mvpExit = 0 }
Log "run_mvp_test exit code: $mvpExit"

$summary = Join-Path $LogDir "SUMMARY.txt"
$mvpContent = if (Test-Path $mvpLog) { Get-Content $mvpLog -Raw } else { "(no log)" }
@"
=== MVP TEST SUMMARY $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===
Backend: $(if ($backendUp) { 'PASS' } else { 'FAIL' })
Frontend: $(if ($frontendUp) { 'PASS' } else { 'SKIP/FAIL' })
DEEPSEEK_API_KEY: $(if ($keyOk) { 'PASS' } else { 'FAIL (placeholder)' })
run_mvp_test exit code: $mvpExit

--- run_mvp_test log ---
$mvpContent
"@ | Set-Content -Path $summary -Encoding UTF8

Log "Summary written: $summary"
Log "=== run_full_test END ==="
exit $mvpExit
