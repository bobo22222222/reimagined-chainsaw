"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import ProjectForm, { ProjectFormValues } from "@/components/ProjectForm";
import { api } from "@/lib/api";
import { setCurrentProjectId } from "@/lib/project";

export default function CreatePage() {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(values: ProjectFormValues) {
    setSubmitting(true);
    try {
      const project = await api.createProject(values);
      setCurrentProjectId(project.id);
      router.push(`/settings?project=${project.id}`);
    } catch (e: any) {
      alert(e.message || "创建失败");
      setSubmitting(false);
    }
  }

  return (
    <div>
      <h1 className="text-2xl font-bold mb-2">创建项目</h1>
      <p className="text-slate-400 mb-6">
        创建后将进入「都市快捷设定」，选择题材即可一键生成。
      </p>
      <ProjectForm onSubmit={handleSubmit} submitting={submitting} />
    </div>
  );
}
