"""TTS 前文本清洗：仅用于 edge-tts 输入，不修改数据库正文或导出 TXT。"""
import re

from language_profiles import normalize_language

TTS_REPLACEMENTS = {
    "PPT": "P P T",
    "CEO": "C E O",
    "USB": "U S B",
}

_HEADER_RE = re.compile(r"^\s*#{1,6}\s*(.*)$")
_LIST_RE = re.compile(r"^\s*(?:[-*•・]|\d+\.)\s+(.*)$")
_HRULE_RE = re.compile(r"^\s*[-*_]{3,}\s*$")
_FENCED_CODE_RE = re.compile(r"```[\s\S]*?```")
_INLINE_CODE_RE = re.compile(r"`([^`]*)`")
_BOLD_ITALIC_RE = [
    (re.compile(r"\*\*\*(.+?)\*\*\*"), r"\1"),
    (re.compile(r"\*\*(.+?)\*\*"), r"\1"),
    (re.compile(r"__(.+?)__"), r"\1"),
    (re.compile(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"), r"\1"),
    (re.compile(r"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"), r"\1"),
]
_STRAY_MARKDOWN_RE = re.compile(r"[#*_`]+")
_MULTI_SPACE_RE = re.compile(r"[ \t]{2,}")
_MULTI_NEWLINE_RE = re.compile(r"\n{3,}")


def _clean_line(line: str) -> str:
    if not line.strip():
        return ""
    if _HRULE_RE.match(line):
        return ""
    m = _HEADER_RE.match(line)
    if m:
        return m.group(1).strip()
    m = _LIST_RE.match(line)
    if m:
        return m.group(1).strip()
    return line.strip()


def _apply_zh_replacements(text: str) -> str:
    result = text
    for src, dst in TTS_REPLACEMENTS.items():
        result = result.replace(src, dst)
    return result


def clean_text_for_tts(text: str, language: str) -> str:
    """清洗传给 edge-tts 的文本，保留小说标点，不改动数据库正文。"""
    if not text:
        return ""

    lang = normalize_language(language)
    cleaned = text.replace("\r\n", "\n").replace("\r", "\n")
    cleaned = _FENCED_CODE_RE.sub("", cleaned)
    cleaned = _INLINE_CODE_RE.sub(r"\1", cleaned)

    lines = [_clean_line(line) for line in cleaned.split("\n")]
    cleaned = "\n".join(lines)

    for pattern, repl in _BOLD_ITALIC_RE:
        cleaned = pattern.sub(repl, cleaned)

    cleaned = _STRAY_MARKDOWN_RE.sub("", cleaned)
    cleaned = _MULTI_SPACE_RE.sub(" ", cleaned)
    cleaned = _MULTI_NEWLINE_RE.sub("\n\n", cleaned)

    if lang == "zh":
        cleaned = _apply_zh_replacements(cleaned)

    return cleaned.strip()
