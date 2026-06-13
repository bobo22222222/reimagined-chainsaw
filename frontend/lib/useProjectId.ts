"use client";

import { useEffect, useState } from "react";
import { getCurrentProjectId, setCurrentProjectId } from "@/lib/project";

// 优先读取 URL ?project=ID，其次读取 localStorage，避免使用 useSearchParams
// 带来的 Suspense 限制。解析到的 id 会同步写回 localStorage。
export function useProjectId(): number | null | undefined {
  // undefined = 尚未解析；null = 解析完但没有项目
  const [id, setId] = useState<number | null | undefined>(undefined);

  useEffect(() => {
    let resolved: number | null = null;
    if (typeof window !== "undefined") {
      const params = new URLSearchParams(window.location.search);
      const q = params.get("project");
      if (q) {
        resolved = Number(q);
        setCurrentProjectId(resolved);
      } else {
        resolved = getCurrentProjectId();
      }
    }
    setId(resolved);
  }, []);

  return id;
}
