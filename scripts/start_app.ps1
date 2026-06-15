# One-click launcher: env checks, backend + frontend, health wait, open browser
# Usage: powershell -ExecutionPolicy Bypass -File scripts\start_app.ps1
$ErrorActionPreference = "Stop"

function Write-Ok { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "[FAIL] $Msg" -ForegroundColor Red }
function Write-Fix { param([string]$Msg) Write-Host "[FIX] $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "[..] $Msg" -ForegroundColor Cyan }
function Write-Warn { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }

function Resolve-ProjectRoot {
    $candidates = @()
    if ($PSScriptRoot) {
        $candidates += (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    $candidates += (Get-Location).Path

    foreach ($start in ($candidates | Select-Object -Unique)) {
        $dir = $start
        for ($i = 0; $i -lt 8; $i++) {
            $hasBackend = Test-Path (Join-Path $dir "backend")
            $hasFrontend = Test-Path (Join-Path $dir "frontend")
            $hasReadme = Test-Path (Join-Path $dir "README.md")
            if ($hasBackend -and $hasFrontend -and $hasReadme) {
                return (Resolve-Path $dir).Path
            }
            $parent = Split-Path $dir -Parent
            if (-not $parent -or $parent -eq $dir) { break }
            $dir = $parent
        }
    }
    return $null
}

function Test-PortListening {
    param([int]$Port)
    try {
        $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        return [bool]$c
    } catch {
        return $false
    }
}

function Test-BackendHealth {
    param([string]$Url = "http://127.0.0.1:8000/api/health")
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -ne 200) { return $false }
        return ($r.Content -match '"status"\s*:\s*"ok"')
    } catch {
        return $false
    }
}

function Read-EnvKey {
    param([string]$EnvPath, [string]$Key)
    if (-not (Test-Path $EnvPath)) { return $null }
    foreach ($line in Get-Content $EnvPath -Encoding UTF8) {
        $t = $line.Trim()
        if ($t -match "^\s*#") { continue }
        if ($t -match "^\s*$Key\s*=\s*(.*)$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return ""
}

function Normalize-EnvEncoding {
    param([string]$EnvPath)
    if (-not (Test-Path $EnvPath)) { return }

    $bytes = [System.IO.File]::ReadAllBytes($EnvPath)
    if ($bytes.Length -lt 2) { return }

    $text = $null
    $needsRewrite = $false
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        $needsRewrite = $true
    } elseif ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        $needsRewrite = $true
    } elseif ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
        $needsRewrite = $true
    }

    if ($needsRewrite) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($EnvPath, $text, $utf8NoBom)
        Write-Warn "Normalized backend/.env encoding to UTF-8 without BOM"
    }
}

function Test-DeepSeekKeyConfigured {
    param([string]$Value)
    if (-not $Value) { return $false }
    $placeholders = @(
        "你的_deepseek_api_key",
        "your_deepseek_api_key",
        "sk-xxx",
        "changeme",
        "placeholder"
    )
    foreach ($p in $placeholders) {
        if ($Value -eq $p) { return $false }
    }
    if ($Value.Length -lt 8) { return $false }
    return $true
}

$Root = Resolve-ProjectRoot
if (-not $Root) {
    Write-Fail "Project root not found (need backend/, frontend/, README.md)"
    Write-Fix "Run this script from the project root or scripts/ directory"
    exit 1
}

Set-Location $Root
Write-Ok "Project root detected: $Root"

$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"
$EnvFile = Join-Path $Backend ".env"

# --- backend/.env ---
if (-not (Test-Path $EnvFile)) {
    Write-Fail "backend/.env not found"
    Write-Fix "Copy backend/.env.example to backend/.env and fill DEEPSEEK_API_KEY"
    exit 1
}
Write-Ok "backend/.env found"

Normalize-EnvEncoding -EnvPath $EnvFile

$apiKey = Read-EnvKey -EnvPath $EnvFile -Key "DEEPSEEK_API_KEY"
if (-not (Test-DeepSeekKeyConfigured -Value $apiKey)) {
    Write-Fail "DEEPSEEK_API_KEY not configured in backend/.env"
    Write-Fix "Edit backend/.env and set a valid DEEPSEEK_API_KEY"
    exit 1
}
Write-Ok "DEEPSEEK_API_KEY configured"

# --- dependencies (check only, do not auto-install) ---
Push-Location $Backend
$pipOk = $false
try {
    python -m pip show fastapi 2>$null | Out-Null
    $pipOk = ($LASTEXITCODE -eq 0)
} catch { $pipOk = $false }
Pop-Location

if (-not $pipOk) {
    Write-Fail "Backend dependencies missing (fastapi not found)"
    Write-Fix "cd backend; pip install -r requirements.txt"
    exit 1
}
Write-Ok "Backend dependencies found"

if (-not (Test-Path (Join-Path $Frontend "node_modules"))) {
    Write-Fail "frontend/node_modules not found"
    Write-Fix "cd frontend; npm install"
    exit 1
}
Write-Ok "Frontend dependencies found"

# --- port checks ---
$backendAlreadyRunning = $false
if (Test-PortListening -Port 8000) {
    if (Test-BackendHealth) {
        Write-Ok "Backend already running on port 8000"
        $backendAlreadyRunning = $true
    } else {
        Write-Fail "Port 8000 is in use but /api/health is not OK"
        Write-Fix "Close the process using port 8000, then retry"
        exit 1
    }
} else {
    Write-Ok "Port 8000 available"
}

$frontendPortBusy = Test-PortListening -Port 3000
if ($frontendPortBusy) {
    Write-Info "Port 3000 is already in use — frontend may already be running; check manually"
} else {
    Write-Ok "Port 3000 available"
}

# --- start backend ---
if (-not $backendAlreadyRunning) {
    Write-Info "Starting backend..."
    $backendCmd = "`$host.UI.RawUI.WindowTitle='AI Novel Backend'; Set-Location '$Backend'; python -m uvicorn main:app --host 0.0.0.0 --port 8000"
    Start-Process powershell -ArgumentList "-NoExit", "-Command", $backendCmd | Out-Null
    Write-Ok "Backend started (new window: AI Novel Backend)"

    $healthOk = $false
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-BackendHealth) {
            $healthOk = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $healthOk) {
        Write-Fail "Backend health check failed after 30s"
        Write-Fix "Check the AI Novel Backend window for errors"
        exit 1
    }
    Write-Ok "Backend health check passed"
} else {
    Write-Ok "Backend health check passed (existing instance)"
}

# --- start frontend ---
if (-not $frontendPortBusy) {
    Write-Info "Starting frontend..."
    $frontendCmd = "`$host.UI.RawUI.WindowTitle='AI Novel Frontend'; Set-Location '$Frontend'; npm run dev"
    Start-Process powershell -ArgumentList "-NoExit", "-Command", $frontendCmd | Out-Null
    Write-Ok "Frontend started (new window: AI Novel Frontend)"
    Start-Sleep -Seconds 3
} else {
    Write-Info "Skipped frontend start (port 3000 busy)"
}

Write-Host ""
Write-Ok "Backend OK"
Write-Host "Frontend URL: http://localhost:3000" -ForegroundColor Green
Write-Host "Backend docs:   http://localhost:8000/docs" -ForegroundColor Green
Write-Host "[OPEN] http://localhost:3000" -ForegroundColor Cyan
Start-Process "http://localhost:3000"
