# AI 都市小说视频工厂

**版本：** v0.3 重建版（从 Cursor transcript 恢复）  
**稳定目录：** `C:\Users\12834\Documents\ai-urban-novel-tts`  
**请勿**再将项目放在 `%TEMP%` 下。

## 一键启动

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start_app.ps1
```

停止：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\stop_app.ps1
```

## 手动启动

```powershell
cd backend
copy .env.example .env   # 填入 DEEPSEEK_API_KEY
pip install -r requirements.txt
python main.py

cd frontend
copy .env.local.example .env.local
npm install
npm run dev
```

## v0.3 能力

- 四语单项目原生生成：zh / en / es / ja
- 都市小说：bible → outline → 章节 → QC → 重写 → TTS → ZIP
- 正文统一写 `chapters.content`（非翻译工具）
- TTS 前文本清洗（`tts_text_cleaner.py`）
- 健康检查：`GET /api/health`

## 验收脚本

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_v03_language_smoke.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_v03_language_3ch.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_v03_full_work_test.ps1
```

## v0.4 产品化脚本

断点续跑指定项目：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\resume_project.ps1 -ProjectId 49 -FromChapter 1 -ToChapter 10 -DoText -DoQuality -DoRewrite -DoTts -DoExport
```

常用场景：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\resume_project.ps1 -ProjectId 49 -FromChapter 1 -ToChapter 10 -DoTts -DoExport
```

续跑会跳过已有正文、已完成评分和已存在 MP3 的章节；失败、缺评分、缺 MP3 的章节会按所选阶段重试。

恢复说明见 [REBUILD.md](./REBUILD.md)。
