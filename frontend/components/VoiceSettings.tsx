"use client";

import { useEffect, useState } from "react";
import {
  DEFAULT_VOICE_BY_LANGUAGE,
  RATE_OPTIONS,
  VOICE_GROUPS,
  VOICE_OPTIONS,
  languageLabel,
} from "@/lib/constants";
import { defaultVoiceForLanguage, getVoiceConfig, setVoiceConfig } from "@/lib/voice";

export default function VoiceSettings({ projectLanguage = "zh" }: { projectLanguage?: string }) {
  const lang = projectLanguage || "zh";
  const defaultKey = defaultVoiceForLanguage(lang);
  const [voiceKey, setVoiceKey] = useState(defaultKey);
  const [rate, setRate] = useState("+0%");
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    const cfg = getVoiceConfig(lang);
    const preferred = DEFAULT_VOICE_BY_LANGUAGE[lang];
    const validKeys = VOICE_OPTIONS.map((v) => v.key);
    const key =
      cfg.voice_key && validKeys.includes(cfg.voice_key) ? cfg.voice_key : preferred;
    setVoiceKey(key);
    setRate(cfg.rate);
  }, [lang]);

  function save() {
    setVoiceConfig({ voice_key: voiceKey, rate });
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }

  const currentGroup = VOICE_GROUPS.find((g) => g.lang === lang) || VOICE_GROUPS[0];
  const groupedOptions = VOICE_GROUPS.map((group) => ({
    ...group,
    options: VOICE_OPTIONS.filter((v) => group.keys.includes(v.key)),
  }));

  return (
    <div className="card max-w-xl space-y-5">
      <div className="text-sm text-slate-400">
        当前项目目标语言：<span className="text-slate-200">{languageLabel(lang)}</span>
        ，默认推荐 {VOICE_OPTIONS.find((v) => v.key === defaultKey)?.label || defaultKey}
      </div>

      <div>
        <label className="label">配音声音（edge-tts 免费）</label>
        <select
          className="input"
          value={voiceKey}
          onChange={(e) => setVoiceKey(e.target.value)}
        >
          {groupedOptions.map((group) => (
            <optgroup key={group.lang} label={group.label}>
              {group.options.map((v) => (
                <option key={v.key} value={v.key}>
                  {v.label}
                  {group.lang === lang ? " ★ 推荐" : ""}
                </option>
              ))}
            </optgroup>
          ))}
        </select>
        <p className="text-xs text-slate-500 mt-1">
          {currentGroup.label}为当前项目默认分组；其他语言音色仅供预览，不建议用于本项目。
        </p>
      </div>

      <div>
        <label className="label">语速</label>
        <select className="input" value={rate} onChange={(e) => setRate(e.target.value)}>
          {RATE_OPTIONS.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}
            </option>
          ))}
        </select>
      </div>

      <div className="text-xs text-slate-500 leading-relaxed">
        第一版每章生成一个 MP3。TTS 读取章节统一字段 content。
        <br />
        保存后，在「章节管理」点击「生成配音」或批量配音即按此配置合成。
      </div>

      <button className="btn-primary" onClick={save}>
        {saved ? "已保存 ✓" : "保存配音设置"}
      </button>
    </div>
  );
}
