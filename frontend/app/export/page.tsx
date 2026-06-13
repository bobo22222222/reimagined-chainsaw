"use client";

import NoProject from "@/components/NoProject";
import ExportPanel from "@/components/ExportPanel";
import { useProjectId } from "@/lib/useProjectId";

export default function ExportPage() {
  const projectId = useProjectId();

  if (projectId === undefined) return <div className="text-slate-400">加载中…</div>;
  if (projectId === null) return <NoProject />;

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold">导出文件</h1>
        <p className="text-sm text-slate-400">
          导出视频制作素材：文案 TXT、配音 MP3 以及完整项目 ZIP。
        </p>
      </div>
      <ExportPanel projectId={projectId} />
    </div>
  );
}
