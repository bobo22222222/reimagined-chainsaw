# 一键启动后端 + 前端（各开一个新 PowerShell 窗口）
$Root = Split-Path $PSScriptRoot -Parent
$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"

if (-not (Test-Path (Join-Path $Backend ".env"))) {
    Copy-Item (Join-Path $Backend ".env.example") (Join-Path $Backend ".env")
    Write-Host "已创建 backend/.env — 请填入 DEEPSEEK_API_KEY 后重新运行" -ForegroundColor Yellow
}

if (-not (Test-Path (Join-Path $Frontend ".env.local"))) {
    Copy-Item (Join-Path $Frontend ".env.local.example") (Join-Path $Frontend ".env.local")
}

Write-Host "启动后端 http://localhost:8000 ..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$Backend'; pip install -r requirements.txt -q; python main.py"

Start-Sleep -Seconds 3

Write-Host "启动前端 http://localhost:3000 ..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$Frontend'; if (-not (Test-Path node_modules)) { npm install }; npm run dev"

Write-Host ""
Write-Host "两个窗口已打开。等待约 10 秒后访问:" -ForegroundColor Green
Write-Host "  前端: http://localhost:3000"
Write-Host "  后端文档: http://localhost:8000/docs"
Write-Host ""
Write-Host "验收脚本（后端就绪后）:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/run_mvp_test.ps1"
