"use client";

import { useState } from "react";
import { api, Chapter, downloadUrls, getChapterContent, parseQualityReport } from "@/lib/api";
import {
  CONTENT_STATUS_CLASS,
  CONTENT_STATUS_LABEL,
  MEDIA_STATUS_CLASS,
  MEDIA_STATUS_LABEL,
  QUALITY_STATUS_CLASS,
  QUALITY_STATUS_LABEL,
  chapterNeedsRewrite,
  qualityScoreClass,
} from "@/lib/chapterStatus";
import { getVoiceConfig } from "@/lib/voice";

const NO_CONTENT_MSG = "请先生成章节正文";

function ContentStatusBadge({ status }: { status: string }) {
  return (
    <span
      className={`badge ${CONTENT_STATUS_CLASS[status] || CONTENT_STATUS_CLASS.pending}`}
    >
      {CONTENT_STATUS_LABEL[status] || status}
    </span>
  );
}

function MediaStatusBadge({ status }: { status: string }) {
  return (
    <span
      className={`badge ${MEDIA_STATUS_CLASS[status] || MEDIA_STATUS_CLASS.pending}`}
    >
      {MEDIA_STATUS_LABEL[status] || status}
    </span>
  );
}

function QualityBadge({ chapter }: { chapter: Chapter }) {
  const qStatus = chapter.quality_status || "pending";
  if (qStatus === "checking") {
    return (
      <span className={`badge ${QUALITY_STATUS_CLASS.checking}`}>
        {QUALITY_STATUS_LABEL.checking}
      </span>
    );
  }
  if (chapter.quality_score != null) {
    return (
      <span className={`badge ${qualityScoreClass(chapter.quality_score)}`}>
        {chapter.quality_score} 分
      </span>
    );
  }
  return (
    <span className={`badge ${QUALITY_STATUS_CLASS[qStatus] || QUALITY_STATUS_CLASS.pending}`}>
      {QUALITY_STATUS_LABEL[qStatus] || QUALITY_STATUS_LABEL.pending}
    </span>
  );
}

function isChapterBusy(ch: Chapter): boolean {
  return (
    ch.status === "generating" ||
    ch.status === "summarizing" ||
    ch.status === "rewriting" ||
    ch.tts_status === "generating" ||
    ch.quality_status === "checking"
  );
}

export default function ChapterTable({
  chapters,
  projectLanguage = "zh",
  rewriteThreshold = 70,
  onReload,
  onTaskStart,
  onTaskEnd,
}: {
  chapters: Chapter[];
  projectLanguage?: string;
  rewriteThreshold?: number;
  onReload: () => void;
  onTaskStart?: () => void;
  onTaskEnd?: () => void;
}) {
  const [busyId, setBusyId] = useState<number | null>(null);
  const [busyAction, setBusyAction] = useState<string>("");
  const [viewing, setViewing] = useState<Chapter | null>(null);
  const [editText, setEditText] = useState("");
  const [error, setError] = useState("");
  const [errorDetail, setErrorDetail] = useState<Chapter | null>(null);

  async function run(id: number, action: string, fn: () => Promise<any>) {
    setBusyId(id);
    setBusyAction(action);
    setError("");
    onTaskStart?.();
    try {
      await fn();
      onReload();
    } catch (e: any) {
      setError(`第 ${id} 章 ${action} 失败：${e.message}`);
      onReload();
    } finally {
      setBusyId(null);
      setBusyAction("");
      onTaskEnd?.();
    }
  }

  async function openView(ch: Chapter) {
    const fresh = await api.getChapter(ch.id);
    setViewing(fresh);
    setEditText(getChapterContent(fresh));
  }

  async function saveEdit() {
    if (!viewing) return;
    await api.updateChapter(viewing.id, { content: editText });
    setViewing(null);
    onReload();
  }

  function busy(id: number, action: string) {
    return busyId === id && busyAction === action;
  }

  function hasContent(ch: Chapter) {
    return Boolean(getChapterContent(ch));
  }

  function requireContent(ch: Chapter): boolean {
    if (hasContent(ch)) return true;
    setError(NO_CONTENT_MSG);
    return false;
  }

  const viewingReport = viewing ? parseQualityReport(viewing.quality_report) : null;

  return (
    <div>
      {error && <div className="card border-red-500/50 text-red-300 mb-4">{error}</div>}

      <div className="card p-0 overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-slate-400 border-b border-ink-600">
            <tr>
              <th className="text-left px-3 py-3">#</th>
              <th className="text-left px-3 py-3">标题 / 大纲</th>
              <th className="text-left px-3 py-3">字数</th>
              <th className="text-left px-3 py-3">文案</th>
              <th className="text-left px-3 py-3">配音</th>
              <th className="text-left px-3 py-3">质量</th>
              <th className="text-right px-3 py-3">操作</th>
            </tr>
          </thead>
          <tbody>
            {chapters.map((ch) => (
              <tr key={ch.id} className="border-b border-ink-700 align-top">
                <td className="px-3 py-3 font-medium">{ch.chapter_number}</td>
                <td className="px-3 py-3 max-w-md">
                  <div className="font-medium">{ch.title}</div>
                  <div className="text-xs text-slate-500 line-clamp-2 whitespace-pre-wrap">
                    {ch.outline}
                  </div>
                </td>
                <td className="px-3 py-3">{ch.word_count || 0}</td>
                <td className="px-3 py-3">
                  <ContentStatusBadge status={ch.status} />
                </td>
                <td className="px-3 py-3">
                  <MediaStatusBadge status={ch.tts_status} />
                </td>
                <td className="px-3 py-3">
                  <QualityBadge chapter={ch} />
                </td>
                <td className="px-3 py-3">
                  <div className="flex flex-wrap gap-1 justify-end">
                    {ch.status !== "completed" ? (
                      <button
                        className="btn-primary btn-sm"
                        disabled={busyId === ch.id || isChapterBusy(ch)}
                        onClick={() =>
                          run(ch.id, "生成正文", () => api.generateChapter(ch.id))
                        }
                      >
                        {busy(ch.id, "生成正文") ? "生成中…" : "生成正文"}
                      </button>
                    ) : (
                      <button
                        className="btn-ghost btn-sm"
                        disabled={busyId === ch.id || isChapterBusy(ch)}
                        onClick={() =>
                          run(ch.id, "重新生成", () => api.regenerateChapter(ch.id))
                        }
                      >
                        {busy(ch.id, "重新生成") ? "生成中…" : "重新生成"}
                      </button>
                    )}
                    <button
                      className="btn-secondary btn-sm"
                      disabled={busyId === ch.id || isChapterBusy(ch) || !hasContent(ch)}
                      onClick={() =>
                        run(ch.id, "质量检查", () => api.checkChapterQuality(ch.id))
                      }
                    >
                      {busy(ch.id, "质量检查") ? "检查中…" : "质量检查"}
                    </button>
                    {chapterNeedsRewrite(ch, rewriteThreshold) && (
                      <button
                        className="btn-primary btn-sm"
                        disabled={busyId === ch.id || isChapterBusy(ch)}
                        onClick={() =>
                          run(ch.id, "一键重写", () => api.rewriteChapter(ch.id))
                        }
                      >
                        {busy(ch.id, "一键重写") ? "重写中…" : "一键重写"}
                      </button>
                    )}
                    {ch.last_error && (
                      <button
                        className="btn-ghost btn-sm text-red-300"
                        onClick={() => setErrorDetail(ch)}
                      >
                        错误详情
                      </button>
                    )}
                    <button
                      className="btn-secondary btn-sm"
                      onClick={() => openView(ch)}
                      disabled={!hasContent(ch)}
                    >
                      查看
                    </button>
                    <button
                      className="btn-ghost btn-sm"
                      disabled={busyId === ch.id || isChapterBusy(ch)}
                      onClick={() => {
                        if (!requireContent(ch)) return;
                        const cfg = getVoiceConfig(projectLanguage);
                        run(ch.id, "生成配音", () =>
                          api.generateTTS(ch.id, cfg.voice_key, cfg.rate)
                        );
                      }}
                    >
                      {busy(ch.id, "生成配音") ? "配音中…" : "生成配音"}
                    </button>
                    <a
                      className="btn-ghost btn-sm"
                      href={downloadUrls.chapterTxt(ch.id)}
                      target="_blank"
                      rel="noreferrer"
                    >
                      TXT
                    </a>
                    {ch.tts_status === "completed" && (
                      <a
                        className="btn-ghost btn-sm"
                        href={downloadUrls.chapterMp3(ch.id)}
                        target="_blank"
                        rel="noreferrer"
                      >
                        MP3
                      </a>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {viewing && (
        <div
          className="fixed inset-0 bg-black/60 flex items-center justify-center p-6 z-50"
          onClick={() => setViewing(null)}
        >
          <div
            className="bg-ink-800 border border-ink-600 rounded-xl w-full max-w-3xl max-h-[85vh] flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b border-ink-600">
              <h3 className="font-semibold">
                第{viewing.chapter_number}章 {viewing.title}
                {viewing.quality_score != null && (
                  <span className={`ml-2 badge ${qualityScoreClass(viewing.quality_score)}`}>
                    {viewing.quality_score} 分
                  </span>
                )}
              </h3>
              <button className="btn-ghost btn-sm" onClick={() => setViewing(null)}>
                关闭
              </button>
            </div>

            {viewingReport && (
              <div className="mx-4 mt-4 p-3 rounded-lg bg-ink-900 border border-ink-600 text-sm space-y-2 max-h-40 overflow-y-auto">
                {viewingReport.length && (
                  <div className="text-slate-300 flex flex-wrap gap-x-4 gap-y-1">
                    <span>
                      章节长度：{viewingReport.length.value} {viewingReport.length.unit}
                    </span>
                    <span>
                      长度判断：
                      <span
                        className={
                          viewingReport.length.judgment === "正常"
                            ? "text-emerald-300"
                            : viewingReport.length.judgment === "明显过长"
                              ? "text-red-300"
                              : "text-amber-300"
                        }
                      >
                        {viewingReport.length.judgment}
                      </span>
                    </span>
                  </div>
                )}
                <div className="text-slate-300">{viewingReport.summary}</div>
                {viewingReport.issues?.length > 0 && (
                  <ul className="list-disc pl-5 text-slate-400 space-y-1">
                    {viewingReport.issues.map((issue, i) => (
                      <li key={i}>
                        <span
                          className={
                            issue.severity === "error"
                              ? "text-red-300"
                              : issue.severity === "warning"
                                ? "text-amber-300"
                                : "text-slate-400"
                          }
                        >
                          {issue.message}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
                {viewingReport.suggestions?.length > 0 && (
                  <div className="text-brand-300">
                    建议：{viewingReport.suggestions.join("；")}
                  </div>
                )}
              </div>
            )}

            <textarea
              className="input flex-1 m-4 min-h-[40vh] font-mono text-sm"
              value={editText}
              onChange={(e) => setEditText(e.target.value)}
            />
            <div className="flex justify-end gap-2 p-4 border-t border-ink-600">
              <button className="btn-ghost" onClick={() => setViewing(null)}>
                取消
              </button>
              <button className="btn-primary" onClick={saveEdit}>
                保存修改
              </button>
            </div>
          </div>
        </div>
      )}

      {errorDetail && (
        <div
          className="fixed inset-0 bg-black/60 flex items-center justify-center p-6 z-50"
          onClick={() => setErrorDetail(null)}
        >
          <div
            className="bg-ink-800 border border-red-500/40 rounded-xl w-full max-w-lg p-5 space-y-3"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="font-semibold text-red-300">
              第{errorDetail.chapter_number}章 错误详情
            </h3>
            {errorDetail.last_error_at && (
              <p className="text-xs text-slate-500">时间：{errorDetail.last_error_at}</p>
            )}
            <pre className="text-sm text-slate-200 whitespace-pre-wrap font-sans">
              {errorDetail.last_error}
            </pre>
            <div className="flex justify-end">
              <button className="btn-ghost btn-sm" onClick={() => setErrorDetail(null)}>
                关闭
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
