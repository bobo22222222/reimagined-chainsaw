"""导出服务：TXT / 章节 ZIP / MP3 ZIP / 完整项目 ZIP（v0.3 统一读取 chapters.content）。"""
import io
import zipfile
from pathlib import Path
from typing import Optional

from content_utils import get_chapter_content
from language_profiles import get_profile, normalize_language

BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "output"


def ensure_output_dirs() -> None:
    """启动时创建 output 及子目录（Windows / Unix 兼容）。"""
    for sub in ["", "chapters", "audio", "exports"]:
        path = OUTPUT_DIR / sub if sub else OUTPUT_DIR
        path.mkdir(parents=True, exist_ok=True)


def project_output_dir(project_id: int) -> Path:
    """单项目音频输出目录。"""
    path = OUTPUT_DIR / f"project_{project_id}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _safe_name(name: str) -> str:
    name = name or "project"
    for ch in '\\/:*?"<>|':
        name = name.replace(ch, "_")
    return name.strip() or "project"


def _path_exists(path: Optional[str]) -> bool:
    if not path:
        return False
    return Path(path).is_file()


def _project_lang(project: dict) -> str:
    return normalize_language(project.get("language"))


def _chapter_file_prefix(ch: dict, lang: str) -> str:
    num = ch.get("chapter_number")
    title = _safe_name(ch.get("title") or f"chapter_{num}")
    profile = get_profile(lang)
    if lang == "en":
        return f"chapters/Chapter_{num:03d}_{title}.txt"
    if lang == "es":
        return f"chapters/Capitulo_{num:03d}_{title}.txt"
    return f"chapters/第{num:03d}章_{title}.txt"


def has_exportable_content(project: dict, chapters: list[dict]) -> bool:
    """是否存在可导出的文案内容。"""
    if (project.get("story_bible") or "").strip():
        return True
    if (project.get("outline") or "").strip():
        return True
    if not chapters:
        return False
    return any(get_chapter_content(ch) for ch in chapters)


def count_existing_audio(chapters: list[dict]) -> int:
    return sum(1 for ch in chapters if _path_exists(ch.get("audio_path")))


def build_full_novel_text(project: dict, chapters: list[dict]) -> str:
    lang = _project_lang(project)
    profile = get_profile(lang)
    placeholder = profile["no_content_placeholder"]
    parts = [f"《{project.get('title') or project.get('project_name')}》", ""]
    for ch in chapters:
        num = ch.get("chapter_number")
        title = ch.get("title") or profile["chapter_name"].format(n=num)
        if lang == "en":
            parts.append(f"Chapter {num} {title}")
        elif lang == "es":
            parts.append(f"Capítulo {num} {title}")
        else:
            parts.append(f"第{num}章 {title}")
        parts.append("")
        parts.append(get_chapter_content(ch) or placeholder)
        parts.append("")
        parts.append("")
    return "\n".join(parts)


def export_full_txt(project: dict, chapters: list[dict]) -> bytes:
    return build_full_novel_text(project, chapters).encode("utf-8")


def export_chapters_zip(project: dict, chapters: list[dict]) -> bytes:
    lang = _project_lang(project)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for ch in chapters:
            zf.writestr(_chapter_file_prefix(ch, lang), get_chapter_content(ch))
    return buf.getvalue()


def export_audio_zip(chapters: list[dict]) -> tuple[bytes, int]:
    buf = io.BytesIO()
    added = 0
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for ch in chapters:
            path = ch.get("audio_path")
            if _path_exists(path):
                num = ch.get("chapter_number")
                zf.write(path, f"audio/第{num:03d}章.mp3")
                added += 1
    return buf.getvalue(), added


def export_full_zip(project: dict, chapters: list[dict]) -> bytes:
    """完整项目 ZIP：story_bible / outline / full_novel_{lang} / chapters / audio。"""
    lang = _project_lang(project)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("story_bible.txt", project.get("story_bible") or "")
        zf.writestr("outline.txt", project.get("outline") or "")
        zf.writestr(f"full_novel_{lang}.txt", build_full_novel_text(project, chapters))
        for ch in chapters:
            zf.writestr(_chapter_file_prefix(ch, lang), get_chapter_content(ch))
            apath = ch.get("audio_path")
            if _path_exists(apath):
                num = ch.get("chapter_number")
                zf.write(apath, f"audio/第{num:03d}章.mp3")
    return buf.getvalue()
