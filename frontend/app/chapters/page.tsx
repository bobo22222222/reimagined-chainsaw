"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import ChapterTable from "@/components/ChapterTable";
import ConfirmDialog from "@/components/ConfirmDialog";
import NoProject from "@/components/NoProject";
import { api, Chapter, Project } from "@/lib/api";
import { hasActiveChapterTasks, computeQualityStats } from "@/lib/chapterStatus";
import { languageLabel } from "@/lib/constants";
import { getVoiceConfig } from "@/lib/voice";
import { useProjectId } from "@/lib/useProjectId";

const FIRST3_CONFIRM_DESC = `系统将自动完成以下操作：

1. 如果还没有小说总设定，会先生成总设定。
2. 如果还没有章节目录，会继续生成章节目录。
3. 然后依次生成第 1～3 章正文。
4. 每章生成完成后会自动生成摘要，供后续章节保持上下文。
5. 如果项目开启了配音，会同时生成 MP3。
6. 此操作会消耗 DeepSeek API 额度，并可能需要一些时间。`;

function buildContentRangeConfirmDesc(start: number, end: number, autoTts: boolean) {
  const lines = [
    `系统将按顺序生成第 ${start} 章到第 ${end} 章的正文与摘要。`,
    "",
    "已生成正文的章节会自动跳过。",
  ];
  if (autoTts) {
    lines.push("项目已开启「生成正文后自动配音」，新生成章节将同时生成 MP3。");
  } else {
    lines.push("本项目未开启自动配音，仅生成正文与摘要。");
  }
  lines.push("", "此操作会消耗 DeepSeek API 额度，并可能需要一些时间。");
  return lines.join("\n");
}

function validateChapterRange(start: number, end: number): string | null {
  if (start < 1) return "开始章节必须大于等于 1。";
  if (end < start) return "结束章节必须大于等于开始章节。";
  if (end - start + 1 > 5) return "一次最多只能批量生成 5 章。";
  return null;
}

function formatRangeResult(res: {
  generated_chapters: number[];
  skipped_chapters: number[];
  failed_chapters: number[];
  message?: string;
}) {
  return (
    `${res.message || "完成"}：成功 ${res.generated_chapters.length} 章，` +
    `跳过 ${res.skipped_chapters.length} 章，失败 ${res.failed_chapters.length} 章。` +
    (res.generated_chapters.length
      ? `（成功：${res.generated_chapters.join("、")}）`
      : "") +
    (res.skipped_chapters.length
      ? `（跳过：${res.skipped_chapters.join("、")}）`
      : "") +
    (res.failed_chapters.length
      ? `（失败：${res.failed_chapters.join("、")}）`
      : "")
  );
}

function RangeInputs({
  start,
  end,
  onStart,
  onEnd,
  disabled,
}: {
  start: number;
  end: number;
  onStart: (n: number) => void;
  onEnd: (n: number) => void;
  disabled?: boolean;
}) {
  return (
    <div className="grid grid-cols-2 gap-4 max-w-md">
      <div>
        <label className="label">开始章节</label>
        <input
          type="number"
          min={1}
          className="input"
          value={start}
          onChange={(e) => onStart(Number(e.target.value))}
          disabled={disabled}
        />
      </div>
      <div>
        <label className="label">结束章节</label>
        <input
          type="number"
          min={1}
          className="input"
          value={end}
          onChange={(e) => onEnd(Number(e.target.value))}
          disabled={disabled}
        />
      </div>
    </div>
  );
}

export default function ChaptersPage() {
  const projectId = useProjectId();
  const [project, setProject] = useState<Project | null>(null);
  const [chapters, setChapters] = useState<Chapter[]>([]);
  const [loading, setLoading] = useState(true);

  const [confirmOpen, setConfirmOpen] = useState(false);
  const [generatingFirst3, setGeneratingFirst3] = useState(false);
  const [batchMsg, setBatchMsg] = useState("");
  const [batchError, setBatchError] = useState("");

  const [rangeStart, setRangeStart] = useState(1);
  const [rangeEnd, setRangeEnd] = useState(3);
  const [rangeConfirmOpen, setRangeConfirmOpen] = useState(false);
  const [generatingRange, setGeneratingRange] = useState(false);
  const [rangeMsg, setRangeMsg] = useState("");
  const [rangeError, setRangeError] = useState("");

  const [ttsStart, setTtsStart] = useState(1);
  const [ttsEnd, setTtsEnd] = useState(3);
  const [generatingTtsRange, setGeneratingTtsRange] = useState(false);
  const [ttsMsg, setTtsMsg] = useState("");
  const [ttsError, setTtsError] = useState("");

  const [qcStart, setQcStart] = useState(1);
  const [qcEnd, setQcEnd] = useState(3);
  const [checkingQuality, setCheckingQuality] = useState(false);
  const [qcMsg, setQcMsg] = useState("");
  const [qcError, setQcError] = useState("");

  const [rewriteConfirmOpen, setRewriteConfirmOpen] = useState(false);
  const [rewritingIssues, setRewritingIssues] = useState(false);
  const [rewriteMsg, setRewriteMsg] = useState("");
  const [rewriteError, setRewriteError] = useState("");
  const [rewriteThreshold, setRewriteThreshold] = useState(70);
  const [rewriteMaxRounds, setRewriteMaxRounds] = useState(1);

  const [chapterTaskActive, setChapterTaskActive] = useState(false);

  const isBusy =
    generatingFirst3 ||
    generatingRange ||
    generatingTtsRange ||
    checkingQuality ||
    rewritingIssues ||
    chapterTaskActive;

  const shouldPoll =
    generatingFirst3 ||
    generatingRange ||
    generatingTtsRange ||
    checkingQuality ||
    rewritingIssues ||
    chapterTaskActive ||
    hasActiveChapterTasks(chapters);

  const load = useCallback(async (id: number) => {
    const [p, chs] = await Promise.all([
      api.getProject(id),
      api.listChapters(id),
    ]);
    setProject(p);
    setChapters(chs);
    setLoading(false);
  }, []);

  useEffect(() => {
    if (typeof projectId === "number") load(projectId);
  }, [projectId, load]);

  const refreshChaptersOnly = useCallback(async (id: number) => {
    try {
      const chs = await api.listChapters(id);
      setChapters(chs);
    } catch {
      /* 轮询失败时静默 */
    }
  }, []);

  useEffect(() => {
    if (!shouldPoll || typeof projectId !== "number") return;
    const timer = setInterval(() => refreshChaptersOnly(projectId), 3000);
    return () => clearInterval(timer);
  }, [shouldPoll, projectId, refreshChaptersOnly]);

  async function handleGenerateFirst3() {
    if (typeof projectId !== "number") return;
    setConfirmOpen(false);
    setGeneratingFirst3(true);
    setBatchMsg("文案生成中（前 3 章），请不要重复点击……");
    setBatchError("");
    try {
      const voice = getVoiceConfig(project?.language);
      const res = await api.generateFirst3(projectId, {
        voice_key: voice.voice_key,
        rate: voice.rate,
      });
      setBatchMsg(
        `${res.message}（成功：${
          res.generated_chapters.join("、") || "无"
        }${res.failed_chapters.length ? "；失败：" + res.failed_chapters.join("、") : ""}）`
      );
      await load(projectId);
    } catch (e: any) {
      setBatchMsg("");
      setBatchError(e.message || "一键生成失败");
    } finally {
      setGeneratingFirst3(false);
    }
  }

  async function handleGenerateRange() {
    if (typeof projectId !== "number") return;
    setRangeConfirmOpen(false);
    setGeneratingRange(true);
    setRangeMsg("文案生成中（批量），请不要重复点击……");
    setRangeError("");
    try {
      const voice = getVoiceConfig();
      const res = await api.generateChapterRange(projectId, {
        start_chapter: rangeStart,
        end_chapter: rangeEnd,
        voice_key: voice.voice_key,
        rate: voice.rate,
      });
      setRangeMsg(formatRangeResult(res));
      await load(projectId);
    } catch (e: any) {
      setRangeMsg("");
      setRangeError(e.message || "批量生成失败");
    } finally {
      setGeneratingRange(false);
    }
  }

  async function handleGenerateTtsRange() {
    if (typeof projectId !== "number") return;
    const err = validateChapterRange(ttsStart, ttsEnd);
    if (err) {
      setTtsError(err);
      return;
    }
    setTtsError("");
    setGeneratingTtsRange(true);
    setTtsMsg("配音生成中（批量），请不要重复点击……");
    try {
      const voice = getVoiceConfig();
      const res = await api.generateTtsRange(projectId, {
        start_chapter: ttsStart,
        end_chapter: ttsEnd,
        voice_key: voice.voice_key,
        rate: voice.rate,
      });
      setTtsMsg(formatRangeResult(res));
      await load(projectId);
    } catch (e: any) {
      setTtsMsg("");
      setTtsError(e.message || "批量配音失败");
    } finally {
      setGeneratingTtsRange(false);
    }
  }

  async function handleQualityCheckRange() {
    if (typeof projectId !== "number") return;
    const err = validateChapterRange(qcStart, qcEnd);
    if (err) {
      setQcError(err);
      return;
    }
    setQcError("");
    setCheckingQuality(true);
    setQcMsg("质量检查中，请不要重复点击……");
    try {
      const res = await api.qualityCheckRange(projectId, {
        start_chapter: qcStart,
        end_chapter: qcEnd,
        score_threshold: rewriteThreshold,
      });
      setQcMsg(
        `${res.message}（已检查 ${res.checked_chapters.length} 章，` +
          `低于 ${rewriteThreshold} 分 ${res.low_score_count} 章` +
          (res.skipped_chapters.length
            ? `；跳过 ${res.skipped_chapters.join("、")}`
            : "") +
          (res.failed_chapters.length
            ? `；失败 ${res.failed_chapters.join("、")}`
            : "") +
          "）"
      );
      await load(projectId);
    } catch (e: any) {
      setQcMsg("");
      setQcError(e.message || "批量质量检查失败");
    } finally {
      setCheckingQuality(false);
    }
  }

  async function handleRewriteIssues() {
    if (typeof projectId !== "number") return;
    setRewriteConfirmOpen(false);
    const err = validateChapterRange(qcStart, qcEnd);
    if (err) {
      setRewriteError(err);
      return;
    }
    setRewriteError("");
    setRewritingIssues(true);
    setRewriteMsg("正在重写低质量章节，请不要重复点击……");
    try {
      const res = await api.rewriteIssues(projectId, {
        start_chapter: qcStart,
        end_chapter: qcEnd,
        score_threshold: rewriteThreshold,
        max_rounds: rewriteMaxRounds,
      });
      setRewriteMsg(
        `${res.message}：重写 ${res.rewritten_chapters.length} 章，` +
          `跳过 ${res.skipped_chapters.length} 章，失败 ${res.failed_chapters.length} 章。` +
          (res.rewritten_chapters.length
            ? `（重写：${res.rewritten_chapters.join("、")}）`
            : "")
      );
      await load(projectId);
    } catch (e: any) {
      setRewriteMsg("");
      setRewriteError(e.message || "一键重写失败");
    } finally {
      setRewritingIssues(false);
    }
  }

  const qualityStats = computeQualityStats(chapters, rewriteThreshold);
  const lowScoreCount = qualityStats.lowCount;

  if (projectId === undefined) return <div className="text-slate-400">加载中…</div>;
  if (projectId === null) return <NoProject />;

  const autoTts = Boolean(project?.generate_tts);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">章节管理</h1>
          <p className="text-sm text-slate-400">
            {project?.project_name} · 目标语言 {languageLabel(project?.language)} · 共{" "}
            {chapters.length} 章
            {!autoTts && " · 未开启自动配音"}
          </p>
        </div>
        <div className="flex gap-2">
          <Link href={`/settings?project=${projectId}`} className="btn-ghost">
            ← 设定
          </Link>
          <Link href={`/voice?project=${projectId}`} className="btn-ghost">
            配音设置
          </Link>
          <Link href={`/export?project=${projectId}`} className="btn-secondary">
            导出 →
          </Link>
        </div>
      </div>

      {shouldPoll && (
        <div className="card border-sky-500/40 text-sky-200 text-sm">
          任务进行中，页面会自动刷新状态。请不要重复点击生成按钮。
        </div>
      )}

      <section className="space-y-3">
        <h2 className="text-lg font-semibold text-brand-300">文案生成</h2>
        <p className="text-sm text-slate-400">
          生成章节正文与摘要。是否自动配音取决于创建项目时的「生成正文后自动配音」开关。
        </p>

        <div className="card flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div>
            <div className="font-semibold">一键生成前 3 章</div>
            <div className="text-sm text-slate-400">
              自动补齐总设定与目录，再生成第 1～3 章正文与摘要。
              {autoTts ? " 已开启自动配音。" : " 不会自动生成 MP3。"}
            </div>
          </div>
          <button
            className="btn-primary"
            onClick={() => !isBusy && setConfirmOpen(true)}
            disabled={isBusy}
          >
            {generatingFirst3 ? "生成中…" : "一键生成前 3 章"}
          </button>
        </div>

        <div className="card space-y-4">
          <div>
            <div className="font-semibold">批量生成正文</div>
            <p className="text-sm text-slate-400 mt-1">
              一次最多 5 章。已有正文的章节会自动跳过。
            </p>
          </div>
          <RangeInputs
            start={rangeStart}
            end={rangeEnd}
            onStart={setRangeStart}
            onEnd={setRangeEnd}
            disabled={isBusy}
          />
          <button
            className="btn-primary"
            onClick={() => {
              if (isBusy) return;
              const err = validateChapterRange(rangeStart, rangeEnd);
              if (err) {
                setRangeError(err);
                return;
              }
              setRangeError("");
              setRangeConfirmOpen(true);
            }}
            disabled={isBusy}
          >
            {generatingRange ? "生成中…" : "批量生成正文"}
          </button>
        </div>

        {generatingFirst3 && (
          <div className="card text-brand-300 text-sm">{batchMsg}</div>
        )}
        {!generatingFirst3 && batchMsg && (
          <div className="card text-brand-300 text-sm">{batchMsg}</div>
        )}
        {batchError && (
          <div className="card border-red-500/50 text-red-300 text-sm">{batchError}</div>
        )}
        {generatingRange && (
          <div className="card text-brand-300 text-sm">{rangeMsg}</div>
        )}
        {!generatingRange && rangeMsg && (
          <div className="card text-brand-300 text-sm">{rangeMsg}</div>
        )}
        {rangeError && (
          <div className="card border-red-500/50 text-red-300 text-sm">{rangeError}</div>
        )}
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold text-brand-300">配音生成</h2>
        <p className="text-sm text-slate-400">
          独立于文案生成。仅对已生成正文的章节生成 MP3；音色见「配音设置」。
        </p>
        <div className="card space-y-4">
          <div className="font-semibold">批量生成 MP3</div>
          <RangeInputs
            start={ttsStart}
            end={ttsEnd}
            onStart={setTtsStart}
            onEnd={setTtsEnd}
            disabled={isBusy}
          />
          <button
            className="btn-secondary"
            onClick={handleGenerateTtsRange}
            disabled={isBusy}
          >
            {generatingTtsRange ? "配音中…" : "批量生成 MP3"}
          </button>
          {generatingTtsRange && (
            <div className="text-sm text-brand-300">{ttsMsg}</div>
          )}
          {!generatingTtsRange && ttsMsg && (
            <div className="text-sm text-brand-300">{ttsMsg}</div>
          )}
          {ttsError && <div className="text-sm text-red-300">{ttsError}</div>}
        </div>
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold text-brand-300">质量检查与重写</h2>
        <p className="text-sm text-slate-400">
          对已生成正文进行规则 + AI 质量评估（满分 100，70 分及以上为达标）。
          低于 70 分或存在严重问题的章节可一键重写，重写后会更新正文与摘要，并重置配音状态。
        </p>
        <div className="card space-y-4">
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
            <div>
              <span className="text-slate-500">已检查章节：</span>
              {qualityStats.checked} / {qualityStats.total}
            </div>
            <div>
              <span className="text-slate-500">平均分：</span>
              {qualityStats.avg != null ? qualityStats.avg : "—"}
            </div>
            <div>
              <span className="text-slate-500">达标章节：</span>
              {qualityStats.passCount}
            </div>
            <div>
              <span className="text-slate-500">低分章节：</span>
              <span className={lowScoreCount > 0 ? "text-red-300" : ""}>
                {qualityStats.lowCount}
              </span>
              <span className="text-slate-500 text-xs">（&lt; {rewriteThreshold} 分）</span>
            </div>
            <div>
              <span className="text-slate-500">最低分：</span>
              {qualityStats.min != null ? qualityStats.min : "—"}
            </div>
            <div>
              <span className="text-slate-500">最高分：</span>
              {qualityStats.max != null ? qualityStats.max : "—"}
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <div className="font-semibold">批量质量检查</div>
            {lowScoreCount > 0 && (
              <span className="badge bg-red-500/20 text-red-300">
                {lowScoreCount} 章待改进
              </span>
            )}
          </div>
          <RangeInputs
            start={qcStart}
            end={qcEnd}
            onStart={setQcStart}
            onEnd={setQcEnd}
            disabled={isBusy}
          />
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 max-w-2xl">
            <div>
              <label className="label">重写低于多少分的章节</label>
              <select
                className="input"
                value={rewriteThreshold}
                onChange={(e) => setRewriteThreshold(Number(e.target.value))}
                disabled={isBusy}
              >
                <option value={60}>60 分</option>
                <option value={65}>65 分</option>
                <option value={70}>70 分</option>
                <option value={75}>75 分</option>
              </select>
            </div>
            <div>
              <label className="label">最大重写轮次</label>
              <select
                className="input"
                value={rewriteMaxRounds}
                onChange={(e) => setRewriteMaxRounds(Number(e.target.value))}
                disabled={isBusy}
              >
                <option value={1}>1 次</option>
                <option value={2}>2 次</option>
              </select>
              <p className="text-xs text-slate-500 mt-1">
                极低分章节可能一次重写后仍不达标，可设为 2 次对同一批章节再重写。
              </p>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              className="btn-secondary"
              onClick={handleQualityCheckRange}
              disabled={isBusy}
            >
              {checkingQuality ? "检查中…" : "批量质量检查"}
            </button>
            <button
              className="btn-primary"
              onClick={() => {
                if (isBusy) return;
                const err = validateChapterRange(qcStart, qcEnd);
                if (err) {
                  setRewriteError(err);
                  return;
                }
                setRewriteError("");
                setRewriteConfirmOpen(true);
              }}
              disabled={isBusy}
            >
              {rewritingIssues ? "重写中…" : "一键重写低分章节"}
            </button>
          </div>
          {checkingQuality && (
            <div className="text-sm text-brand-300">{qcMsg}</div>
          )}
          {!checkingQuality && qcMsg && (
            <div className="text-sm text-brand-300">{qcMsg}</div>
          )}
          {qcError && <div className="text-sm text-red-300">{qcError}</div>}
          {rewritingIssues && (
            <div className="text-sm text-brand-300">{rewriteMsg}</div>
          )}
          {!rewritingIssues && rewriteMsg && (
            <div className="text-sm text-brand-300">{rewriteMsg}</div>
          )}
          {rewriteError && <div className="text-sm text-red-300">{rewriteError}</div>}
        </div>
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold">章节列表</h2>
        {loading ? (
          <div className="text-slate-400">加载中…</div>
        ) : chapters.length === 0 ? (
          <div className="card text-slate-400">
            还没有章节。请先到{" "}
            <Link href={`/settings?project=${projectId}`} className="text-brand-400 underline">
              都市快捷设定
            </Link>{" "}
            生成总设定和章节目录，或使用上方「文案生成」功能。
          </div>
        ) : (
          <ChapterTable
            chapters={chapters}
            projectLanguage={project?.language}
            rewriteThreshold={rewriteThreshold}
            onReload={() => load(projectId)}
            onTaskStart={() => setChapterTaskActive(true)}
            onTaskEnd={() => setChapterTaskActive(false)}
          />
        )}
      </section>

      <ConfirmDialog
        open={confirmOpen}
        title="确认生成前 3 章？"
        description={FIRST3_CONFIRM_DESC}
        confirmText="确认生成"
        cancelText="取消"
        loading={generatingFirst3}
        onConfirm={handleGenerateFirst3}
        onCancel={() => !generatingFirst3 && setConfirmOpen(false)}
      />

      <ConfirmDialog
        open={rangeConfirmOpen}
        title="确认批量生成正文？"
        description={buildContentRangeConfirmDesc(rangeStart, rangeEnd, autoTts)}
        confirmText="确认生成"
        cancelText="取消"
        loading={generatingRange}
        onConfirm={handleGenerateRange}
        onCancel={() => !generatingRange && setRangeConfirmOpen(false)}
      />

      <ConfirmDialog
        open={rewriteConfirmOpen}
        title="确认一键重写低分章节？"
        description={`系统将检查第 ${qcStart}～${qcEnd} 章的质量报告，对低于 ${rewriteThreshold} 分或未达标的章节进行 AI 重写（最多 ${rewriteMaxRounds} 轮）。

1. 仅重写低质量章节，达标章节自动跳过。
2. 一次最多处理 5 章。
3. 重写后会更新正文与摘要，并重置配音状态（需重新生成 MP3）。
4. 重写完成，请重新进行质量检查。
5. 此操作会消耗 DeepSeek API 额度，并可能需要一些时间。`}
        confirmText="确认重写"
        cancelText="取消"
        loading={rewritingIssues}
        onConfirm={handleRewriteIssues}
        onCancel={() => !rewritingIssues && setRewriteConfirmOpen(false)}
      />
    </div>
  );
}
