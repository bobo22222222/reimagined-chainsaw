"""章节质量检查：规则引擎 + DeepSeek 语义评估。"""
import json
import re
from typing import Any

from content_utils import measure_content_length
from language_profiles import judge_chapter_length
from validators import check_urban_generated_content

META_PHRASES = (
    "本章讲述",
    "接下来",
    "上一章",
    "下一章",
    "各位看官",
    "话说",
    "书接上文",
    "且听下回",
)

FORBIDDEN_GENRE_WORDS = ()  # deprecated; use validators.check_urban_generated_content


def _deduct(score: int, amount: int) -> int:
    return max(0, min(100, score - amount))


def run_rule_checks(
    content: str,
    chapter_outline: str,
    target_words: int,
    language: str = "zh",
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """本地规则检查，不消耗 API。返回 (issues, length_meta)。"""
    issues: list[dict[str, Any]] = []
    text = (content or "").strip()
    length_meta: dict[str, Any] = {"value": 0, "unit": "字", "judgment": "正常", "status": "正常"}

    if not text:
        issues.append(
            {
                "code": "empty_content",
                "severity": "error",
                "message": "章节正文为空，无法通过质量检查。",
            }
        )
        return issues, length_meta, length_meta

    wc = measure_content_length(text, language)
    length_judged = judge_chapter_length(wc, language, target_words)
    length_meta = {
        "value": wc,
        "unit": length_judged["unit"],
        "judgment": length_judged["judgment"],
        "status": length_judged["status"],
    }
    if length_judged.get("severity") and length_judged.get("message"):
        issues.append(
            {
                "code": length_judged["code"],
                "severity": length_judged["severity"],
                "message": length_judged["message"],
            }
        )

    for phrase in META_PHRASES:
        if phrase in text:
            issues.append(
                {
                    "code": "meta_phrase",
                    "severity": "error",
                    "message": f"出现说明性/meta 用语「{phrase}」，不适合旁白朗读。",
                }
            )

    for word in check_urban_generated_content(text, language):
        issues.append(
            {
                "code": "forbidden_genre",
                "severity": "error",
                "message": f"出现非都市题材词「{word}」，与项目设定冲突。",
            }
        )

    paragraphs = [p.strip() for p in re.split(r"\n+", text) if p.strip()]
    if paragraphs:
        long_paras = [p for p in paragraphs if len(re.sub(r"\s", "", p)) > 220]
        if long_paras:
            issues.append(
                {
                    "code": "long_paragraph",
                    "severity": "warning",
                    "message": f"有 {len(long_paras)} 段过长（>220 字），建议拆段以便配音。",
                }
            )

        opening = paragraphs[0]
        if len(re.sub(r"\s", "", opening)) > 180 and "？" not in opening and "！" not in opening:
            issues.append(
                {
                    "code": "slow_opening",
                    "severity": "warning",
                    "message": "开头第一段偏长且缺少冲突感，建议更快进入矛盾。",
                }
            )

        ending = paragraphs[-1]
        if ending and not re.search(r"[？！…]$", ending.rstrip("」」")):
            issues.append(
                {
                    "code": "weak_ending_hook",
                    "severity": "warning",
                    "message": "结尾悬念感偏弱，建议加强钩子或反转。",
                }
            )

    if chapter_outline:
        outline_keywords = re.findall(r"[\u4e00-\u9fff]{2,6}", chapter_outline[:200])
        hit = sum(1 for kw in outline_keywords[:8] if kw in text)
        if outline_keywords and hit == 0:
            issues.append(
                {
                    "code": "outline_mismatch",
                    "severity": "warning",
                    "message": "正文与章节大纲关键词重合度低，可能偏离本章剧情目标。",
                }
            )

    return issues, length_meta


def parse_llm_quality_json(raw: str) -> dict[str, Any]:
    """从模型输出中提取 JSON。"""
    text = (raw or "").strip()
    if not text:
        return {}
    # 尝试直接解析
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # 提取 ```json ... ``` 或 { ... }
    m = re.search(r"\{[\s\S]*\}", text)
    if not m:
        return {}
    try:
        return json.loads(m.group(0))
    except json.JSONDecodeError:
        return {}


def merge_quality_report(
    rule_issues: list[dict[str, Any]],
    llm_data: dict[str, Any],
    length_meta: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """合并规则与 LLM 结果，计算最终分数。"""
    score = 100
    for issue in rule_issues:
        sev = issue.get("severity", "warning")
        code = issue.get("code", "")
        if sev == "error":
            score = _deduct(score, 15)
        elif sev == "warning":
            deduct = 10 if code in ("length_very_long", "length_short") else 8
            score = _deduct(score, deduct)
        else:
            score = _deduct(score, 3)

    llm_issues = llm_data.get("issues") or []
    if isinstance(llm_issues, list):
        for issue in llm_issues:
            if not isinstance(issue, dict):
                continue
            sev = issue.get("severity", "warning")
            if sev == "error":
                score = _deduct(score, 12)
            elif sev == "warning":
                score = _deduct(score, 6)
            else:
                score = _deduct(score, 2)

    llm_score = llm_data.get("score")
    if isinstance(llm_score, (int, float)):
        score = int(round((score + float(llm_score)) / 2))

    all_issues = list(rule_issues)
    for issue in llm_issues:
        if isinstance(issue, dict) and issue.get("message"):
            all_issues.append(
                {
                    "code": issue.get("code") or "llm_issue",
                    "severity": issue.get("severity") or "warning",
                    "message": issue["message"],
                }
            )

    suggestions = llm_data.get("suggestions") or []
    if not isinstance(suggestions, list):
        suggestions = []

    summary = llm_data.get("summary") or ""
    if not summary and all_issues:
        summary = f"发现 {len(all_issues)} 项待改进问题。"

    passed = score >= 70 and not any(i.get("severity") == "error" for i in all_issues)

    result: dict[str, Any] = {
        "score": score,
        "passed": passed,
        "issues": all_issues,
        "suggestions": [str(s) for s in suggestions if s],
        "summary": str(summary),
    }
    if length_meta:
        result["length"] = length_meta
    return result


def report_to_json(report: dict[str, Any]) -> str:
    return json.dumps(report, ensure_ascii=False)


def report_from_json(raw: str | None) -> dict[str, Any] | None:
    if not raw:
        return None
    try:
        data = json.loads(raw)
        return data if isinstance(data, dict) else None
    except json.JSONDecodeError:
        return None
