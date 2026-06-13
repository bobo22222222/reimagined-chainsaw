// 后端 API 客户端封装。
export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8000";

export interface Project {
  id: number;
  project_name: string;
  title: string;
  target_words: number;
  chapter_words: number;
  language: string;
  generate_tts: number;
  genre?: string;
  protagonist_type?: string;
  opening_hook?: string;
  main_conflict?: string;
  antagonist_type?: string;
  plot_style?: string;
  emotion_direction?: string;
  tone?: string;
  ending_type?: string;
  target_audience?: string;
  custom_setting?: string;
  story_bible?: string;
  outline?: string;
  status: string;
  created_at: string;
  updated_at: string;
  chapter_count?: number;
  chapters?: Chapter[];
}

export interface Chapter {
  id: number;
  project_id: number;
  chapter_number: number;
  title?: string;
  outline?: string;
  content?: string;
  /** @deprecated v0.2 兼容字段，请使用 content */
  content_cn?: string;
  summary?: string;
  word_count: number;
  status: string;
  audio_path?: string;
  tts_status: string;
  quality_score?: number | null;
  quality_report?: string | null;
  quality_status?: string;
  quality_checked_at?: string | null;
  last_error?: string | null;
  last_error_at?: string | null;
}

export interface QualityCheckResult {
  chapter_id: number;
  chapter_number: number;
  score: number;
  passed: boolean;
  issues: Array<{ code?: string; severity: string; message: string }>;
  suggestions: string[];
  summary: string;
  checked_at?: string;
  length?: {
    value: number;
    unit: string;
    judgment: string;
    status: string;
  };
}

export interface QualityCheckRangeResult {
  project_id: number;
  start_chapter: number;
  end_chapter: number;
  checked_chapters: QualityCheckResult[];
  skipped_chapters: number[];
  failed_chapters: number[];
  low_score_count: number;
  message: string;
}

export interface RewriteIssuesResult {
  project_id: number;
  start_chapter: number;
  end_chapter: number;
  score_threshold: number;
  max_rounds?: number;
  rewritten_chapters: number[];
  skipped_chapters: number[];
  failed_chapters: number[];
  message: string;
}

export function getChapterContent(ch: Chapter): string {
  return (ch.content || ch.content_cn || "").trim();
}

export function parseQualityReport(raw?: string | null) {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as QualityCheckResult;
  } catch {
    return null;
  }
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...(options.headers as Record<string, string> | undefined),
      },
    });
  } catch {
    throw new Error("无法连接后端服务，请确认 FastAPI 已启动。");
  }
  if (!res.ok) {
    let detail = `请求失败 (${res.status})`;
    try {
      const data = await res.json();
      if (data.detail !== undefined) {
        detail = formatApiDetail(data.detail);
      }
    } catch {
      /* ignore */
    }
    throw new Error(detail);
  }
  return res.json() as Promise<T>;
}

function formatApiDetail(detail: unknown): string {
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) {
    return detail
      .map((item) => {
        if (typeof item === "string") return item;
        if (item && typeof item === "object" && "msg" in item) {
          return String((item as { msg?: string }).msg);
        }
        return JSON.stringify(item);
      })
      .join("；");
  }
  if (detail && typeof detail === "object") {
    return JSON.stringify(detail);
  }
  return String(detail);
}

export const api = {
  listProjects: () => request<Project[]>("/api/projects"),
  getProject: (id: number) => request<Project>(`/api/projects/${id}`),
  createProject: (body: any) =>
    request<Project>("/api/projects", { method: "POST", body: JSON.stringify(body) }),
  updateProject: (id: number, body: any) =>
    request<Project>(`/api/projects/${id}`, { method: "PUT", body: JSON.stringify(body) }),
  deleteProject: (id: number) =>
    request<{ ok: boolean }>(`/api/projects/${id}`, { method: "DELETE" }),

  saveUrbanSettings: (id: number, body: any) =>
    request<Project>(`/api/projects/${id}/save-urban-settings`, {
      method: "POST",
      body: JSON.stringify(body),
    }),
  applyTemplate: (id: number, templateKey: string) =>
    request<Project>(`/api/projects/${id}/apply-template`, {
      method: "POST",
      body: JSON.stringify({ template_key: templateKey }),
    }),

  generateBible: (id: number) =>
    request<{ story_bible: string }>(`/api/projects/${id}/generate-bible`, {
      method: "POST",
    }),
  generateOutline: (id: number) =>
    request<{ outline: string; chapters: Chapter[] }>(
      `/api/projects/${id}/generate-outline`,
      { method: "POST" }
    ),
  generateFirst3: (
    id: number,
    payload?: { voice_key?: string; rate?: string }
  ) => generateFirst3(id, payload),
  generateChapterRange: (
    id: number,
    payload: {
      start_chapter: number;
      end_chapter: number;
      voice_key?: string;
      rate?: string;
    }
  ) => generateChapterRange(id, payload),
  generateTtsRange: (
    id: number,
    payload: {
      start_chapter: number;
      end_chapter: number;
      voice_key?: string;
      rate?: string;
    }
  ) => generateTtsRange(id, payload),
  generateChapter: (chapterId: number) =>
    request<Chapter>(`/api/chapters/${chapterId}/generate`, { method: "POST" }),
  regenerateChapter: (chapterId: number) =>
    request<Chapter>(`/api/chapters/${chapterId}/regenerate`, { method: "POST" }),
  summarizeChapter: (chapterId: number) =>
    request<{ summary: string }>(`/api/chapters/${chapterId}/summarize`, {
      method: "POST",
    }),

  listChapters: (projectId: number) =>
    request<Chapter[]>(`/api/projects/${projectId}/chapters`),
  getChapter: (chapterId: number) => request<Chapter>(`/api/chapters/${chapterId}`),
  updateChapter: (chapterId: number, body: any) =>
    request<Chapter>(`/api/chapters/${chapterId}`, {
      method: "PUT",
      body: JSON.stringify(body),
    }),

  generateTTS: (chapterId: number, voiceKey: string, rate: string) =>
    request<Chapter>(`/api/chapters/${chapterId}/tts`, {
      method: "POST",
      body: JSON.stringify({ voice_key: voiceKey, rate }),
    }),

  checkChapterQuality: (chapterId: number) =>
    request<QualityCheckResult>(`/api/chapters/${chapterId}/quality-check`, {
      method: "POST",
    }),
  rewriteChapter: (chapterId: number) =>
    request<Chapter>(`/api/chapters/${chapterId}/rewrite`, { method: "POST" }),
  qualityCheckRange: (
    projectId: number,
    payload: { start_chapter: number; end_chapter: number; score_threshold?: number }
  ) =>
    request<QualityCheckRangeResult>(
      `/api/projects/${projectId}/quality-check-range`,
      {
        method: "POST",
        body: JSON.stringify({
          start_chapter: payload.start_chapter,
          end_chapter: payload.end_chapter,
          score_threshold: payload.score_threshold ?? 70,
        }),
      }
    ),
  rewriteIssues: (
    projectId: number,
    payload: {
      start_chapter: number;
      end_chapter: number;
      score_threshold?: number;
      max_rounds?: number;
    }
  ) =>
    request<RewriteIssuesResult>(`/api/projects/${projectId}/rewrite-issues`, {
      method: "POST",
      body: JSON.stringify({
        start_chapter: payload.start_chapter,
        end_chapter: payload.end_chapter,
        score_threshold: payload.score_threshold ?? 70,
        max_rounds: payload.max_rounds ?? 1,
      }),
    }),
};

export interface GenerateFirst3Result {
  project_id: number;
  generated_chapters: number[];
  failed_chapters: number[];
  message: string;
  voice_key: string;
  rate: string;
}

export async function generateFirst3(
  projectId: number,
  payload?: { voice_key?: string; rate?: string }
): Promise<GenerateFirst3Result> {
  return request<GenerateFirst3Result>(
    `/api/projects/${projectId}/generate-first-3`,
    {
      method: "POST",
      body: JSON.stringify({
        voice_key: payload?.voice_key || "zh_male",
        rate: payload?.rate || "+0%",
      }),
    }
  );
}

export interface GenerateChapterRangeResult {
  project_id: number;
  start_chapter: number;
  end_chapter: number;
  generated_chapters: number[];
  skipped_chapters: number[];
  failed_chapters: number[];
  voice_key: string;
  rate: string;
  message: string;
}

export async function generateChapterRange(
  projectId: number,
  payload: {
    start_chapter: number;
    end_chapter: number;
    voice_key?: string;
    rate?: string;
  }
): Promise<GenerateChapterRangeResult> {
  return request<GenerateChapterRangeResult>(
    `/api/projects/${projectId}/generate-chapter-range`,
    {
      method: "POST",
      body: JSON.stringify({
        start_chapter: payload.start_chapter,
        end_chapter: payload.end_chapter,
        voice_key: payload.voice_key || "zh_male",
        rate: payload.rate || "+0%",
      }),
    }
  );
}

export interface GenerateMediaRangeResult {
  project_id: number;
  start_chapter: number;
  end_chapter: number;
  generated_chapters: number[];
  skipped_chapters: number[];
  failed_chapters: number[];
  message: string;
  voice_key?: string;
  rate?: string;
}

export async function generateTtsRange(
  projectId: number,
  payload: {
    start_chapter: number;
    end_chapter: number;
    voice_key?: string;
    rate?: string;
  }
): Promise<GenerateMediaRangeResult> {
  return request<GenerateMediaRangeResult>(
    `/api/projects/${projectId}/generate-tts-range`,
    {
      method: "POST",
      body: JSON.stringify({
        start_chapter: payload.start_chapter,
        end_chapter: payload.end_chapter,
        voice_key: payload.voice_key || "zh_male",
        rate: payload.rate || "+0%",
      }),
    }
  );
}

export const downloadUrls = {
  chapterTxt: (id: number) => `${API_BASE_URL}/api/chapters/${id}/download/txt`,
  chapterMp3: (id: number) => `${API_BASE_URL}/api/chapters/${id}/download/mp3`,
  projectTxt: (id: number) => `${API_BASE_URL}/api/projects/${id}/export/txt`,
  projectChaptersZip: (id: number) =>
    `${API_BASE_URL}/api/projects/${id}/export/chapters-zip`,
  projectAudioZip: (id: number) =>
    `${API_BASE_URL}/api/projects/${id}/export/audio-zip`,
  projectFullZip: (id: number) => `${API_BASE_URL}/api/projects/${id}/export/full-zip`,
};
