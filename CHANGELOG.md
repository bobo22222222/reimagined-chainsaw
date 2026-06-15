# CHANGELOG

## v0.4-product-polish - 产品化补强（进行中）

- 一键启动脚本增强：规范化 `backend/.env` 编码，使用无 reload 后端启动，并增强停止脚本进程识别。
- TTS 清洗复测自包含化：新增 `tts_cleaner_selftest.py`，验证清洗不修改数据库正文且 MP3 可生成。
- 新增 `scripts/resume_project.ps1`：支持按章节范围续跑正文、质量检查、低分重写、TTS 与 ZIP 导出。

## v0.3-rebuild - 从 transcript 恢复（2026-06-13）

### 恢复方式

- 源：Cursor agent transcript JSONL
- 工具：`tools/recover_from_transcript.py`
- 目标目录：`C:\Users\12834\Documents\ai-urban-novel-tts`

### 已恢复

- 后端 13 模块 + `tts_text_cleaner.py`
- 前端 Next.js 全页面与组件
- 脚本：`lib_api.ps1`、v0.3 冒烟/三章/完整作品测试、v0.4 TTS 清洗测试、`start_app.ps1`、`stop_app.ps1`
- `GET /api/health` 可用

### 待用户完成

- 在 `backend/.env` 填入真实 `DEEPSEEK_API_KEY`
- 运行 `run_v03_language_smoke.ps1` 验收
- `git push` 到远程私有仓库

## v0.3 - 单语言原生生成版（历史）

四语 zh/en/es/ja 单项目原生生成，正文统一 `chapters.content`。

## v0.2.1 - 中文长篇稳定版（历史）

长篇生成、QC、重写、TTS、ZIP 导出。
