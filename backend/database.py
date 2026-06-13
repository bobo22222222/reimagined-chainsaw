"""SQLite 数据库初始化、自动迁移与连接管理。"""
import sqlite3
from contextlib import contextmanager
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "app.db"

# 老库可能缺失的字段 → ALTER TABLE 定义（仅 ADD COLUMN，重复添加会跳过）
PROJECT_MIGRATIONS: dict[str, str] = {
    "status": "TEXT DEFAULT 'created'",
}

CHAPTER_MIGRATIONS: dict[str, str] = {
    "content": "TEXT",
    "content_en": "TEXT",
    "content_es": "TEXT",
    "content_ja": "TEXT",
    "audio_path": "TEXT",
    "srt_path": "TEXT",
    "tts_status": "TEXT DEFAULT 'pending'",
    "srt_status": "TEXT DEFAULT 'pending'",
    "quality_score": "INTEGER",
    "quality_report": "TEXT",
    "quality_status": "TEXT DEFAULT 'pending'",
    "quality_checked_at": "TEXT",
    "last_error": "TEXT",
    "last_error_at": "TEXT",
    "generation_retry_reason": "TEXT",
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_name TEXT NOT NULL,
    title TEXT NOT NULL,
    target_words INTEGER,
    chapter_words INTEGER,
    language TEXT,
    generate_tts INTEGER DEFAULT 1,
    generate_srt INTEGER DEFAULT 1,

    genre TEXT,
    protagonist_type TEXT,
    opening_hook TEXT,
    main_conflict TEXT,
    antagonist_type TEXT,
    plot_style TEXT,
    emotion_direction TEXT,
    tone TEXT,
    ending_type TEXT,
    target_audience TEXT,
    custom_setting TEXT,

    story_bible TEXT,
    outline TEXT,
    status TEXT DEFAULT 'created',
    created_at TEXT,
    updated_at TEXT
);

CREATE TABLE IF NOT EXISTS chapters (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    chapter_number INTEGER NOT NULL,
    title TEXT,
    outline TEXT,

    content_cn TEXT,
    content_en TEXT,
    content_es TEXT,
    content_ja TEXT,

    summary TEXT,
    word_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'pending',

    audio_path TEXT,
    srt_path TEXT,
    tts_status TEXT DEFAULT 'pending',
    srt_status TEXT DEFAULT 'pending',

    created_at TEXT,
    updated_at TEXT,

    FOREIGN KEY(project_id) REFERENCES projects(id)
);

CREATE TABLE IF NOT EXISTS tts_segments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chapter_id INTEGER NOT NULL,
    segment_index INTEGER,
    text TEXT,
    audio_path TEXT,
    duration_seconds REAL,
    start_time REAL,
    end_time REAL,
    status TEXT DEFAULT 'pending',
    FOREIGN KEY(chapter_id) REFERENCES chapters(id)
);
"""


def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


@contextmanager
def db_cursor():
    """提供一个自动提交 / 关闭的游标上下文。"""
    conn = get_connection()
    try:
        cur = conn.cursor()
        yield cur
        conn.commit()
    finally:
        conn.close()


def _table_columns(conn: sqlite3.Connection, table: str) -> set[str]:
    cur = conn.execute(f"PRAGMA table_info({table})")
    return {row[1] for row in cur.fetchall()}


def _migrate_columns(conn: sqlite3.Connection, table: str, migrations: dict[str, str]) -> None:
    """为已存在的表补字段；字段已存在则跳过。"""
    if table not in {
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
    }:
        return
    existing = _table_columns(conn, table)
    for col, col_def in migrations.items():
        if col not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {col} {col_def}")


def init_db() -> None:
    """创建所有数据表（若不存在）。"""
    conn = get_connection()
    try:
        conn.executescript(SCHEMA)
        conn.commit()
    finally:
        conn.close()


def ensure_schema() -> None:
    """创建表 + 自动迁移缺失字段，启动时调用。"""
    init_db()
    conn = get_connection()
    try:
        _migrate_columns(conn, "projects", PROJECT_MIGRATIONS)
        _migrate_columns(conn, "chapters", CHAPTER_MIGRATIONS)
        conn.commit()
    finally:
        conn.close()


# 兼容旧调用
migrate_db = ensure_schema
