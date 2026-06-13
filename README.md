# AI 都市小说视频工厂（重建中）

**状态：** 从备份丢失后重建  
**稳定目录：** `C:\Users\12834\Documents\ai-urban-novel-tts`  
**请勿**再将项目放在 `%TEMP%` 下。

## 当前进度

- [x] 稳定目录创建
- [x] 抢救 `scripts/start_app.ps1`、`scripts/stop_app.ps1`
- [ ] 恢复 v0.3 后端 + 前端
- [ ] 恢复 v0.3 测试脚本与报告
- [ ] 恢复 v0.4 TTS 清洗与一键启动

详细步骤见 [REBUILD.md](./REBUILD.md)。

## 目标能力（v0.3）

- 四语单项目原生生成：zh / en / es / ja
- 都市小说：bible → outline → 章节 → QC → 重写 → TTS → ZIP
- 非翻译工具，正文统一写 `chapters.content`
