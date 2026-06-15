"""章节正文统一读写与多语言长度计量。"""
from __future__ import annotations

import re

from language_profiles import judge_chapter_length, normalize_language, resolve_chapter_length


def count_cjk_chars(text: str) -> int:
    if not text:
        return 0
    return len(re.sub(r"\s", "", text))


def count_latin_words(text: str) -> int:
    if not text:
        return 0
    return len(re.findall(r"\b[\w']+\b", text, flags=re.UNICODE))


def measure_content_length(text: str, language: str | None = None) -> int:
    """按语言计量：zh/ja 为字符数（不含空白），en/es 为单词数。"""
    lang = normalize_language(language)
    if lang in ("en", "es"):
        return count_latin_words(text)
    return count_cjk_chars(text)


def word_count(text: str) -> int:
    """兼容旧调用：默认按去空白字符数（中文场景）。"""
    return count_cjk_chars(text)


def word_count_for_language(text: str, language: str | None = None) -> int:
    return measure_content_length(text, language)


def is_length_within_bounds(
    text: str,
    language: str | None = None,
    chapter_words: int | None = None,
) -> tuple[bool, dict]:
    """返回 (是否在可接受范围内, spec 含 actual)。仅用于测试/统计，不阻断生成。"""
    spec = resolve_chapter_length(language, chapter_words)
    actual = measure_content_length(text, language)
    spec = {**spec, "actual": actual}
    ok = spec["acceptable_min"] <= actual <= spec["acceptable_max"]
    return ok, spec


def length_report_meta(text: str, language: str | None, chapter_words: int | None = None) -> dict:
    """供质量报告展示的长度元数据。"""
    actual = measure_content_length(text, language)
    judged = judge_chapter_length(actual, language, chapter_words)
    return {
        "value": actual,
        "unit": judged["unit"],
        "judgment": judged["judgment"],
        "status": judged["status"],
    }


def get_chapter_content(chapter: dict) -> str:
    """读取章节正文：优先 v0.3 content，回退旧库多语言字段。"""
    return (
        chapter.get("content")
        or chapter.get("content_cn")
        or chapter.get("content_en")
        or chapter.get("content_es")
        or chapter.get("content_ja")
        or ""
    ).strip()


def chapter_has_content(chapter: dict) -> bool:
    return bool(get_chapter_content(chapter))
