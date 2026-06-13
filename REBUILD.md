# ai-urban-novel-tts 重建指南

> 原 Temp 项目已丢失。本目录为**稳定重建根目录**，不要再放在 `%TEMP%` 下。

## 已从旧目录抢救

- `scripts/start_app.ps1`
- `scripts/stop_app.ps1`

## 重建顺序（建议严格按阶段）

### 阶段 0：稳定环境（当前）

```powershell
cd C:\Users\12834\Documents\ai-urban-novel-tts
git init
git add .gitignore REBUILD.md scripts/
git commit -m "chore: init rebuild workspace"
```

**原则：**

- 项目固定在 `Documents` 或 `C:\Projects`
- 每完成一个阶段就 `git commit`
- 重要节点打 tag：`v0.3`、`v0.4`
- `mvp_test_output/*.txt` 报告可提交；`*.zip` / `*.log` / `*.mp3` 不提交

---

### 阶段 1：恢复 v0.3 稳定版（优先）

目标：四语单语言原生生成，完整主链路可用。

**后端（FastAPI + SQLite）：**

- `backend/main.py` — API 入口
- `backend/database.py` — schema + 迁移
- `backend/models.py`
- `backend/language_profiles.py` — zh/en/es/ja
- `backend/content_utils.py`
- `backend/prompts.py`
- `backend/validators.py`
- `backend/quality_service.py`
- `backend/tts_service.py` — edge-tts
- `backend/exporter.py`
- `backend/deepseek_client.py`
- `backend/requirements.txt`
- `backend/.env.example`

**前端（Next.js）：**

- 创建项目、都市模板、生成 bible/outline/章节
- 质量检查、重写、TTS、ZIP 导出
- 语言选择与章节表

**验收脚本：**

- `scripts/lib_api.ps1`
- `scripts/run_v03_language_smoke.ps1`
- `scripts/run_v03_language_3ch.ps1`
- `scripts/run_v03_full_work_test.ps1`

**通过后：**

```powershell
git tag v0.3
```

---

### 阶段 2：恢复 v0.4（在 v0.3 之上）

1. `backend/tts_text_cleaner.py` + 接入 TTS（不改数据库正文）
2. `scripts/run_v04_tts_cleaner_test.ps1`
3. `scripts/start_app.ps1` + `GET /api/health`（已有脚本，需补后端）
4. `scripts/stop_app.ps1`

**通过后：**

```powershell
git checkout -b v0.4-product-polish
git tag v0.4  # 可选
```

---

### 阶段 3：日常开发纪律

| 动作 | 命令/习惯 |
|------|-----------|
| 启动 | `powershell -File scripts\start_app.ps1` |
| 停止 | `powershell -File scripts\stop_app.ps1` |
| 备份 | 定期 `robocopy` 到 `Documents\ai-urban-novel-tts-backup-日期` |
| 远程 | 建议创建 GitHub 私有仓并 `git push` |

---

## 本地环境要求

- Python 3.10+
- Node.js 18+
- `backend/.env` 中配置 `DEEPSEEK_API_KEY`
- `cd frontend && npm install`
- `cd backend && pip install -r requirements.txt`

---

## 下一步

对 Cursor 说：**「开始在 Documents\ai-urban-novel-tts 重建 v0.3 阶段 1」**

将按上述文件列表逐模块恢复，每步跑冒烟测试，避免再次放在 Temp 目录。
