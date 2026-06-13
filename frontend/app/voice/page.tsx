"use client";

import { useEffect, useState } from "react";
import NoProject from "@/components/NoProject";
import VoiceSettings from "@/components/VoiceSettings";
import { api, Project } from "@/lib/api";
import { languageLabel } from "@/lib/constants";
import { useProjectId } from "@/lib/useProjectId";

export default function VoicePage() {
  const projectId = useProjectId();
  const [project, setProject] = useState<Project | null>(null);

  useEffect(() => {
    if (typeof projectId !== "number") return;
    api.getProject(projectId).then(setProject).catch(() => setProject(null));
  }, [projectId]);

  if (projectId === undefined) return <div className="text-slate-400">加载中…</div>;
  if (projectId === null) return <NoProject />;

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold">配音设置</h1>
        <p className="text-sm text-slate-400">
          项目目标语言：{languageLabel(project?.language)}。默认音色与项目语言匹配。
        </p>
      </div>
      <VoiceSettings projectLanguage={project?.language || "zh"} />
    </div>
  );
}
