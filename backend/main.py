"""AI 都市小说视频工厂 —— FastAPI 后端入口。"""
import math
import re
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response

import database
import exporter
import outline_utils
import prompts
import quality_service
from content_utils import get_chapter_content, word_count_for_language
from language_profiles import default_voice_key, get_profile, ja_extreme_char_limit, normalize_language
from models import (
    ApplyTemplate,
    ChapterUpdate,
    GenerateChapterRangeRequest,
    GenerateFirst3Request,
    GenerateTtsRangeRequest,
    ProjectCreate,
    ProjectUpdate,
    QualityCheckRangeRequest,
    RewriteIssuesRequest,
    TTSRequest,
    UrbanSettings,
)
from tts_service import ALLOWED_RATES, VOICE_MAP, generate_tts
from tts_text_cleaner import clean_text_for_tts
from validators import (
    assert_urban_generated_content,
    assert_urban_only,
    assert_urban_project_settings,
    assert_valid_target_words,
    find_content_violations,
    format_chapter_generation_error,
)

BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = exporter.OUTPUT_DIR

EXPORT_EMPTY_MSG = "当前项目还没有可导出的内容，请先生成章节。"

app = FastAPI(title="AI 都市小说视频工厂")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _startup():
    database.ensure_schema()
    exporter.ensure_output_dirs()


# --------------------------------------------------------------------------- #
# 工具函数
# --------------------------------------------------------------------------- #
def _require_exportable(project: dict, chapters: list[dict]) -> None:
    if not exporter.has_exportable_content(project, chapters):
        raise HTTPException(status_code=400, detail=EXPORT_EMPTY_MSG)
def now() -> str:
    return datetime.utcnow().isoformat(timespec="seconds")


def row_to_dict(row) -> dict:
    return dict(row) if row is not None else None


def get_project_or_404(project_id: int) -> dict:
    with database.db_cursor() as cur:
        cur.execute("SELECT * FROM projects WHERE id = ?", (project_id,))
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="项目不存在")
    return row_to_dict(row)


def get_chapter_or_404(chapter_id: int) -> dict:
    with database.db_cursor() as cur:
        cur.execute("SELECT * FROM chapters WHERE id = ?", (chapter_id,))
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="章节不存在")
    return row_to_dict(row)


def list_chapters(project_id: int) -> list[dict]:
    with database.db_cursor() as cur:
        cur.execute(
            "SELECT * FROM chapters WHERE project_id = ? ORDER BY chapter_number ASC",
            (project_id,),
        )
        return [row_to_dict(r) for r in cur.fetchall()]


def cn_word_count(text: str) -> int:
    """兼容旧调用。"""
    return word_count_for_language(text, "zh")


def _project_language(project: dict) -> str:
    return normalize_language(project.get("language"))


def _system_for_project(project: dict) -> str:
    return get_profile(_project_language(project))["system"]


def assert_valid_tts_params(voice_key: str, rate: str) -> None:
    """校验配音参数；voice_key 须在 VOICE_MAP 内，rate 须在允许列表内。"""
    if voice_key not in VOICE_MAP:
        raise HTTPException(status_code=400, detail="voice_key 无效，请选择支持的音色")
    if rate not in ALLOWED_RATES:
        raise HTTPException(
            status_code=400,
            detail="rate 无效，只允许 -20%/-10%/+0%/+10%/+20%",
        )


def _set_project_status(project_id: int, status: str) -> None:
    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE projects SET status = ?, updated_at = ? WHERE id = ?",
            (status, now(), project_id),
        )


def get_deepseek():
    """延迟实例化 DeepSeek 客户端；缺少 Key 时返回 400。"""
    try:
        from deepseek_client import DEEPSEEK_KEY_ERROR, DeepSeekClient

        return DeepSeekClient()
    except RuntimeError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:  # noqa: BLE001
        from deepseek_client import DEEPSEEK_KEY_ERROR

        raise HTTPException(status_code=400, detail=DEEPSEEK_KEY_ERROR)


def _set_chapter_error(chapter_id: int, error: str) -> None:
    msg = (error or "未知错误")[:2000]
    ts = now()
    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET last_error = ?, last_error_at = ?, updated_at = ? WHERE id = ?",
            (msg, ts, ts, chapter_id),
        )


def _clear_chapter_error(chapter_id: int) -> None:
    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET last_error = NULL, last_error_at = NULL, updated_at = ? WHERE id = ?",
            (now(), chapter_id),
        )


def _exception_message(exc: Exception) -> str:
    if isinstance(exc, HTTPException):
        detail = exc.detail
        if isinstance(detail, str):
            return detail
        return str(detail)
    return str(exc)


def parse_outline(outline_text: str) -> list[dict]:
    """兼容旧调用，委托 outline_utils。"""
    return outline_utils.parse_outline(outline_text)


# --------------------------------------------------------------------------- #
# 项目接口
# --------------------------------------------------------------------------- #
@app.post("/api/projects")
def create_project(payload: ProjectCreate):
    assert_urban_project_settings(payload.model_dump(), payload.language)
    assert_valid_target_words(payload.target_words)
    ts = now()
    with database.db_cursor() as cur:
        cur.execute(
            """INSERT INTO projects
            (project_name, title, target_words, chapter_words, language,
             generate_tts, generate_srt, status, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (
                payload.project_name,
                payload.title,
                payload.target_words,
                payload.chapter_words,
                payload.language,
                1 if payload.generate_tts else 0,
                0,
                "created",
                ts,
                ts,
            ),
        )
        pid = cur.lastrowid
    return get_project_or_404(pid)


@app.get("/api/projects")
def get_projects():
    with database.db_cursor() as cur:
        cur.execute("SELECT * FROM projects ORDER BY id DESC")
        projects = [row_to_dict(r) for r in cur.fetchall()]
        for p in projects:
            cur.execute(
                "SELECT COUNT(*) AS c FROM chapters WHERE project_id = ?", (p["id"],)
            )
            p["chapter_count"] = cur.fetchone()["c"]
    return projects


@app.get("/api/projects/{project_id}")
def get_project(project_id: int):
    project = get_project_or_404(project_id)
    project["chapters"] = list_chapters(project_id)
    return project


@app.put("/api/projects/{project_id}")
def update_project(project_id: int, payload: ProjectUpdate):
    get_project_or_404(project_id)
    data = payload.model_dump(exclude_unset=True)
    if not data:
        return get_project_or_404(project_id)
    assert_urban_project_settings(data, data.get("language"))
    if "language" in data:
        code = normalize_language(data["language"])
        if code not in {"zh", "en", "es", "ja"}:
            raise HTTPException(status_code=400, detail="language 必须是 zh / en / es / ja")
        data["language"] = code
    if "target_words" in data:
        assert_valid_target_words(data["target_words"])
    # bool -> int
    data.pop("generate_srt", None)
    for key in ("generate_tts",):
        if key in data and isinstance(data[key], bool):
            data[key] = 1 if data[key] else 0
    data["updated_at"] = now()
    cols = ", ".join(f"{k} = ?" for k in data)
    with database.db_cursor() as cur:
        cur.execute(
            f"UPDATE projects SET {cols} WHERE id = ?",
            (*data.values(), project_id),
        )
    return get_project_or_404(project_id)


@app.delete("/api/projects/{project_id}")
def delete_project(project_id: int):
    get_project_or_404(project_id)
    with database.db_cursor() as cur:
        cur.execute("DELETE FROM chapters WHERE project_id = ?", (project_id,))
        cur.execute("DELETE FROM projects WHERE id = ?", (project_id,))
    return {"ok": True}


# --------------------------------------------------------------------------- #
# 都市设定接口
# --------------------------------------------------------------------------- #
@app.post("/api/projects/{project_id}/save-urban-settings")
def save_urban_settings(project_id: int, payload: UrbanSettings):
    get_project_or_404(project_id)
    data = payload.model_dump(exclude_unset=True)
    assert_urban_only(data)
    data["updated_at"] = now()
    cols = ", ".join(f"{k} = ?" for k in data)
    with database.db_cursor() as cur:
        cur.execute(
            f"UPDATE projects SET {cols} WHERE id = ?",
            (*data.values(), project_id),
        )
    return get_project_or_404(project_id)


@app.post("/api/projects/{project_id}/apply-template")
def apply_template(project_id: int, payload: ApplyTemplate):
    get_project_or_404(project_id)
    template = prompts.TEMPLATES.get(payload.template_key)
    if not template:
        raise HTTPException(status_code=400, detail="模板不存在")
    data = {k: v for k, v in template.items() if k != "name"}
    data["updated_at"] = now()
    cols = ", ".join(f"{k} = ?" for k in data)
    with database.db_cursor() as cur:
        cur.execute(
            f"UPDATE projects SET {cols} WHERE id = ?",
            (*data.values(), project_id),
        )
    return get_project_or_404(project_id)


@app.get("/api/templates")
def get_templates():
    return prompts.TEMPLATES


# --------------------------------------------------------------------------- #
# 生成接口
# --------------------------------------------------------------------------- #
@app.post("/api/projects/{project_id}/generate-bible")
def generate_bible(project_id: int):
    project = get_project_or_404(project_id)
    assert_urban_project_settings(project, _project_language(project))
    _set_project_status(project_id, "bible_generating")
    client = get_deepseek()
    prompt = prompts.build_bible_prompt(project)
    system = _system_for_project(project)
    try:
        bible = client.chat(prompt, system=system)
    except HTTPException:
        _set_project_status(project_id, "failed")
        raise
    except Exception as e:  # noqa: BLE001
        _set_project_status(project_id, "failed")
        raise HTTPException(status_code=500, detail=f"生成总设定失败：{e}")
    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE projects SET story_bible = ?, status = ?, updated_at = ? WHERE id = ?",
            (bible, "bible_completed", now(), project_id),
        )
    return {"story_bible": bible}


@app.post("/api/projects/{project_id}/generate-outline")
def generate_outline(project_id: int):
    project = get_project_or_404(project_id)
    assert_urban_only(project)
    if not project.get("story_bible"):
        raise HTTPException(status_code=400, detail="请先生成小说总设定")

    target_words = project.get("target_words") or 10000
    chapter_words = project.get("chapter_words") or 3000
    chapter_count = outline_utils.compute_chapter_count(target_words, chapter_words)

    _set_project_status(project_id, "outline_generating")
    client = get_deepseek()
    lang = _project_language(project)
    prompt = prompts.build_outline_prompt(
        project["story_bible"], target_words, chapter_words, chapter_count, lang
    )
    system = _system_for_project(project)
    try:
        outline = client.chat(prompt, system=system)
    except HTTPException:
        _set_project_status(project_id, "failed")
        raise
    except Exception as e:  # noqa: BLE001
        _set_project_status(project_id, "failed")
        raise HTTPException(status_code=500, detail=f"生成章节目录失败：{e}")

    parsed = outline_utils.parse_outline(outline)
    chapters_to_create = outline_utils.normalize_chapters(
        parsed,
        chapter_count,
        client=client,
        story_bible=project.get("story_bible") or "",
        target_words=target_words,
        chapter_words=chapter_words,
        language=lang,
    )
    ts = now()
    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE projects SET outline = ?, status = ?, updated_at = ? WHERE id = ?",
            (outline, "outline_completed", ts, project_id),
        )
        cur.execute("DELETE FROM chapters WHERE project_id = ?", (project_id,))
        for ch in chapters_to_create:
            cur.execute(
                """INSERT INTO chapters
                (project_id, chapter_number, title, outline, status,
                 tts_status, srt_status, created_at, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?)""",
                (
                    project_id,
                    ch["chapter_number"],
                    ch["title"],
                    ch["outline"],
                    "pending",
                    "pending",
                    "pending",
                    ts,
                    ts,
                ),
            )
    return {
        "outline": outline,
        "chapter_count": chapter_count,
        "chapters": list_chapters(project_id),
    }


def _generate_chapter_content(chapter_id: int) -> dict:
    chapter = get_chapter_or_404(chapter_id)
    project = get_project_or_404(chapter["project_id"])
    lang = _project_language(project)
    ch_num = int(chapter["chapter_number"])

    assert_urban_project_settings(project, lang)
    outline_check = f"{chapter.get('title') or ''}\n{chapter.get('outline') or ''}"
    try:
        assert_urban_generated_content(outline_check, lang)
    except HTTPException:
        # 章纲为 AI 产物，温和校验：仅记录，不阻断（正文生成时会约束）
        pass

    previous_summary = ""
    if ch_num > 1:
        with database.db_cursor() as cur:
            cur.execute(
                "SELECT summary FROM chapters WHERE project_id = ? AND chapter_number = ?",
                (chapter["project_id"], ch_num - 1),
            )
            prev = cur.fetchone()
            if prev and prev["summary"]:
                previous_summary = prev["summary"]

    client = get_deepseek()
    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
            ("generating", now(), chapter_id),
        )

    chapter_words = project.get("chapter_words") or 3000
    story_bible = project.get("story_bible") or ""
    book_outline = project.get("outline") or ""
    chapter_outline = chapter.get("outline") or ""
    system = _system_for_project(project)

    base_prompt = prompts.build_chapter_prompt(
        ch_num,
        story_bible,
        book_outline,
        chapter_outline,
        previous_summary,
        chapter_words,
        lang,
    )

    generation_retried = False
    retry_reason: str | None = None
    content = ""
    last_reason = ""
    violations: list[str] = []

    for attempt in range(2):
        try:
            if attempt == 0:
                prompt = base_prompt
            else:
                generation_retried = True
                prompt = prompts.build_chapter_strict_retry_prompt(
                    ch_num,
                    story_bible,
                    book_outline,
                    chapter_outline,
                    previous_summary,
                    chapter_words,
                    lang,
                    violations,
                )
            content = client.chat(prompt, system=system)
            assert_urban_generated_content(content, lang)
            last_reason = ""
            break
        except HTTPException as e:
            last_reason = _exception_message(e)
            violations = find_content_violations(content, lang) if content else []
            if attempt == 0 and ("都市" in last_reason or violations):
                with database.db_cursor() as cur:
                    cur.execute(
                        "UPDATE chapters SET last_error = ?, last_error_at = ?, updated_at = ? WHERE id = ?",
                        (
                            format_chapter_generation_error(
                                last_reason, lang, ch_num, retried=False, stage="章节正文生成(第1次)"
                            ),
                            now(),
                            now(),
                            chapter_id,
                        ),
                    )
                continue
            with database.db_cursor() as cur:
                cur.execute(
                    "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
                    ("failed", now(), chapter_id),
                )
            _set_chapter_error(
                chapter_id,
                format_chapter_generation_error(
                    last_reason, lang, ch_num, retried=True, stage="章节正文生成"
                ),
            )
            raise
        except Exception as e:  # noqa: BLE001
            err = _exception_message(e)
            with database.db_cursor() as cur:
                cur.execute(
                    "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
                    ("failed", now(), chapter_id),
                )
            _set_chapter_error(
                chapter_id,
                format_chapter_generation_error(
                    f"生成正文失败：{err}", lang, ch_num, generation_retried, stage="章节正文生成"
                ),
            )
            if isinstance(e, HTTPException):
                raise
            raise HTTPException(status_code=500, detail=f"生成正文失败：{e}")

    if not content:
        with database.db_cursor() as cur:
            cur.execute(
                "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
                ("failed", now(), chapter_id),
            )
        _set_chapter_error(
            chapter_id,
            format_chapter_generation_error(
                "模型未返回正文", lang, ch_num, generation_retried, stage="章节正文生成"
            ),
        )
        raise HTTPException(status_code=500, detail="生成正文失败：模型未返回内容")

    # 日语：极端超长（>6000 字符）温和压缩重试 1 次（不影响 zh/en/es）
    if lang == "ja":
        extreme_max = ja_extreme_char_limit()
        wc_ja = word_count_for_language(content, lang)
        if wc_ja > extreme_max:
            with database.db_cursor() as cur:
                cur.execute(
                    "UPDATE chapters SET last_error = ?, last_error_at = ?, updated_at = ? WHERE id = ?",
                    (
                        f"日语章节极端超长（约 {wc_ja} 字符，上限 {extreme_max}），正在压缩重试…",
                        now(),
                        now(),
                        chapter_id,
                    ),
                )
            generation_retried = True
            retry_reason = "JA_EXTREME_LENGTH"
            compress_prompt = prompts.build_chapter_ja_extreme_length_retry_prompt(
                ch_num,
                story_bible,
                book_outline,
                chapter_outline,
                previous_summary,
                chapter_words,
                content,
                wc_ja,
            )
            try:
                content = client.chat(compress_prompt, system=system)
                assert_urban_generated_content(content, lang)
                wc_ja = word_count_for_language(content, lang)
                if wc_ja > extreme_max:
                    err_msg = (
                        f"日语章节极端超长（约 {wc_ja} 字符，上限 {extreme_max}），已重试仍失败"
                    )
                    with database.db_cursor() as cur:
                        cur.execute(
                            "UPDATE chapters SET status = ?, generation_retry_reason = ?, updated_at = ? WHERE id = ?",
                            ("failed", retry_reason, now(), chapter_id),
                        )
                    _set_chapter_error(chapter_id, err_msg)
                    raise HTTPException(status_code=422, detail=err_msg)
            except HTTPException:
                raise
            except Exception as e:  # noqa: BLE001
                err = _exception_message(e)
                with database.db_cursor() as cur:
                    cur.execute(
                        "UPDATE chapters SET status = ?, generation_retry_reason = ?, updated_at = ? WHERE id = ?",
                        ("failed", retry_reason, now(), chapter_id),
                    )
                _set_chapter_error(
                    chapter_id,
                    f"日语章节极端超长压缩重试失败：{err}",
                )
                raise HTTPException(status_code=500, detail=f"日语章节压缩重试失败：{e}")

    wc = word_count_for_language(content, lang)
    with database.db_cursor() as cur:
        cur.execute(
            """UPDATE chapters SET content = ?, word_count = ?, status = ?,
               generation_retry_reason = ?, updated_at = ? WHERE id = ?""",
            (content, wc, "summarizing", retry_reason, now(), chapter_id),
        )

    _summarize_chapter(chapter_id, client=client, content=content, language=lang)
    _clear_chapter_error(chapter_id)
    result = get_chapter_or_404(chapter_id)
    result["generation_retried"] = generation_retried
    result["retry_reason"] = retry_reason
    return result


@app.post("/api/chapters/{chapter_id}/generate")
def generate_chapter(chapter_id: int):
    return _generate_chapter_content(chapter_id)


@app.post("/api/chapters/{chapter_id}/regenerate")
def regenerate_chapter(chapter_id: int):
    return _generate_chapter_content(chapter_id)


def _summarize_chapter(chapter_id: int, client=None, content: str = None, language: str = "zh") -> str:
    chapter = get_chapter_or_404(chapter_id)
    if content is None:
        content = get_chapter_content(chapter)
    if not content:
        return ""
    if client is None:
        client = get_deepseek()
    lang = normalize_language(language) if language else _project_language(
        get_project_or_404(chapter["project_id"])
    )
    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
            ("summarizing", now(), chapter_id),
        )
    prompt = prompts.build_summary_prompt(content, lang)
    system = get_profile(lang)["system"]
    try:
        summary = client.chat(prompt, system=system, temperature=0.5)
        with database.db_cursor() as cur:
            cur.execute(
                "UPDATE chapters SET summary = ?, status = ?, updated_at = ? WHERE id = ?",
                (summary, "completed", now(), chapter_id),
            )
        return summary
    except Exception:  # noqa: BLE001
        # 摘要失败不阻断正文，正文仍标记为已完成
        with database.db_cursor() as cur:
            cur.execute(
                "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
                ("completed", now(), chapter_id),
            )
        return ""


@app.post("/api/chapters/{chapter_id}/summarize")
def summarize_chapter(chapter_id: int):
    summary = _summarize_chapter(chapter_id)
    return {"summary": summary}


def _previous_chapter_summary(chapter: dict) -> str:
    if chapter["chapter_number"] <= 1:
        return ""
    with database.db_cursor() as cur:
        cur.execute(
            "SELECT summary FROM chapters WHERE project_id = ? AND chapter_number = ?",
            (chapter["project_id"], chapter["chapter_number"] - 1),
        )
        prev = cur.fetchone()
        if prev and prev["summary"]:
            return prev["summary"]
    return ""


def _check_chapter_quality(chapter_id: int) -> dict:
    chapter = get_chapter_or_404(chapter_id)
    project = get_project_or_404(chapter["project_id"])
    content = get_chapter_content(chapter)
    if not content:
        raise HTTPException(status_code=400, detail="请先生成章节正文")

    target_words = project.get("chapter_words") or 3000
    lang = _project_language(project)
    ts = now()

    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET quality_status = ?, updated_at = ? WHERE id = ?",
            ("checking", ts, chapter_id),
        )

    rule_issues, length_meta = quality_service.run_rule_checks(
        content, chapter.get("outline") or "", target_words, lang
    )

    llm_data: dict = {}
    try:
        client = get_deepseek()
        prompt = prompts.build_quality_check_prompt(
            chapter["chapter_number"],
            project.get("story_bible") or "",
            chapter.get("outline") or "",
            content,
            target_words,
            lang,
        )
        raw = client.chat(prompt, system=get_profile(lang)["system"], temperature=0.3)
        llm_data = quality_service.parse_llm_quality_json(raw)
    except HTTPException as e:
        with database.db_cursor() as cur:
            cur.execute(
                "UPDATE chapters SET quality_status = ?, updated_at = ? WHERE id = ?",
                ("failed", now(), chapter_id),
            )
        _set_chapter_error(chapter_id, f"质量检查失败：{_exception_message(e)}")
        raise
    except Exception as e:  # noqa: BLE001
        with database.db_cursor() as cur:
            cur.execute(
                "UPDATE chapters SET quality_status = ?, updated_at = ? WHERE id = ?",
                ("failed", now(), chapter_id),
            )
        _set_chapter_error(chapter_id, f"质量检查失败：{e}")
        raise HTTPException(status_code=500, detail=f"质量检查失败：{e}")

    report = quality_service.merge_quality_report(rule_issues, llm_data, length_meta)
    report_json = quality_service.report_to_json(report)
    checked_at = now()

    with database.db_cursor() as cur:
        cur.execute(
            """UPDATE chapters SET quality_score = ?, quality_report = ?,
               quality_status = ?, quality_checked_at = ?, updated_at = ? WHERE id = ?""",
            (
                report["score"],
                report_json,
                "completed",
                checked_at,
                checked_at,
                chapter_id,
            ),
        )
    _clear_chapter_error(chapter_id)

    return {
        "chapter_id": chapter_id,
        "chapter_number": chapter["chapter_number"],
        **report,
        "checked_at": checked_at,
    }


def _rewrite_chapter_content(chapter_id: int) -> dict:
    chapter = get_chapter_or_404(chapter_id)
    project = get_project_or_404(chapter["project_id"])
    content = get_chapter_content(chapter)
    if not content:
        raise HTTPException(status_code=400, detail="请先生成章节正文")

    report = quality_service.report_from_json(chapter.get("quality_report"))
    if not report:
        report = _check_chapter_quality(chapter_id)
        chapter = get_chapter_or_404(chapter_id)
        report = quality_service.report_from_json(chapter.get("quality_report")) or report

    lang = _project_language(project)
    target_words = project.get("chapter_words") or 3000
    assert_urban_project_settings(project, lang)
    previous_summary = _previous_chapter_summary(chapter)
    report_text = quality_service.report_to_json(report)

    client = get_deepseek()
    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
            ("rewriting", now(), chapter_id),
        )

    prompt = prompts.build_rewrite_prompt(
        chapter["chapter_number"],
        project.get("story_bible") or "",
        project.get("outline") or "",
        chapter.get("outline") or "",
        previous_summary,
        content,
        report_text,
        target_words,
        lang,
    )
    system = _system_for_project(project)
    try:
        new_content = client.chat(prompt, system=system, temperature=0.75)
        assert_urban_generated_content(new_content, lang)
    except Exception as e:  # noqa: BLE001
        err = _exception_message(e)
        with database.db_cursor() as cur:
            cur.execute(
                "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
                ("completed", now(), chapter_id),
            )
        _set_chapter_error(chapter_id, f"一键重写失败：{err}")
        if isinstance(e, HTTPException):
            raise
        raise HTTPException(status_code=500, detail=f"重写失败：{e}")

    wc = word_count_for_language(new_content, lang)
    with database.db_cursor() as cur:
        cur.execute(
            """UPDATE chapters SET content = ?, word_count = ?, status = ?,
               quality_score = NULL, quality_report = NULL,
               quality_status = ?, tts_status = ?, updated_at = ? WHERE id = ?""",
            (new_content, wc, "summarizing", "pending", "pending", now(), chapter_id),
        )

    _summarize_chapter(chapter_id, client=client, content=new_content, language=lang)
    _clear_chapter_error(chapter_id)
    return get_chapter_or_404(chapter_id)


@app.post("/api/chapters/{chapter_id}/quality-check")
def check_chapter_quality(chapter_id: int):
    return _check_chapter_quality(chapter_id)


@app.post("/api/chapters/{chapter_id}/rewrite")
def rewrite_chapter(chapter_id: int):
    return _rewrite_chapter_content(chapter_id)


# --------------------------------------------------------------------------- #
# 章节接口
# --------------------------------------------------------------------------- #
@app.get("/api/projects/{project_id}/chapters")
def get_project_chapters(project_id: int):
    get_project_or_404(project_id)
    return list_chapters(project_id)


@app.get("/api/chapters/{chapter_id}")
def get_chapter(chapter_id: int):
    return get_chapter_or_404(chapter_id)


@app.put("/api/chapters/{chapter_id}")
def update_chapter(chapter_id: int, payload: ChapterUpdate):
    chapter = get_chapter_or_404(chapter_id)
    project = get_project_or_404(chapter["project_id"])
    lang = _project_language(project)
    data = payload.model_dump(exclude_unset=True)
    if "content" in data:
        data["word_count"] = word_count_for_language(data["content"], lang)
        data["status"] = "completed"
    if not data:
        return get_chapter_or_404(chapter_id)
    data["updated_at"] = now()
    cols = ", ".join(f"{k} = ?" for k in data)
    with database.db_cursor() as cur:
        cur.execute(
            f"UPDATE chapters SET {cols} WHERE id = ?",
            (*data.values(), chapter_id),
        )
    return get_chapter_or_404(chapter_id)


# --------------------------------------------------------------------------- #
# TTS 接口
# --------------------------------------------------------------------------- #
async def _do_chapter_tts(chapter_id: int, voice_key: str, rate: str) -> dict:
    chapter = get_chapter_or_404(chapter_id)
    content = get_chapter_content(chapter)
    if not content:
        raise HTTPException(status_code=400, detail="请先生成章节正文")

    project = get_project_or_404(chapter["project_id"])
    lang = project.get("language") or "zh"
    tts_text = clean_text_for_tts(content, lang)

    project_dir = exporter.project_output_dir(chapter["project_id"])
    audio_path = project_dir / f"chapter_{chapter['chapter_number']:03d}.mp3"
    audio_path_str = str(audio_path)

    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET tts_status = ?, updated_at = ? WHERE id = ?",
            ("generating", now(), chapter_id),
        )
    try:
        await generate_tts(tts_text, audio_path_str, voice_key, rate)
    except Exception as e:  # noqa: BLE001
        err = _exception_message(e)
        with database.db_cursor() as cur:
            cur.execute(
                "UPDATE chapters SET tts_status = ?, updated_at = ? WHERE id = ?",
                ("failed", now(), chapter_id),
            )
        _set_chapter_error(chapter_id, f"配音生成失败：{err}")
        raise HTTPException(status_code=500, detail=f"配音生成失败：{e}")

    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET audio_path = ?, tts_status = ?, updated_at = ? WHERE id = ?",
            (audio_path_str, "completed", now(), chapter_id),
        )
    _clear_chapter_error(chapter_id)
    return get_chapter_or_404(chapter_id)


async def _try_chapter_tts(chapter_id: int, voice_key: str, rate: str) -> bool:
    """批量任务用：TTS 失败只标记该章，不抛异常。"""
    try:
        await _do_chapter_tts(chapter_id, voice_key, rate)
        return True
    except Exception:  # noqa: BLE001
        return False


def _do_chapter_srt(chapter_id: int) -> dict:
    chapter = get_chapter_or_404(chapter_id)
    content = get_chapter_content(chapter)
    if not content:
        raise HTTPException(status_code=400, detail="请先生成本章正文")
    project = get_project_or_404(chapter["project_id"])

    project_dir = exporter.project_output_dir(chapter["project_id"])
    srt_path = project_dir / f"chapter_{chapter['chapter_number']:03d}.srt"
    srt_path_str = str(srt_path)

    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET srt_status = ?, updated_at = ? WHERE id = ?",
            ("generating", now(), chapter_id),
        )

    try:
        srt_text = generate_srt(content, project.get("language") or "中文")
        srt_path.write_text(srt_text, encoding="utf-8")
    except Exception as e:  # noqa: BLE001
        with database.db_cursor() as cur:
            cur.execute(
                "UPDATE chapters SET srt_status = ?, updated_at = ? WHERE id = ?",
                ("failed", now(), chapter_id),
            )
        raise HTTPException(status_code=500, detail=f"字幕生成失败：{e}")

    with database.db_cursor() as cur:
        cur.execute(
            "UPDATE chapters SET srt_path = ?, srt_status = ?, updated_at = ? WHERE id = ?",
            (srt_path_str, "completed", now(), chapter_id),
        )
    return get_chapter_or_404(chapter_id)


def _try_chapter_srt(chapter_id: int) -> bool:
    """批量任务用：SRT 失败只标记该章，不抛异常。"""
    try:
        _do_chapter_srt(chapter_id)
        return True
    except Exception:  # noqa: BLE001
        return False


@app.post("/api/chapters/{chapter_id}/tts")
async def chapter_tts(chapter_id: int, payload: TTSRequest):
    return await _do_chapter_tts(chapter_id, payload.voice_key, payload.rate)


@app.post("/api/chapters/{chapter_id}/srt")
def chapter_srt(chapter_id: int):
    return _do_chapter_srt(chapter_id)


# --------------------------------------------------------------------------- #
# 一键生成前 3 章
# --------------------------------------------------------------------------- #
@app.post("/api/projects/{project_id}/generate-first-3")
async def generate_first_3(
    project_id: int,
    payload: GenerateFirst3Request = GenerateFirst3Request(),
):
    project = get_project_or_404(project_id)
    assert_urban_only(project)

    generate_tts_flag = bool(project.get("generate_tts"))
    voice_key = payload.voice_key
    rate = payload.rate
    if generate_tts_flag:
        assert_valid_tts_params(voice_key, rate)

    # 1~2. 缺少总设定 / 目录则先补齐
    if not project.get("story_bible"):
        generate_bible(project_id)
        project = get_project_or_404(project_id)
    if not project.get("outline") or not list_chapters(project_id):
        generate_outline(project_id)
        project = get_project_or_404(project_id)

    chapters = list_chapters(project_id)[:3]
    if not chapters:
        raise HTTPException(status_code=400, detail="未能生成章节目录，请检查总设定")

    generated: list[int] = []
    failed: list[int] = []
    tts_failed: list[int] = []

    _set_project_status(project_id, "generating_chapters")
    for ch in chapters:
        num = ch["chapter_number"]
        try:
            _generate_chapter_content(ch["id"])
            if generate_tts_flag and not await _try_chapter_tts(ch["id"], voice_key, rate):
                tts_failed.append(num)
            generated.append(num)
        except Exception as e:  # noqa: BLE001
            with database.db_cursor() as cur:
                cur.execute(
                    "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
                    ("failed", now(), ch["id"]),
                )
            _set_chapter_error(ch["id"], f"生成正文失败：{_exception_message(e)}")
            failed.append(num)

    if not failed:
        message = "前 3 章生成完成"
    elif generated:
        message = f"部分完成：成功 {generated}，失败 {failed}"
    else:
        message = "前 3 章生成失败，请检查 DeepSeek 配置"
    if tts_failed:
        message += f"；配音失败章节：{tts_failed}"

    if generated and not failed:
        _set_project_status(project_id, "completed")
    elif generated:
        _set_project_status(project_id, "completed")
    else:
        _set_project_status(project_id, "failed")

    return {
        "project_id": project_id,
        "generated_chapters": generated,
        "failed_chapters": failed,
        "message": message,
        "voice_key": voice_key,
        "rate": rate,
    }


# --------------------------------------------------------------------------- #
# 批量生成章节
# --------------------------------------------------------------------------- #
@app.post("/api/projects/{project_id}/generate-chapter-range")
async def generate_chapter_range(
    project_id: int,
    payload: GenerateChapterRangeRequest,
):
    project = get_project_or_404(project_id)
    assert_urban_only(project)

    start_ch = payload.start_chapter
    end_ch = payload.end_chapter

    if start_ch < 1:
        raise HTTPException(status_code=400, detail="开始章节必须大于等于 1。")
    if end_ch < start_ch:
        raise HTTPException(status_code=400, detail="结束章节必须大于等于开始章节。")
    if end_ch - start_ch + 1 > 5:
        raise HTTPException(status_code=400, detail="一次最多只能批量生成 5 章。")

    generate_tts_flag = bool(project.get("generate_tts"))
    voice_key = payload.voice_key
    rate = payload.rate
    if generate_tts_flag:
        assert_valid_tts_params(voice_key, rate)

    if not project.get("story_bible"):
        generate_bible(project_id)
        project = get_project_or_404(project_id)
    if not project.get("outline") or not list_chapters(project_id):
        generate_outline(project_id)
        project = get_project_or_404(project_id)

    all_chapters = list_chapters(project_id)
    target_chapters = [
        ch for ch in all_chapters if start_ch <= ch["chapter_number"] <= end_ch
    ]
    target_chapters.sort(key=lambda c: c["chapter_number"])

    if not target_chapters:
        raise HTTPException(
            status_code=400,
            detail=f"第 {start_ch} 章到第 {end_ch} 章范围内没有章节，请先生成章节目录。",
        )

    generated: list[int] = []
    skipped: list[int] = []
    failed: list[int] = []
    tts_failed: list[int] = []

    _set_project_status(project_id, "generating_chapters")
    for ch in target_chapters:
        num = ch["chapter_number"]
        content = get_chapter_content(ch)
        if content:
            skipped.append(num)
            continue
        try:
            _generate_chapter_content(ch["id"])
            if generate_tts_flag and not await _try_chapter_tts(ch["id"], voice_key, rate):
                tts_failed.append(num)
            generated.append(num)
        except Exception as e:  # noqa: BLE001
            with database.db_cursor() as cur:
                cur.execute(
                    "UPDATE chapters SET status = ?, updated_at = ? WHERE id = ?",
                    ("failed", now(), ch["id"]),
                )
            _set_chapter_error(ch["id"], f"生成正文失败：{_exception_message(e)}")
            failed.append(num)

    if not failed and (generated or skipped):
        message = "批量生成完成"
    elif generated:
        message = f"部分完成：成功 {generated}，跳过 {skipped}，失败 {failed}"
    elif skipped and not failed:
        message = "指定范围内章节均已有正文，已全部跳过"
    else:
        message = "批量生成失败，请检查 DeepSeek 配置"
    if tts_failed:
        message += f"；配音失败章节：{tts_failed}"

    if generated or (skipped and not failed):
        _set_project_status(project_id, "completed")
    elif failed and not generated:
        _set_project_status(project_id, "failed")
    else:
        _set_project_status(project_id, "completed")

    return {
        "project_id": project_id,
        "start_chapter": start_ch,
        "end_chapter": end_ch,
        "generated_chapters": generated,
        "skipped_chapters": skipped,
        "failed_chapters": failed,
        "voice_key": voice_key,
        "rate": rate,
        "message": message,
    }


def _validate_chapter_range(start_ch: int, end_ch: int) -> None:
    if start_ch < 1:
        raise HTTPException(status_code=400, detail="开始章节必须大于等于 1。")
    if end_ch < start_ch:
        raise HTTPException(status_code=400, detail="结束章节必须大于等于开始章节。")
    if end_ch - start_ch + 1 > 5:
        raise HTTPException(status_code=400, detail="一次最多只能批量生成 5 章。")


def _chapters_in_range(project_id: int, start_ch: int, end_ch: int) -> list[dict]:
    all_chapters = list_chapters(project_id)
    target = [ch for ch in all_chapters if start_ch <= ch["chapter_number"] <= end_ch]
    target.sort(key=lambda c: c["chapter_number"])
    if not target:
        raise HTTPException(
            status_code=400,
            detail=f"第 {start_ch} 章到第 {end_ch} 章范围内没有章节，请先生成章节目录。",
        )
    return target


@app.post("/api/projects/{project_id}/quality-check-range")
def quality_check_range(project_id: int, payload: QualityCheckRangeRequest):
    get_project_or_404(project_id)
    start_ch = payload.start_chapter
    end_ch = payload.end_chapter
    _validate_chapter_range(start_ch, end_ch)

    target_chapters = _chapters_in_range(project_id, start_ch, end_ch)
    checked: list[dict] = []
    skipped: list[int] = []
    failed: list[int] = []

    for ch in target_chapters:
        num = ch["chapter_number"]
        if not get_chapter_content(ch):
            skipped.append(num)
            continue
        try:
            result = _check_chapter_quality(ch["id"])
            checked.append(result)
        except HTTPException as e:
            _set_chapter_error(ch["id"], f"质量检查失败：{_exception_message(e)}")
            failed.append(num)
        except Exception as e:  # noqa: BLE001
            _set_chapter_error(ch["id"], f"质量检查失败：{e}")
            failed.append(num)

    low_score = [r for r in checked if r.get("score", 100) < payload.score_threshold]
    if checked and not failed:
        message = f"质量检查完成，{len(low_score)} 章低于 {payload.score_threshold} 分"
    elif checked:
        message = f"部分完成：成功 {len(checked)}，跳过 {len(skipped)}，失败 {len(failed)}"
    elif skipped and not failed:
        message = "指定范围内章节均无正文，已全部跳过"
    else:
        message = "质量检查失败"

    return {
        "project_id": project_id,
        "start_chapter": start_ch,
        "end_chapter": end_ch,
        "checked_chapters": checked,
        "skipped_chapters": skipped,
        "failed_chapters": failed,
        "low_score_count": len(low_score),
        "message": message,
    }


@app.post("/api/projects/{project_id}/rewrite-issues")
def rewrite_issues(project_id: int, payload: RewriteIssuesRequest):
    get_project_or_404(project_id)
    start_ch = payload.start_chapter
    end_ch = payload.end_chapter
    threshold = payload.score_threshold
    max_rounds = min(max(1, payload.max_rounds), 2)
    if end_ch - start_ch + 1 > 5:
        raise HTTPException(status_code=400, detail="一次最多只能批量重写 5 章。")

    rewritten: list[int] = []
    skipped: list[int] = []
    failed: list[int] = []

    def chapter_needs_rewrite(ch: dict) -> bool:
        score = ch.get("quality_score")
        report = quality_service.report_from_json(ch.get("quality_report"))
        if score is not None and score < threshold:
            return True
        if report and not report.get("passed", True):
            return True
        return False

    all_chapters = list_chapters(project_id)
    target = [
        ch
        for ch in all_chapters
        if start_ch <= ch["chapter_number"] <= end_ch
        and get_chapter_content(ch)
    ]
    target.sort(key=lambda c: c["chapter_number"])

    candidates: list[dict] = []
    for ch in target:
        needs = chapter_needs_rewrite(ch)
        if not needs and ch.get("quality_status") != "completed":
            try:
                result = _check_chapter_quality(ch["id"])
                needs = result.get("score", 100) < threshold or not result.get("passed", True)
                ch = get_chapter_or_404(ch["id"])
            except HTTPException as e:
                _set_chapter_error(ch["id"], f"一键重写失败：{_exception_message(e)}")
                failed.append(ch["chapter_number"])
                continue
            except Exception as e:  # noqa: BLE001
                _set_chapter_error(ch["id"], f"一键重写失败：{e}")
                failed.append(ch["chapter_number"])
                continue
        if needs and len(candidates) < 5:
            candidates.append(ch)
        elif not needs:
            skipped.append(ch["chapter_number"])

    for _round in range(max_rounds):
        round_any = False
        for ch in candidates:
            fresh = get_chapter_or_404(ch["id"])
            if not chapter_needs_rewrite(fresh):
                continue
            num = fresh["chapter_number"]
            try:
                _rewrite_chapter_content(fresh["id"])
                if num not in rewritten:
                    rewritten.append(num)
                round_any = True
            except HTTPException as e:
                _set_chapter_error(fresh["id"], f"一键重写失败：{_exception_message(e)}")
                if num not in failed:
                    failed.append(num)
            except Exception as e:  # noqa: BLE001
                _set_chapter_error(fresh["id"], f"一键重写失败：{e}")
                if num not in failed:
                    failed.append(num)
        if not round_any:
            break

    if rewritten and not failed:
        message = f"已重写 {len(rewritten)} 章低质量正文。重写完成，请重新进行质量检查。重写后的章节需要重新生成 MP3。"
    elif rewritten:
        message = (
            f"部分完成：重写 {rewritten}，跳过 {skipped}，失败 {failed}。"
            "重写完成，请重新进行质量检查。重写后的章节需要重新生成 MP3。"
        )
    elif skipped and not failed:
        message = "指定范围内章节均达标，无需重写"
    else:
        message = "一键重写失败或无待重写章节"

    return {
        "project_id": project_id,
        "start_chapter": start_ch,
        "end_chapter": end_ch,
        "score_threshold": threshold,
        "max_rounds": max_rounds,
        "rewritten_chapters": rewritten,
        "skipped_chapters": skipped,
        "failed_chapters": failed,
        "message": message,
    }


@app.post("/api/projects/{project_id}/generate-tts-range")
async def generate_tts_range(project_id: int, payload: GenerateTtsRangeRequest):
    get_project_or_404(project_id)
    start_ch = payload.start_chapter
    end_ch = payload.end_chapter
    _validate_chapter_range(start_ch, end_ch)
    assert_valid_tts_params(payload.voice_key, payload.rate)

    target_chapters = _chapters_in_range(project_id, start_ch, end_ch)
    generated: list[int] = []
    skipped: list[int] = []
    failed: list[int] = []

    for ch in target_chapters:
        num = ch["chapter_number"]
        if not get_chapter_content(ch):
            skipped.append(num)
            continue
        try:
            await _do_chapter_tts(ch["id"], payload.voice_key, payload.rate)
            generated.append(num)
        except HTTPException:
            with database.db_cursor() as cur:
                cur.execute(
                    "UPDATE chapters SET tts_status = ?, updated_at = ? WHERE id = ?",
                    ("failed", now(), ch["id"]),
                )
            failed.append(num)
        except Exception:  # noqa: BLE001
            with database.db_cursor() as cur:
                cur.execute(
                    "UPDATE chapters SET tts_status = ?, updated_at = ? WHERE id = ?",
                    ("failed", now(), ch["id"]),
                )
            failed.append(num)

    if generated and not failed:
        message = "批量配音完成"
    elif generated:
        message = f"部分完成：成功 {generated}，跳过 {skipped}，失败 {failed}"
    elif skipped and not failed:
        message = "指定范围内章节均无正文，已全部跳过"
    else:
        message = "批量配音失败"

    return {
        "project_id": project_id,
        "start_chapter": start_ch,
        "end_chapter": end_ch,
        "generated_chapters": generated,
        "skipped_chapters": skipped,
        "failed_chapters": failed,
        "voice_key": payload.voice_key,
        "rate": payload.rate,
        "message": message,
    }


# --------------------------------------------------------------------------- #
# 下载单章文件
# --------------------------------------------------------------------------- #
@app.get("/api/chapters/{chapter_id}/download/txt")
def download_chapter_txt(chapter_id: int):
    chapter = get_chapter_or_404(chapter_id)
    content = get_chapter_content(chapter)
    fname = f"chapter_{chapter['chapter_number']:03d}.txt"
    return Response(
        content=content.encode("utf-8"),
        media_type="text/plain; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{fname}"'},
    )


@app.get("/api/chapters/{chapter_id}/download/mp3")
def download_chapter_mp3(chapter_id: int):
    chapter = get_chapter_or_404(chapter_id)
    path = chapter.get("audio_path")
    if not path or not Path(path).is_file():
        raise HTTPException(status_code=404, detail="尚未生成配音")
    data = Path(path).read_bytes()
    fname = f"chapter_{chapter['chapter_number']:03d}.mp3"
    return Response(
        content=data,
        media_type="audio/mpeg",
        headers={"Content-Disposition": f'attachment; filename="{fname}"'},
    )


# --------------------------------------------------------------------------- #
# 项目级导出接口
# --------------------------------------------------------------------------- #
def _attach(fname: str) -> dict:
    return {"Content-Disposition": f'attachment; filename="{fname}"'}


@app.get("/api/projects/{project_id}/export/txt")
def export_txt(project_id: int):
    project = get_project_or_404(project_id)
    chapters = list_chapters(project_id)
    _require_exportable(project, chapters)
    lang = _project_language(project)
    data = exporter.export_full_txt(project, chapters)
    return Response(
        data,
        media_type="text/plain; charset=utf-8",
        headers=_attach(f"project_{project_id}_{lang}_full.txt"),
    )


@app.get("/api/projects/{project_id}/export/chapters-zip")
def export_chapters_zip(project_id: int):
    project = get_project_or_404(project_id)
    chapters = list_chapters(project_id)
    _require_exportable(project, chapters)
    data = exporter.export_chapters_zip(project, chapters)
    return Response(
        data,
        media_type="application/zip",
        headers=_attach(f"project_{project_id}_chapters.zip"),
    )


@app.get("/api/projects/{project_id}/export/audio-zip")
def export_audio_zip(project_id: int):
    get_project_or_404(project_id)
    chapters = list_chapters(project_id)
    data, count = exporter.export_audio_zip(chapters)
    if count == 0:
        raise HTTPException(status_code=400, detail=EXPORT_EMPTY_MSG)
    return Response(
        data,
        media_type="application/zip",
        headers=_attach(f"project_{project_id}_audio.zip"),
    )


@app.get("/api/projects/{project_id}/export/full-zip")
def export_full_zip(project_id: int):
    project = get_project_or_404(project_id)
    chapters = list_chapters(project_id)
    _require_exportable(project, chapters)
    lang = _project_language(project)
    data = exporter.export_full_zip(project, chapters)
    return Response(
        data,
        media_type="application/zip",
        headers=_attach(f"project_{project_id}_{lang}_full.zip"),
    )


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/")
def root():
    return {"app": "AI 都市小说视频工厂", "version": "v0.3-dev", "status": "ok"}


if __name__ == "__main__":
    import uvicorn

    database.ensure_schema()
    exporter.ensure_output_dirs()
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
