"""Pydantic 请求 / 响应模型。"""
from typing import Optional
from pydantic import BaseModel, field_validator

from language_profiles import ALLOWED_LANGUAGES, normalize_language


class ProjectCreate(BaseModel):
    project_name: str
    title: str
    target_words: int = 10000
    chapter_words: int = 3000
    language: str = "zh"
    generate_tts: bool = True

    @field_validator("language", mode="before")
    @classmethod
    def _norm_lang(cls, v: str) -> str:
        code = normalize_language(v)
        if code not in ALLOWED_LANGUAGES:
            raise ValueError("language 必须是 zh / en / es / ja")
        return code


class UrbanSettings(BaseModel):
    genre: Optional[str] = None
    protagonist_type: Optional[str] = None
    opening_hook: Optional[str] = None
    main_conflict: Optional[str] = None
    antagonist_type: Optional[str] = None
    plot_style: Optional[str] = None
    emotion_direction: Optional[str] = None
    tone: Optional[str] = None
    ending_type: Optional[str] = None
    target_audience: Optional[str] = None
    custom_setting: Optional[str] = None


class ProjectUpdate(BaseModel):
    project_name: Optional[str] = None
    title: Optional[str] = None
    target_words: Optional[int] = None
    chapter_words: Optional[int] = None
    language: Optional[str] = None
    generate_tts: Optional[bool] = None
    genre: Optional[str] = None
    protagonist_type: Optional[str] = None
    opening_hook: Optional[str] = None
    main_conflict: Optional[str] = None
    antagonist_type: Optional[str] = None
    plot_style: Optional[str] = None
    emotion_direction: Optional[str] = None
    tone: Optional[str] = None
    ending_type: Optional[str] = None
    target_audience: Optional[str] = None
    custom_setting: Optional[str] = None


class ApplyTemplate(BaseModel):
    template_key: str


class ChapterUpdate(BaseModel):
    title: Optional[str] = None
    outline: Optional[str] = None
    content: Optional[str] = None
    summary: Optional[str] = None


class TTSRequest(BaseModel):
    voice_key: str = "zh_male"
    rate: str = "+0%"


class GenerateFirst3Request(BaseModel):
    voice_key: str = "zh_male"
    rate: str = "+0%"


class GenerateChapterRangeRequest(BaseModel):
    start_chapter: int
    end_chapter: int
    voice_key: str = "zh_male"
    rate: str = "+0%"


class GenerateTtsRangeRequest(BaseModel):
    start_chapter: int
    end_chapter: int
    voice_key: str = "zh_male"
    rate: str = "+0%"


class QualityCheckRangeRequest(BaseModel):
    start_chapter: int
    end_chapter: int
    score_threshold: int = 70


class RewriteIssuesRequest(BaseModel):
    start_chapter: int = 1
    end_chapter: int = 999
    score_threshold: int = 70
    max_rounds: int = 1
