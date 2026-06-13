# Stop backend (python main.py) and frontend (next dev) for this project only
# Usage: powershell -ExecutionPolicy Bypass -File scripts\stop_app.ps1
$ErrorActionPreference = "Continue"

function Resolve-ProjectRoot {
    if ($PSScriptRoot) {
        $fromScript = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        if ((Test-Path (Join-Path $fromScript "backend")) -and (Test-Path (Join-Path $fromScript "frontend"))) {
            return $fromScript
        }
    }
    $dir = (Get-Location).Path
    for ($i = 0; $i -lt 8; $i++) {
        if ((Test-Path (Join-Path $dir "backend")) -and (Test-Path (Join-Path $dir "frontend"))) {
            return (Resolve-Path $dir).Path
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Write-Ok { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Info { param([string]$Msg) Write-Host "[..] $Msg" -ForegroundColor Cyan }
function Write-Warn { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }

$Root = Resolve-ProjectRoot
if (-not $Root) {
    Write-Warn "Project root not found — will still try to stop python main.py / next dev"
} else {
    Write-Info "Project root: $Root"
}

$stopped = @()

# Backend: python main.py
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    $cmd = $_.CommandLine
    if (-not $cmd) { return }
    if ($cmd -match "main\.py") {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $stopped += "backend pid=$($_.ProcessId)"
    }
}

# Also stop uvicorn reload worker children still holding port 8000
foreach ($port in @(8000, 3000)) {
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $owningPid = $_.OwningProcess
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$owningPid" -ErrorAction SilentlyContinue
        if (-not $proc) { return }
        $name = $proc.Name
        $cmd = $proc.CommandLine
        if ($name -in @("python.exe", "node.exe") -and $cmd -match "main\.py|next") {
            Stop-Process -Id $owningPid -Force -ErrorAction SilentlyContinue
            $stopped += "port-$port pid=$owningPid"
        }
    }
}

# Frontend: next dev (only when project root known)
if ($Root) {
    $frontendNorm = (Join-Path $Root "frontend").Replace("\", "/").ToLower()
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $cmd = $_.CommandLine
        if (-not $cmd) { return }
        $cmdNorm = $cmd.Replace("\", "/").ToLower()
        if (($cmdNorm -like "*next*dev*" -or $cmdNorm -like "*next-server*") -and $cmdNorm -like "*$frontendNorm*") {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            $stopped += "frontend pid=$($_.ProcessId)"
        }
    }
}

if ($stopped.Count -gt 0) {
    foreach ($s in $stopped) { Write-Ok "Stopped $s" }
} else {
    Write-Info "No matching project processes found on ports 8000/3000"
    Write-Host "Manual steps:"
    Write-Host "  1. Close PowerShell windows: AI Novel Backend / AI Novel Frontend"
    Write-Host "  2. Or: Get-NetTCPConnection -LocalPort 8000,3000 | Select OwningProcess"
    Write-Host "  3. End only processes you recognize as this app's python/node"
}
