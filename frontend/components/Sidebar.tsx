"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { getCurrentProjectId, onProjectChange } from "@/lib/project";

const NAV = [
  { href: "/projects", label: "项目列表", needsProject: false, icon: "📁" },
  { href: "/create", label: "创建项目", needsProject: false, icon: "✨" },
  { href: "/settings", label: "都市快捷设定", needsProject: true, icon: "🏙️" },
  { href: "/chapters", label: "章节管理", needsProject: true, icon: "📖" },
  { href: "/voice", label: "配音设置", needsProject: true, icon: "🎙️" },
  { href: "/export", label: "导出文件", needsProject: true, icon: "📦" },
];

export default function Sidebar() {
  const pathname = usePathname();
  const [projectId, setProjectId] = useState<number | null>(null);

  useEffect(() => {
    setProjectId(getCurrentProjectId());
    return onProjectChange(() => setProjectId(getCurrentProjectId()));
  }, []);

  return (
    <aside className="w-60 shrink-0 bg-ink-800 border-r border-ink-600 min-h-screen p-4 flex flex-col">
      <div className="mb-8 px-2">
        <div className="text-lg font-bold text-brand-400">AI 都市</div>
        <div className="text-sm text-slate-400">小说视频工厂</div>
      </div>

      <nav className="flex flex-col gap-1">
        {NAV.map((item) => {
          const href =
            item.needsProject && projectId
              ? `${item.href}?project=${projectId}`
              : item.href;
          const active = pathname === item.href;
          const disabled = item.needsProject && !projectId;
          return (
            <Link
              key={item.href}
              href={disabled ? "#" : href}
              className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm transition-colors ${
                active
                  ? "bg-brand-500 text-white"
                  : disabled
                    ? "text-slate-600 cursor-not-allowed"
                    : "text-slate-300 hover:bg-ink-700"
              }`}
              onClick={(e) => {
                if (disabled) e.preventDefault();
              }}
            >
              <span>{item.icon}</span>
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="mt-auto pt-4 text-xs text-slate-500 px-2">
        {projectId ? `当前项目 #${projectId}` : "未选择项目"}
      </div>
    </aside>
  );
}
