import type { Chapter } from "./api";
import { getChapterContent, parseQualityReport } from "./api";

export const CONTENT_STATUS_LABEL: Record<string, string> = {
  pending: "未生成",
  generating: "生成中",
  summarizing: "摘要中",
  rewriting: "重写中",
  completed: "已完成",
  failed: "失败",
  skipped: "已跳过",
};

export const MEDIA_STATUS_LABEL: Record<string, string> = {
  pending: "未生成",
  generating: "生成中",
  completed: "已完成",
  failed: "失败",
};

export const QUALITY_STATUS_LABEL: Record<string, string> = {
  pending: "未检查",
  checking: "检查中",
  completed: "已检查",
  failed: "检查失败",
};

export const CONTENT_STATUS_CLASS: Record<string, string> = {
  pending: "bg-ink-600 text-slate-300",
  generating: "bg-sky-500/20 text-sky-300",
  summarizing: "bg-amber-500/20 text-amber-300",
  rewriting: "bg-violet-500/20 text-violet-300",
  completed: "bg-emerald-500/20 text-emerald-300",
  failed: "bg-red-500/20 text-red-300",
  skipped: "bg-ink-600 text-slate-400",
};

export const MEDIA_STATUS_CLASS: Record<string, string> = {
  pending: "bg-ink-600 text-slate-300",
  generating: "bg-sky-500/20 text-sky-300",
  completed: "bg-emerald-500/20 text-emerald-300",
  failed: "bg-red-500/20 text-red-300",
};

export const QUALITY_STATUS_CLASS: Record<string, string> = {
  pending: "bg-ink-600 text-slate-300",
  checking: "bg-sky-500/20 text-sky-300",
  completed: "bg-emerald-500/20 text-emerald-300",
  failed: "bg-red-500/20 text-red-300",
};

export function qualityScoreClass(score?: number | null): string {
  if (score == null) return "bg-ink-600 text-slate-400";
  if (score >= 85) return "bg-emerald-500/20 text-emerald-300";
  if (score >= 70) return "bg-amber-500/20 text-amber-300";
  return "bg-red-500/20 text-red-300";
}

export function hasActiveChapterTasks(chapters: Chapter[]): boolean {
  return chapters.some(
    (ch) =>
      ch.status === "generating" ||
      ch.status === "summarizing" ||
      ch.status === "rewriting" ||
      ch.tts_status === "generating" ||
      ch.quality_status === "checking"
  );
}

export function chapterNeedsRewrite(ch: Chapter, threshold = 70): boolean {
  if (!getChapterContent(ch)) return false;
  if (ch.quality_score != null && ch.quality_score < threshold) return true;
  const report = parseQualityReport(ch.quality_report);
  if (report && report.passed === false) return true;
  return false;
}

export function computeQualityStats(chapters: Chapter[], threshold = 70) {
  const withContent = chapters.filter((ch) => getChapterContent(ch));
  const checked = withContent.filter((ch) => ch.quality_score != null);
  const scores = checked.map((ch) => ch.quality_score as number);
  const avg =
    scores.length > 0
      ? Math.round((scores.reduce((a, b) => a + b, 0) / scores.length) * 10) / 10
      : null;
  const passCount = scores.filter((s) => s >= threshold).length;
  const lowCount = scores.filter((s) => s < threshold).length;
  return {
    total: withContent.length,
    checked: checked.length,
    avg,
    passCount,
    lowCount,
    min: scores.length ? Math.min(...scores) : null,
    max: scores.length ? Math.max(...scores) : null,
  };
}
