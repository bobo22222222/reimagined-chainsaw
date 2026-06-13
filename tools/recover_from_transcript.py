"""从 Cursor agent transcript 恢复 Write/StrReplace 到目标项目目录。"""
from __future__ import annotations

import json
import re
from pathlib import Path

TRANSCRIPT = Path(
    r"C:\Users\12834\.cursor\projects"
    r"\C-Users-12834-AppData-Local-Temp-186c1159-84bb-4c0b-8628-b380a9c64111-ai-urban-novel-tts"
    r"\agent-transcripts\d7b56ce2-8f06-46d6-9c27-48ff10a6a006"
    r"\d7b56ce2-8f06-46d6-9c27-48ff10a6a006.jsonl"
)
TARGET_ROOT = Path(r"C:\Users\12834\Documents\ai-urban-novel-tts")
OLD_ROOT = Path(
    r"C:\Users\12834\AppData\Local\Temp"
    r"\186c1159-84bb-4c0b-8628-b380a9c64111\ai-urban-novel-tts"
)

BACKEND_FILES = {
    "database.py",
    "models.py",
    "deepseek_client.py",
    "prompts.py",
    "tts_service.py",
    "exporter.py",
    "main.py",
    "validators.py",
    "quality_service.py",
    "language_profiles.py",
    "content_utils.py",
    "outline_utils.py",
    "requirements.txt",
}


def rel_path(raw: str) -> Path | None:
    p = raw.replace("\\", "/")
    for root in (OLD_ROOT, TARGET_ROOT):
        prefix = str(root).replace("\\", "/")
        if p.startswith(prefix):
            return Path(p[len(prefix) :].lstrip("/"))
    if "/backend/" in p:
        return Path("backend") / p.split("/backend/", 1)[1]
    if "/frontend/" in p:
        return Path("frontend") / p.split("/frontend/", 1)[1]
    if "/scripts/" in p:
        return Path("scripts") / p.split("/scripts/", 1)[1]
    return None


def apply_str_replace(text: str, old: str, new: str) -> str:
    if old not in text:
        return text
    return text.replace(old, new, 1)


def main() -> None:
    files: dict[str, str] = {}
    ops: list[tuple[str, str, Path]] = []

    with TRANSCRIPT.open(encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = obj.get("message", {})
            for part in msg.get("content", []):
                if part.get("type") != "tool_use":
                    continue
                name = part.get("name")
                inp = part.get("input", {})
                path = inp.get("path", "")
                rel = rel_path(path)
                if not rel:
                    continue
                key = rel.as_posix()
                if name == "Write" and "contents" in inp:
                    files[key] = inp["contents"]
                    ops.append(("write", key, rel))
                elif name == "StrReplace" and all(k in inp for k in ("old_string", "new_string")):
                    if key not in files:
                        continue
                    files[key] = apply_str_replace(
                        files[key], inp["old_string"], inp["new_string"]
                    )
                    ops.append(("patch", key, rel))

    written = 0
    for key, content in files.items():
        rel = Path(key)
        if rel.parts[0] == "backend" and rel.name not in BACKEND_FILES:
            continue
        if rel.parts[0] not in ("backend", "scripts", "frontend"):
            continue
        out = TARGET_ROOT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(content, encoding="utf-8", newline="\n")
        written += 1
        print(f"WROTE {out} ({len(content)} chars)")

    report = TARGET_ROOT / "mvp_test_output" / "RECOVER_REPORT.txt"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(
        "\n".join(
            [
                "Transcript recovery report",
                f"Transcript: {TRANSCRIPT}",
                f"Files recovered: {written}",
                "",
                *[f"  {k}" for k in sorted(files.keys()) if k.startswith("backend/")],
            ]
        ),
        encoding="utf-8",
    )
    print(f"Report: {report}")


if __name__ == "__main__":
    main()
