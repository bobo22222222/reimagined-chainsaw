"""都市题材校验：用户设定（严格）与 AI 生成内容（语言感知、温和）。"""
from __future__ import annotations

from fastapi import HTTPException

from language_profiles import normalize_language

CHECKED_FIELDS = [
    "genre",
    "protagonist_type",
    "opening_hook",
    "main_conflict",
    "antagonist_type",
    "plot_style",
    "emotion_direction",
    "tone",
    "ending_type",
    "target_audience",
    "custom_setting",
    "title",
]

FORBIDDEN_MESSAGE = (
    "当前版本只支持都市现代小说，请删除修仙、玄幻、穿越、重生、系统爽文、末日等非都市设定。"
)

ALLOWED_TARGET_WORDS = [5000, 10000, 20000, 50000, 100000, 200000]

TARGET_WORDS_MESSAGE = (
    "生成字数不合法，请选择 5千、1万、2万、5万、10万或20万字。"
)

# --------------------------------------------------------------------------- #
# 用户设定：较严格（不含裸「系统」）
# --------------------------------------------------------------------------- #
FORBIDDEN_CN_SETTINGS = [
    "修仙",
    "玄幻",
    "穿越",
    "重生",
    "系统爽文",
    "觉醒系统",
    "绑定系统",
    "获得系统",
    "任务系统",
    "签到系统",
    "末日",
    "丧尸",
    "异能",
    "魔法",
    "古代",
    "仙侠",
    "灵气复苏",
    "宗门",
    "修炼",
    "飞升",
    "科幻灾难",
    "灵气",
]

FORBIDDEN_EN_SETTINGS = [
    "cultivation",
    "immortal sect",
    "spiritual energy",
    "reincarnation system",
    "transmigration",
    "apocalypse",
    "zombie outbreak",
    "magic power",
    "supernatural ability",
    "xianxia",
    "wuxia",
]

FORBIDDEN_ES_SETTINGS = [
    "cultivación inmortal",
    "secta inmortal",
    "energía espiritual",
    "reencarnación",
    "transmigración",
    "apocalipsis zombi",
    "poder mágico",
    "habilidad sobrenatural",
]

FORBIDDEN_JA_SETTINGS = [
    "修仙",
    "仙侠",
    "異世界転生",
    "転生",
    "タイムリープ",
    "魔法",
    "魔力",
    "ゾンビ",
    "終末世界",
    "霊気",
    "宗門",
    "修行で仙人",
    "覚醒システム",
    "チートシステム",
]

SETTINGS_BY_LANG = {
    "zh": FORBIDDEN_CN_SETTINGS,
    "en": FORBIDDEN_EN_SETTINGS,
    "es": FORBIDDEN_ES_SETTINGS,
    "ja": FORBIDDEN_JA_SETTINGS,
}

# --------------------------------------------------------------------------- #
# AI 生成正文：明显非都市短语（不含裸 system / システム）
# --------------------------------------------------------------------------- #
FORBIDDEN_CN_CONTENT = [
    "修仙",
    "玄幻",
    "穿越到古代",
    "穿越到",
    "主角穿越",
    "重生回",
    "主角重生",
    "绑定神级系统",
    "绑定系统",
    "觉醒系统",
    "获得系统",
    "系统爽文",
    "签到系统",
    "任务系统",
    "灵气复苏",
    "宗门",
    "修炼飞升",
    "修炼成仙",
    "飞升",
    "丧尸末日",
    "末日降临",
    "魔法觉醒",
    "异能觉醒",
    "仙侠",
]

ALLOWED_CN_SYSTEM_PHRASES = [
    "公司系统",
    "银行系统",
    "监控系统",
    "财务系统",
    "内部系统",
    "警务系统",
    "安保系统",
    "商业系统",
    "医疗系统",
    "法律系统",
    "管理系统",
    "交易系统",
    "信息系统",
    "办公系统",
]

FORBIDDEN_EN_CONTENT = [
    "cultivation",
    "immortal sect",
    "spiritual energy",
    "reincarnation system",
    "transmigration",
    "apocalypse",
    "zombie outbreak",
    "magic power",
    "supernatural ability",
    "time travel to ancient",
    "reborn ten years",
    "cheat system",
    "binding system",
    "xianxia",
]

FORBIDDEN_ES_CONTENT = [
    "cultivación inmortal",
    "secta inmortal",
    "energía espiritual",
    "reencarnación",
    "transmigración",
    "apocalipsis zombi",
    "poder mágico",
    "habilidad sobrenatural",
    "viaje en el tiempo",
    "renacido diez años",
]

FORBIDDEN_JA_CONTENT = [
    "修仙",
    "仙侠",
    "異世界転生",
    "転生して",
    "タイムリープ",
    "魔法で",
    "魔力を",
    "ゾンビ",
    "終末世界",
    "霊気が",
    "宗門",
    "修行で仙人",
    "チートシステム",
    "神級システム",
    "覚醒システム",
]

ALLOWED_JA_SYSTEM_PHRASES = [
    "社内システム",
    "監視システム",
    "予約システム",
    "管理システム",
    "銀行システム",
    "警備システム",
    "情報システム",
    "内部システム",
]

CONTENT_BY_LANG = {
    "zh": FORBIDDEN_CN_CONTENT,
    "en": FORBIDDEN_EN_CONTENT,
    "es": FORBIDDEN_ES_CONTENT,
    "ja": FORBIDDEN_JA_CONTENT,
}

CONTENT_WHITELIST_BY_LANG = {
    "zh": ALLOWED_CN_SYSTEM_PHRASES,
    "ja": ALLOWED_JA_SYSTEM_PHRASES,
    "en": [],
    "es": [],
}


class UrbanContentViolation(Exception):
    """AI 生成正文未通过都市题材校验。"""

    def __init__(self, hits: list[str], message: str | None = None):
        self.hits = hits
        self.message = message or _format_hits_message(hits)
        super().__init__(self.message)


def _format_hits_message(hits: list[str]) -> str:
    if not hits:
        return FORBIDDEN_MESSAGE
    return f"{FORBIDDEN_MESSAGE}（命中：{', '.join(hits[:5])}）"


def _collect_field_text(data: dict) -> str:
    parts: list[str] = []
    for field in CHECKED_FIELDS:
        value = data.get(field)
        if value and isinstance(value, str):
            parts.append(value)
    return "\n".join(parts)


def find_settings_violations(data: dict, language: str = "zh") -> list[str]:
    lang = normalize_language(language or data.get("language"))
    phrases = SETTINGS_BY_LANG.get(lang, FORBIDDEN_CN_SETTINGS)
    hits: list[str] = []
    for field in CHECKED_FIELDS:
        value = data.get(field)
        if not value or not isinstance(value, str):
            continue
        check = value if lang != "en" else value.lower()
        for phrase in phrases:
            key = phrase if lang != "en" else phrase.lower()
            if key in check and phrase not in hits:
                hits.append(phrase)
    return hits


def _is_whitelisted_cn_system(text: str, phrase: str) -> bool:
    """若命中项仅出现在现代都市「xx系统」白名单短语内，则忽略。"""
    if phrase != "系统" and "系统" not in phrase:
        return False
    for allowed in ALLOWED_CN_SYSTEM_PHRASES:
        if allowed in text:
            # 若文本中的违规片段实际上是允许短语的一部分，跳过裸「系统」误杀
            if phrase == "系统" and allowed in text:
                continue
    # 更直接：若文本含白名单短语且未含明确禁词，不单独因「系统」报错
    for allowed in ALLOWED_CN_SYSTEM_PHRASES:
        if allowed in text:
            stripped = text.replace(allowed, "")
            if "系统" not in stripped:
                return True
    return False


def find_content_violations(text: str, language: str = "zh") -> list[str]:
    if not text or not isinstance(text, str):
        return []
    lang = normalize_language(language)
    phrases = CONTENT_BY_LANG.get(lang, FORBIDDEN_CN_CONTENT)
    hits: list[str] = []
    check = text if lang not in ("en", "es") else text.lower()
    for phrase in phrases:
        key = phrase if lang not in ("en", "es") else phrase.lower()
        if key in check and phrase not in hits:
            if lang == "zh" and _is_whitelisted_cn_system(text, phrase):
                continue
            hits.append(phrase)
    return hits


def assert_urban_project_settings(data: dict, language: str | None = None) -> None:
    """用户设定校验（创建/更新/保存设定/生成前）。"""
    lang = normalize_language(language or (data or {}).get("language"))
    hits = find_settings_violations(data or {}, lang)
    if hits:
        raise HTTPException(status_code=400, detail=_format_hits_message(hits))


def assert_urban_generated_content(
    text: str,
    language: str = "zh",
    *,
    raise_on_hit: bool = True,
) -> list[str]:
    """AI 生成内容温和校验。默认命中明显违规时抛 400。"""
    hits = find_content_violations(text or "", language)
    if hits and raise_on_hit:
        raise HTTPException(status_code=400, detail=_format_hits_message(hits))
    return hits


def check_urban_generated_content(text: str, language: str = "zh") -> list[str]:
    """不抛异常，仅返回命中列表（供质量检查等使用）。"""
    return find_content_violations(text or "", language)


def assert_urban_only(data: dict) -> None:
    """兼容旧调用：等同 assert_urban_project_settings。"""
    assert_urban_project_settings(data)


def format_chapter_generation_error(
    reason: str,
    language: str,
    chapter_number: int,
    retried: bool,
    stage: str = "章节正文生成",
) -> str:
    return (
        f"失败阶段：{stage}\n"
        f"失败原因：{reason}\n"
        f"是否已重试：{'是' if retried else '否'}\n"
        f"项目语言：{language}\n"
        f"章节编号：{chapter_number}"
    )


def assert_valid_target_words(target_words: int) -> None:
    if target_words not in ALLOWED_TARGET_WORDS:
        raise HTTPException(status_code=400, detail=TARGET_WORDS_MESSAGE)
