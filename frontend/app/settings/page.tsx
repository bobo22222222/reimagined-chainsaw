"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import NoProject from "@/components/NoProject";
import TemplateButtons from "@/components/TemplateButtons";
import UrbanPresetForm, { UrbanValues } from "@/components/UrbanPresetForm";
import { formatTargetWords, languageLabel } from "@/lib/constants";
import { api, Project } from "@/lib/api";
import { useProjectId } from "@/lib/useProjectId";

const URBAN_KEYS = [
  "genre",
  "protagonist_type",
  "opening_hook",
  "main_conflict",
  "antagonist_type",
  "plot_style",
  "emotion_direction",
  "tone",
  "ending_type",
  "target_audience",
  "custom_setting",
];

export default function SettingsPage() {
  const projectId = useProjectId();
  const [project, setProject] = useState<Project | null>(null);
  const [values, setValues] = useState<UrbanValues>({});
  const [busy, setBusy] = useState<string>("");
  const [msg, setMsg] = useState("");

  async function load(id: number) {
    const p = await api.getProject(id);
    setProject(p);
    const v: UrbanValues = {};
    URBAN_KEYS.forEach((k) => {
      v[k] = (p as any)[k] || "";
    });
    setValues(v);
  }

  useEffect(() => {
    if (typeof projectId === "number") load(projectId);
  }, [projectId]);

  if (projectId === undefined) return <div className="text-slate-400">加载中…</div>;
  if (projectId === null) return <NoProject />;

  function setField(key: string, value: string) {
    setValues((v) => ({ ...v, [key]: value }));
  }

  async function applyTemplate(tplValues: Record<string, string>) {
    setValues((v) => ({ ...v, ...tplValues }));
    setMsg("已应用模板，记得点击「保存设定」。");
  }

  async function save() {
    if (!project) return;
    setBusy("save");
    setMsg("");
    try {
      await api.saveUrbanSettings(project.id, values);
      setMsg("设定已保存。");
      await load(project.id);
    } catch (e: any) {
      setMsg(e.message);
    } finally {
      setBusy("");
    }
  }

  async function genBible() {
    if (!project) return;
    setBusy("bible");
    setMsg("正在生成总设定，请稍候…");
    try {
      await api.saveUrbanSettings(project.id, values);
      await api.generateBible(project.id);
      await load(project.id);
      setMsg("小说总设定已生成。");
    } catch (e: any) {
      setMsg(e.message);
    } finally {
      setBusy("");
    }
  }

  async function genOutline() {
    if (!project) return;
    setBusy("outline");
    setMsg("正在生成章节目录并创建章节，请稍候…");
    try {
      await api.generateOutline(project.id);
      await load(project.id);
      setMsg("章节目录已生成，章节已创建。可前往「章节管理」逐章生成正文。");
    } catch (e: any) {
      setMsg(e.message);
    } finally {
      setBusy("");
    }
  }

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">
            {project?.project_name}{" "}
            <span className="text-slate-500 text-base">/ {project?.title}</span>
          </h1>
          <p className="text-sm text-slate-400">
            生成字数 {formatTargetWords(project?.target_words)} · 每章{" "}
            {project?.chapter_words} 字 · 目标语言 {languageLabel(project?.language)}
          </p>
        </div>
        <Link href={`/chapters?project=${projectId}`} className="btn-secondary">
          章节管理 →
        </Link>
      </div>

      <TemplateButtons onApply={applyTemplate} />
      <UrbanPresetForm values={values} onChange={setField} />

      {msg && <div className="card text-brand-300">{msg}</div>}

      <div className="flex flex-wrap gap-3">
        <button className="btn-secondary" onClick={save} disabled={!!busy}>
          {busy === "save" ? "保存中…" : "保存设定"}
        </button>
        <button className="btn-primary" onClick={genBible} disabled={!!busy}>
          {busy === "bible" ? "生成中…" : "① 生成小说总设定"}
        </button>
        <button
          className="btn-primary"
          onClick={genOutline}
          disabled={!!busy || !project?.story_bible}
        >
          {busy === "outline" ? "生成中…" : "② 生成章节目录"}
        </button>
      </div>

      {project?.story_bible && (
        <details className="card" open>
          <summary className="cursor-pointer font-semibold mb-2">
            小说总设定
          </summary>
          <pre className="whitespace-pre-wrap text-sm text-slate-300 mt-3">
            {project.story_bible}
          </pre>
        </details>
      )}
      {project?.outline && (
        <details className="card">
          <summary className="cursor-pointer font-semibold mb-2">章节目录</summary>
          <pre className="whitespace-pre-wrap text-sm text-slate-300 mt-3">
            {project.outline}
          </pre>
        </details>
      )}
    </div>
  );
}
