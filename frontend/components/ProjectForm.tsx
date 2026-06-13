"use client";

import { useState } from "react";
import {
  CHAPTER_WORDS_OPTIONS,
  LANGUAGE_OPTIONS,
  TARGET_WORDS_OPTIONS,
} from "@/lib/constants";

export interface ProjectFormValues {
  project_name: string;
  title: string;
  target_words: number;
  chapter_words: number;
  language: string;
  generate_tts: boolean;
}

const DEFAULTS: ProjectFormValues = {
  project_name: "",
  title: "",
  target_words: 10000,
  chapter_words: 3000,
  language: "zh",
  generate_tts: true,
};

export default function ProjectForm({
  onSubmit,
  submitting,
}: {
  onSubmit: (values: ProjectFormValues) => void;
  submitting?: boolean;
}) {
  const [values, setValues] = useState<ProjectFormValues>(DEFAULTS);

  function set<K extends keyof ProjectFormValues>(key: K, value: ProjectFormValues[K]) {
    setValues((v) => ({ ...v, [key]: value }));
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!values.project_name.trim() || !values.title.trim()) {
      alert("请填写项目名称和小说标题");
      return;
    }
    onSubmit(values);
  }

  return (
    <form onSubmit={submit} className="card space-y-5 max-w-2xl">
      <div>
        <label className="label">项目名称</label>
        <input
          className="input"
          value={values.project_name}
          onChange={(e) => set("project_name", e.target.value)}
          placeholder="例如：富豪归来复仇第一季"
        />
      </div>
      <div>
        <label className="label">小说标题</label>
        <input
          className="input"
          value={values.title}
          onChange={(e) => set("title", e.target.value)}
          placeholder="例如：归来即巅峰"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="label">生成字数</label>
          <select
            className="input"
            value={values.target_words}
            onChange={(e) => set("target_words", Number(e.target.value))}
          >
            {TARGET_WORDS_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="label">每章字数</label>
          <select
            className="input"
            value={values.chapter_words}
            onChange={(e) => set("chapter_words", Number(e.target.value))}
          >
            {CHAPTER_WORDS_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <label className="label">目标语言</label>
        <select
          className="input"
          value={values.language}
          onChange={(e) => set("language", e.target.value)}
        >
          {LANGUAGE_OPTIONS.map((l) => (
            <option key={l.value} value={l.value}>
              {l.label}
            </option>
          ))}
        </select>
        <p className="text-xs text-slate-500 mt-1">
          一个项目只生成一种目标语言；如需其他语言请新建独立项目。
        </p>
      </div>

      <div>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={values.generate_tts}
            onChange={(e) => set("generate_tts", e.target.checked)}
          />
          生成正文后自动配音
        </label>
      </div>

      <button type="submit" className="btn-primary" disabled={submitting}>
        {submitting ? "创建中…" : "创建项目"}
      </button>
    </form>
  );
}
