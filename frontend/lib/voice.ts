import { DEFAULT_VOICE_BY_LANGUAGE } from "./constants";

// 配音设置（存 localStorage，章节管理页 / 一键生成前 3 章读取）。
export interface VoiceConfig {
  voice_key: string;
  rate: string;
}

const KEY = "ai_urban_novel_voice_settings";

const DEFAULT: VoiceConfig = { voice_key: "zh_male", rate: "+0%" };

export function defaultVoiceForLanguage(language?: string): string {
  if (!language) return DEFAULT.voice_key;
  return DEFAULT_VOICE_BY_LANGUAGE[language] || DEFAULT.voice_key;
}

export function getVoiceConfig(projectLanguage?: string): VoiceConfig {
  const fallbackKey = defaultVoiceForLanguage(projectLanguage);
  if (typeof window === "undefined") {
    return { voice_key: fallbackKey, rate: DEFAULT.rate };
  }
  try {
    const raw = window.localStorage.getItem(KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      return {
        voice_key: parsed.voice_key || parsed.voiceKey || fallbackKey,
        rate: parsed.rate || DEFAULT.rate,
      };
    }
  } catch {
    /* ignore */
  }
  return { voice_key: fallbackKey, rate: DEFAULT.rate };
}

export function setVoiceConfig(cfg: VoiceConfig): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(
    KEY,
    JSON.stringify({ voice_key: cfg.voice_key, rate: cfg.rate })
  );
}
