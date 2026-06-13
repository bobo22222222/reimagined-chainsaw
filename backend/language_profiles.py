"""单项目单语言：Prompt / 目录 / 兜底大纲语言配置。"""
from __future__ import annotations

LANGUAGE_PROFILES: dict[str, dict] = {
    "zh": {
        "label": "中文",
        "system": "你是专业都市长篇小说策划、网文作者和长视频文案写手。请全部使用中文创作。",
        "instruction": "请使用中文原创生成，不要翻译。风格适合中文短视频观众。",
        "chapter_name": "第{n}章",
        "outline_header": "第{n}章：",
        "outline_fields": (
            "本章剧情目标：",
            "主要冲突：",
            "反转点：",
            "结尾钩子：",
        ),
        "no_content_placeholder": "（本章尚未生成正文）",
        "fallback_title": "剧情继续推进",
    },
    "en": {
        "label": "English",
        "system": (
            "You are a professional urban fiction planner and long-form video narration writer. "
            "Write everything in natural English."
        ),
        "instruction": (
            "Create the story directly in English. Do not translate from Chinese. "
            "Make it suitable for English-speaking long-form video audiences."
        ),
        "chapter_name": "Chapter {n}",
        "outline_header": "Chapter {n}:",
        "outline_fields": (
            "Chapter Goal:",
            "Main Conflict:",
            "Twist:",
            "Ending Hook:",
        ),
        "no_content_placeholder": "(Chapter content not generated yet)",
        "fallback_title": "The plot moves forward",
    },
    "es": {
        "label": "Español",
        "system": (
            "Eres un guionista profesional de novelas urbanas para videos largos. "
            "Escribe todo en español natural."
        ),
        "instruction": (
            "Crea la historia directamente en español. No traduzcas desde el chino. "
            "Debe sonar natural para una audiencia hispanohablante."
        ),
        "chapter_name": "Capítulo {n}",
        "outline_header": "Capítulo {n}:",
        "outline_fields": (
            "Objetivo del capítulo:",
            "Conflicto principal:",
            "Giro:",
            "Gancho final:",
        ),
        "no_content_placeholder": "(Contenido del capítulo no generado)",
        "fallback_title": "La trama avanza",
    },
    "ja": {
        "label": "日本語",
        "system": (
            "あなたは現代都市小説と長尺動画ナレーションのプロ作家です。"
            "すべて自然な日本語で書いてください。"
        ),
        "instruction": (
            "中国語から翻訳せず、最初から自然な日本語で創作してください。"
            "日本語の長尺動画ナレーション向けにしてください。"
            "各章は2000〜3500文字程度を目安に、場面を絞り簡潔に書いてください。"
        ),
        "chapter_name": "第{n}章",
        "outline_header": "第{n}章：",
        "outline_fields": (
            "本章の目的：",
            "主な対立：",
            "反転ポイント：",
            "ラストの引き：",
        ),
        "no_content_placeholder": "（本章は未生成）",
        "fallback_title": "物語が進む",
    },
}

ALLOWED_LANGUAGES = frozenset(LANGUAGE_PROFILES.keys())

LEGACY_LANGUAGE_MAP = {
    "中文": "zh",
    "英文": "en",
    "西班牙语": "es",
    "日语": "ja",
    "中英西日四语": "zh",
}

DEFAULT_VOICE_BY_LANGUAGE = {
    "zh": "zh_male",
    "en": "en_male",
    "es": "es_male",
    "ja": "ja_male",
}

# 章节长度：推荐范围 + 可接受浮动 + 极端上限（质量检查用，生成时不硬性失败）
CHAPTER_LENGTH_SPECS: dict[str, dict] = {
    "zh": {
        "unit": "chars",
        "unit_label_zh": "汉字",
        "acceptable_min_ratio": 0.7,
        "acceptable_max_ratio": 1.5,
        "target_min_ratio": 0.85,
        "target_max_ratio": 1.15,
        "extreme_max": 5000,
    },
    "en": {
        "unit": "words",
        "unit_label_zh": "英文单词",
        "target_min": 1200,
        "target_max": 2200,
        "acceptable_min": 800,
        "acceptable_max": 3000,
        "extreme_max": 4000,
    },
    "es": {
        "unit": "words",
        "unit_label_zh": "西语单词",
        "target_min": 1200,
        "target_max": 2200,
        "acceptable_min": 800,
        "acceptable_max": 3000,
        "extreme_max": 4000,
    },
    "ja": {
        "unit": "chars",
        "unit_label_zh": "日语字符",
        "target_min": 2000,
        "target_max": 3500,
        "acceptable_min": 1400,
        "acceptable_max": 4500,
        "extreme_max": 6000,
    },
}


def normalize_language(language: str | None) -> str:
    raw = (language or "zh").strip()
    if raw in LANGUAGE_PROFILES:
        return raw
    return LEGACY_LANGUAGE_MAP.get(raw, "zh")


def get_profile(language: str | None) -> dict:
    code = normalize_language(language)
    return LANGUAGE_PROFILES[code]


def default_voice_key(language: str | None) -> str:
    code = normalize_language(language)
    return DEFAULT_VOICE_BY_LANGUAGE.get(code, "zh_male")


def language_directive(profile: dict) -> str:
    return (
        f"目标语言：{profile['label']}\n"
        f"{profile['instruction']}\n"
        "请直接使用目标语言原创生成。\n"
        "不要从中文翻译。\n"
        "不要混用其他语言。"
    )


def resolve_chapter_length(language: str | None, chapter_words: int | None = None) -> dict:
    """返回章节长度推荐/可接受/极端上限（供 QC 与 Prompt 参考）。"""
    lang = normalize_language(language)
    spec = dict(CHAPTER_LENGTH_SPECS.get(lang, CHAPTER_LENGTH_SPECS["zh"]))
    if lang == "zh":
        target = int(chapter_words or 2000)
        spec["target"] = target
        spec["target_min"] = int(target * spec["target_min_ratio"])
        spec["target_max"] = int(target * spec["target_max_ratio"])
        spec["acceptable_min"] = int(target * spec["acceptable_min_ratio"])
        spec["acceptable_max"] = int(target * spec["acceptable_max_ratio"])
    elif lang in ("en", "es", "ja"):
        spec["target"] = (spec["target_min"] + spec["target_max"]) // 2
    return spec


def judge_chapter_length(
    actual: int,
    language: str | None,
    chapter_words: int | None = None,
) -> dict:
    """评估章节长度是否可控，返回 status / severity / message 等。"""
    spec = resolve_chapter_length(language, chapter_words)
    tm, tx = spec["target_min"], spec["target_max"]
    am, ax = spec["acceptable_min"], spec["acceptable_max"]
    extreme = spec["extreme_max"]
    unit = spec.get("unit_label_zh", "字")

    if actual > extreme:
        return {
            "status": "明显过长",
            "severity": "error",
            "code": "length_extreme",
            "message": f"章节长度 {actual} {unit}，极端过长（超过 {extreme} {unit}），请考虑压缩或拆分。",
            "value": actual,
            "unit": unit,
            "judgment": "明显过长",
        }
    if actual > ax:
        return {
            "status": "明显过长",
            "severity": "warning",
            "code": "length_very_long",
            "message": f"章节长度 {actual} {unit}，明显过长（可接受上限约 {ax} {unit}），可能影响配音时长与成本。",
            "value": actual,
            "unit": unit,
            "judgment": "明显过长",
        }
    if actual > tx:
        return {
            "status": "偏长",
            "severity": "info",
            "code": "length_long",
            "message": f"章节长度 {actual} {unit}，略偏长（推荐 {tm}–{tx} {unit}），仍在可接受范围内。",
            "value": actual,
            "unit": unit,
            "judgment": "偏长",
        }
    if actual < am:
        return {
            "status": "偏短",
            "severity": "warning",
            "code": "length_short",
            "message": f"章节长度 {actual} {unit}，偏短（建议至少 {am} {unit}）。",
            "value": actual,
            "unit": unit,
            "judgment": "偏短",
        }
    if actual < tm:
        return {
            "status": "偏短",
            "severity": "info",
            "code": "length_slightly_short",
            "message": f"章节长度 {actual} {unit}，略偏短（推荐 {tm}–{tx} {unit}），仍在可接受范围内。",
            "value": actual,
            "unit": unit,
            "judgment": "偏短",
        }
    return {
        "status": "正常",
        "severity": None,
        "code": "length_ok",
        "message": "",
        "value": actual,
        "unit": unit,
        "judgment": "正常",
    }


def format_length_prompt_line(language: str | None, chapter_words: int | None = None) -> str:
    """生成 Prompt 中的软性长度说明（不强制固定字数）。"""
    lang = normalize_language(language)
    cw = int(chapter_words or 2000)
    common = (
        "请控制在适合长视频旁白的一章长度。"
        "不要过短，也不要明显过长。"
        "以完整剧情节奏优先，字数可在合理范围内浮动。"
    )
    if lang == "zh":
        return (
            f"1. {common}\n"
            f"   本章建议长度约 {cw} 中文字，可适度浮动。"
            f"以剧情完整、节奏自然为优先，不要为了凑字数重复内容。"
        )
    if lang == "en":
        return (
            f"1. {common}\n"
            "   Aim for a complete chapter suitable for long-form voice-over. "
            "Keep the length controlled and avoid making it excessively long. "
            "Do not pad the chapter with repetition."
        )
    if lang == "es":
        return (
            f"1. {common}\n"
            "   Escribe un capítulo completo para narración en video largo, "
            "manteniendo una extensión controlada. "
            "Evita hacerlo excesivamente largo y no rellenes con repeticiones."
        )
    if lang == "ja":
        return (
            f"1. {common}\n"
            "   長尺動画のナレーションに適した一章として、自然な長さで書いてください。\n"
            "   目安は2000〜3500文字程度です。\n"
            "   長くても4500文字以内に収めるよう意識してください。\n"
            "   同じ感情描写や状況説明を繰り返して文字数を増やさないでください。\n"
            "   場面は2〜3個に絞り、会話と描写を簡潔にしてください。\n"
            "   物語の流れを保ちながら、長すぎる章にしないでください。"
        )
    return f"1. {common}"


def ja_extreme_char_limit() -> int:
    """日语章节极端长度上限（字符数）。"""
    return int(CHAPTER_LENGTH_SPECS["ja"]["extreme_max"])


def format_length_guidance_for_rewrite(language: str | None, chapter_words: int | None = None) -> str:
    """重写时的软性长度提示。"""
    lang = normalize_language(language)
    spec = resolve_chapter_length(lang, chapter_words)
    unit = spec.get("unit_label_zh", "字")
    return (
        f"保持适合长视频旁白的章节长度（推荐约 {spec['target_min']}–{spec['target_max']} {unit}，"
        f"可适度浮动）；以剧情完整为先，不要为凑字数重复内容，也不要明显过长。"
    )
