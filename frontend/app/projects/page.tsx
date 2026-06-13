"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { formatTargetWords, languageLabel } from "@/lib/constants";
import { api, Project } from "@/lib/api";
import { setCurrentProjectId } from "@/lib/project";

const STATUS_LABEL: Record<string, string> = {
  created: "已创建",
  bible_generating: "生成总设定中",
  bible_completed: "已出总设定",
  bible_done: "已出总设定",
  outline_generating: "生成目录中",
  outline_completed: "已出目录",
  outline_done: "已出目录",
  generating_chapters: "生成章节中",
  completed: "已完成",
  failed: "失败",
};

export default function ProjectsPage() {
  const router = useRouter();
  const [projects, setProjects] = useState<Project[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  async function load() {
    setLoading(true);
    setError("");
    try {
      setProjects(await api.listProjects());
    } catch (e: any) {
      setError(e.message || "加载失败，请确认后端已启动（http://localhost:8000）");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  function open(p: Project) {
    setCurrentProjectId(p.id);
    router.push(`/settings?project=${p.id}`);
  }

  async function remove(id: number) {
    if (!confirm("确定删除该项目及其所有章节？")) return;
    await api.deleteProject(id);
    load();
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">项目列表</h1>
        <Link href="/create" className="btn-primary">
          + 创建项目
        </Link>
      </div>

      {error && (
        <div className="card border-red-500/50 text-red-300 mb-4">{error}</div>
      )}
      {loading ? (
        <div className="text-slate-400">加载中…</div>
      ) : projects.length === 0 ? (
        <div className="card text-slate-400">
          还没有项目，点击右上角「创建项目」开始。
        </div>
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="w-full text-sm">
            <thead className="text-slate-400 border-b border-ink-600">
              <tr>
                <th className="text-left px-4 py-3">项目名称</th>
                <th className="text-left px-4 py-3">小说标题</th>
                <th className="text-left px-4 py-3">题材</th>
                <th className="text-left px-4 py-3">生成字数</th>
                <th className="text-left px-4 py-3">语言</th>
                <th className="text-left px-4 py-3">章节数</th>
                <th className="text-left px-4 py-3">状态</th>
                <th className="text-left px-4 py-3">创建时间</th>
                <th className="text-right px-4 py-3">操作</th>
              </tr>
            </thead>
            <tbody>
              {projects.map((p) => (
                <tr key={p.id} className="border-b border-ink-700 hover:bg-ink-700/50">
                  <td className="px-4 py-3 font-medium">{p.project_name}</td>
                  <td className="px-4 py-3">{p.title}</td>
                  <td className="px-4 py-3 text-slate-400">{p.genre || "—"}</td>
                  <td className="px-4 py-3">{formatTargetWords(p.target_words)}</td>
                  <td className="px-4 py-3">{languageLabel(p.language)}</td>
                  <td className="px-4 py-3">{p.chapter_count ?? 0}</td>
                  <td className="px-4 py-3">
                    <span className="badge bg-ink-600 text-slate-300">
                      {STATUS_LABEL[p.status] || p.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-slate-400">
                    {p.created_at?.replace("T", " ")}
                  </td>
                  <td className="px-4 py-3 text-right whitespace-nowrap">
                    <button className="btn-secondary btn-sm mr-2" onClick={() => open(p)}>
                      进入
                    </button>
                    <button className="btn-danger btn-sm" onClick={() => remove(p.id)}>
                      删除
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
