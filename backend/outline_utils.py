"""章节目录解析与数量规范化（以后端计算为准，支持多语言章节标题）。"""
from __future__ import annotations

import re
from typing import Optional

from language_profiles import get_profile, normalize_language

CHAPTER_HEADING_RE = re.compile(
    r"(?:"
    r"第\s*(\d+)\s*章[：:、\s]*([^\n]*)"
    r"|Chapter\s*(\d+)\s*[：:\-]?\s*([^\n]*)"
    r"|Capítulo\s*(\d+)\s*[：:\-]?\s*([^\n]*)"
    r")",
    re.IGNORECASE,
)


def compute_chapter_count(target_words: int, chapter_words: int) -> int:
    import math

    tw = target_words or 10000
    cw = chapter_words or 3000
    return max(1, math.ceil(tw / cw))


def _chapter_num_and_title(match: re.Match) -> tuple[int, str]:
    if match.group(1) is not None:
        return int(match.group(1)), (match.group(2) or "").strip()
    if match.group(3) is not None:
        return int(match.group(3)), (match.group(4) or "").strip()
    return int(match.group(5)), (match.group(6) or "").strip()


def fallback_chapter(n: int, language: str = "zh") -> dict:
    """缺失章节兜底大纲（按项目语言）。"""
    profile = get_profile(language)
    header = profile["outline_header"].format(n=n)
    f1, f2, f3, f4 = profile["outline_fields"]
    title = profile["fallback_title"]
    body = (
        f"{header}{title}\n"
        f"{f1}延续主线冲突，推动人物关系变化。\n"
        f"{f2}主角继续面对反派压力。\n"
        f"{f3}隐藏线索进一步浮出水面。\n"
        f"{f4}新的危机出现。"
    )
    if language == "en":
        body = (
            f"{header}{title}\n"
            f"{f1} Advance the main conflict and character relationships.\n"
            f"{f2} The protagonist faces pressure from the antagonist.\n"
            f"{f3} A hidden clue surfaces.\n"
            f"{f4} A new crisis emerges."
        )
    elif language == "es":
        body = (
            f"{header}{title}\n"
            f"{f1} Avanzar el conflicto principal y las relaciones.\n"
            f"{f2} El protagonista enfrenta presión del antagonista.\n"
            f"{f3} Surge una pista oculta.\n"
            f"{f4} Aparece una nueva crisis."
        )
    elif language == "ja":
        body = (
            f"{header}{title}\n"
            f"{f1} 主線の対立と人物関係を前に進める。\n"
            f"{f2} 主人公は敵の圧力に直面する。\n"
            f"{f3} 隠された手がかりが浮上する。\n"
            f"{f4} 新たな危機が現れる。"
        )
    return {
        "chapter_number": n,
        "title": title,
        "outline": body,
    }


def parse_outline(outline_text: str) -> list[dict]:
    """把章节目录文本解析为 [{chapter_number, title, outline}]。"""
    if not outline_text:
        return []
    matches = list(CHAPTER_HEADING_RE.finditer(outline_text))
    chapters = []
    for i, m in enumerate(matches):
        number, title = _chapter_num_and_title(m)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(outline_text)
        body = outline_text[start:end].strip()
        default_title = f"第{number}章"
        chapters.append(
            {
                "chapter_number": number,
                "title": title or default_title,
                "outline": body,
            }
        )
    return chapters


def normalize_chapters(
    parsed: list[dict],
    chapter_count: int,
    client=None,
    story_bible: str = "",
    target_words: int = 10000,
    chapter_words: int = 3000,
    language: str = "zh",
) -> list[dict]:
    """
    将解析结果规范为恰好 chapter_count 章（编号 1..N）。
    - 超出：截断，只保留前 N 章
    - 不足：先尝试 DeepSeek 补全，失败则用兜底大纲
    """
    import prompts

    lang = normalize_language(language)
    profile = get_profile(lang)

    by_num: dict[int, dict] = {}
    for ch in sorted(parsed, key=lambda x: x["chapter_number"]):
        num = int(ch["chapter_number"])
        if num not in by_num:
            by_num[num] = ch

    by_num = {n: ch for n, ch in by_num.items() if 1 <= n <= chapter_count}
    missing = [n for n in range(1, chapter_count + 1) if n not in by_num]

    if missing and client and story_bible:
        try:
            prompt = prompts.build_missing_chapters_prompt(
                story_bible,
                target_words,
                chapter_words,
                chapter_count,
                missing,
                lang,
            )
            raw = client.chat(prompt, system=profile["system"], temperature=0.7)
            for ch in parse_outline(raw):
                num = int(ch["chapter_number"])
                if num in missing:
                    by_num[num] = ch
            missing = [n for n in range(1, chapter_count + 1) if n not in by_num]
        except Exception:
            pass

    result: list[dict] = []
    for n in range(1, chapter_count + 1):
        if n in by_num:
            ch = dict(by_num[n])
            ch["chapter_number"] = n
            ch["title"] = ch.get("title") or profile["chapter_name"].format(n=n)
            result.append(ch)
        else:
            result.append(fallback_chapter(n, lang))
    return result
