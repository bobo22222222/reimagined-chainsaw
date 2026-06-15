"""Self-tests for TTS input cleaning.

This script is used by scripts/run_v04_tts_cleaner_test.ps1. It does not
read API keys and does not call any LLM provider.
"""
from __future__ import annotations

import json
import sys

import database
from content_utils import word_count_for_language
from tts_text_cleaner import clean_text_for_tts


RAW_SAMPLE = """# 第八章：会议室里的 PPT

- **CEO** 把 `USB` 放到桌上。
- 他看着投影说：***这份方案必须今晚落地***。

---

秘书补了一句：“PPT 里的预算别再写成 *大概*，董事会要数字。”
"""

FORBIDDEN_MARKDOWN = ["#", "**", "***", "`", "---", "- "]


def _now_sql() -> str:
    from datetime import datetime

    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def run_unit() -> None:
    cases = [
        ("zh", "# 标题\n- **CEO** 看了 `USB` 里的 PPT", ["标题", "C E O", "U S B", "P P T"]),
        ("en", "## Title\n- **Board meeting** with `numbers`", ["Title", "Board meeting", "numbers"]),
        ("es", "### Titulo\n- **Reunion** con `datos`", ["Titulo", "Reunion", "datos"]),
        ("ja", "## 会議\n- **資料** と `数字`", ["会議", "資料", "数字"]),
    ]
    for lang, raw, expected_parts in cases:
        cleaned = clean_text_for_tts(raw, lang)
        hits = [token for token in FORBIDDEN_MARKDOWN if token in cleaned]
        if hits:
            raise AssertionError(f"{lang}: markdown residue remains: {hits!r} in {cleaned!r}")
        for part in expected_parts:
            if part not in cleaned:
                raise AssertionError(f"{lang}: expected {part!r} in {cleaned!r}")
    print("PASS")


def create_fixture() -> None:
    database.ensure_schema()
    ts = _now_sql()
    cleaned = clean_text_for_tts(RAW_SAMPLE, "zh")
    hits = [token for token in FORBIDDEN_MARKDOWN if token in cleaned]

    with database.db_cursor() as cur:
        cur.execute(
            """INSERT INTO projects (
                   project_name, title, target_words, chapter_words, language,
                   generate_tts, generate_srt, story_bible, outline, status,
                   created_at, updated_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                "v04-tts-cleaner-fixture",
                "V04 TTS Cleaner Fixture",
                5000,
                2000,
                "zh",
                1,
                0,
                "fixture",
                "fixture",
                "created",
                ts,
                ts,
            ),
        )
        project_id = cur.lastrowid
        cur.execute(
            """INSERT INTO chapters (
                   project_id, chapter_number, title, outline, content,
                   word_count, status, tts_status, srt_status, created_at, updated_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                project_id,
                1,
                "TTS Cleaner Fixture",
                "fixture",
                RAW_SAMPLE,
                word_count_for_language(RAW_SAMPLE, "zh"),
                "completed",
                "pending",
                "pending",
                ts,
                ts,
            ),
        )
        chapter_id = cur.lastrowid

    print(
        json.dumps(
            {
                "project_id": project_id,
                "chapter_id": chapter_id,
                "raw_len": len(RAW_SAMPLE),
                "clean_len": len(cleaned),
                "markdown_removed": len(hits) == 0,
                "forbid_hits": hits,
                "raw_sample": RAW_SAMPLE[:160],
                "clean_sample": cleaned[:160],
            },
            ensure_ascii=True,
        )
    )


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "unit"
    if mode == "unit":
        run_unit()
    elif mode == "fixture":
        create_fixture()
    else:
        raise SystemExit(f"Unknown mode: {mode}")


if __name__ == "__main__":
    main()
