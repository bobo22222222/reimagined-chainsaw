"""都市长视频小说 Prompt 模板与都市爆款模板数据。

v0.3：单项目单语言，所有 Prompt 从 project.language 读取 language_profiles。
"""

from language_profiles import (
    format_length_guidance_for_rewrite,
    format_length_prompt_line,
    get_profile,
    language_directive,
    normalize_language,
    resolve_chapter_length,
)

URBAN_GUARD = """硬性限制：
1. 只能写都市现代背景。
2. 不允许出现修仙、玄幻、穿越、重生、系统、末日、异能、魔法、古代设定。
3. 故事必须适合长视频旁白。
4. 整体风格要强冲突、强悬念、强反转。"""

URBAN_GUARD_EN = """Hard constraints:
1. Urban/modern setting only.
2. No fantasy, cultivation, time travel, rebirth, system, apocalypse, superpowers, magic, or ancient settings.
3. Must suit long-form video narration.
4. Strong conflict, suspense, and twists throughout."""


def _guard_for(language: str) -> str:
    return URBAN_GUARD if normalize_language(language) == "zh" else URBAN_GUARD_EN


def _outline_example(language: str, n: int = 1) -> str:
    profile = get_profile(language)
    header = profile["outline_header"].format(n=n)
    f1, f2, f3, f4 = profile["outline_fields"]
    n2 = n + 1
    header2 = profile["outline_header"].format(n=n2)
    return (
        f"{header}章节标题\n{f1}\n{f2}\n{f3}\n{f4}\n\n"
        f"{header2}章节标题\n{f1}\n{f2}\n{f3}\n{f4}"
    )


def build_bible_prompt(p: dict) -> str:
    lang = normalize_language(p.get("language"))
    profile = get_profile(lang)
    directive = language_directive(profile)
    guard = _guard_for(lang)
    return f"""{profile['system']}

请根据以下用户选择，设计一部适合长视频解说的都市小说总设定。

{directive}

小说标题：{p.get('title') or ''}
目标字数：{p.get('target_words') or ''}
题材类型：{p.get('genre') or ''}
主角身份：{p.get('protagonist_type') or ''}
故事开局：{p.get('opening_hook') or ''}
主要冲突：{p.get('main_conflict') or ''}
反派类型：{p.get('antagonist_type') or ''}
爽点类型：{p.get('plot_style') or ''}
情感方向：{p.get('emotion_direction') or ''}
文风选择：{p.get('tone') or ''}
结局方向：{p.get('ending_type') or ''}
目标受众：{p.get('target_audience') or ''}
用户补充：{p.get('custom_setting') or ''}

{guard}
5. 开头三秒必须有强钩子。

请输出以下内容（全部使用 {profile['label']}）：
1. 故事简介
2. 开头三秒钩子
3. 主角设定
4. 主要配角设定
5. 反派设定
6. 人物关系
7. 主线冲突
8. 情感线设计
9. 爽点设计
10. 伏笔设计
11. 分卷结构
12. 结局方向
13. 适合长视频分集的节奏说明"""


def build_outline_prompt(
    story_bible: str,
    target_words: int,
    chapter_words: int,
    chapter_count: int,
    language: str = "zh",
) -> str:
    lang = normalize_language(language)
    profile = get_profile(lang)
    directive = language_directive(profile)
    guard = _guard_for(lang)
    example = _outline_example(lang)
    return f"""请根据以下都市小说总设定，生成章节目录。

{directive}

小说总设定：
{story_bible}

目标字数：{target_words}
每章字数：{chapter_words}
预计章节数：{chapter_count}

{guard}
3. 每章必须推动主线。
4. 每章都要有冲突、反转或悬念。
5. 不要重复剧情。
6. 每章结尾都要适合引导观众继续观看。
7. 全部使用 {profile['label']} 输出。

请严格按以下格式输出（章节标题行必须可被程序识别，例如「第1章：」「Chapter 1:」「Capítulo 1:」）：

{example}"""


def build_missing_chapters_prompt(
    story_bible: str,
    target_words: int,
    chapter_words: int,
    chapter_count: int,
    missing_numbers: list[int],
    language: str = "zh",
) -> str:
    lang = normalize_language(language)
    profile = get_profile(lang)
    directive = language_directive(profile)
    nums = "、".join(str(n) for n in missing_numbers)
    example = _outline_example(lang, missing_numbers[0] if missing_numbers else 1)
    return f"""请根据以下都市小说总设定，仅补写缺失的章节目录条目。

{directive}

小说总设定：
{story_bible}

全书预计 {chapter_count} 章，每章约 {chapter_words} 字，目标总字数 {target_words}。

请只为以下章节生成目录（不要重复其他章节）：
第 {nums} 章

硬性限制：
1. 只能写都市现代背景。
2. 每章必须推动主线，与前后章节衔接。
3. 全部使用 {profile['label']} 输出。
4. 严格按格式输出，章节行必须包含章节编号。

格式示例：
{example}"""


def build_chapter_prompt(
    chapter_number: int,
    story_bible: str,
    outline: str,
    chapter_outline: str,
    previous_summary: str,
    chapter_words: int,
    language: str = "zh",
) -> str:
    lang = normalize_language(language)
    profile = get_profile(lang)
    directive = language_directive(profile)
    length_line = format_length_prompt_line(lang, chapter_words)
    ja_extra = ""
    if lang == "ja":
        ja_extra = """
14. 日本語の場合の追加制約：
- 場面数を2〜3個に絞る
- 心理描写を繰り返さない
- 同じ情報を別表現で反復しない
- 会話を長くしすぎない
- 説明よりも展開を優先する"""
    return f"""你正在写一部都市长视频小说文案的第 {chapter_number} 章。

{directive}

小说总设定：
{story_bible}

全书章节目录：
{outline}

当前章节大纲：
{chapter_outline}

前文摘要：
{previous_summary or '（这是第一章，没有前文）'}

本章要求：
{length_line}
2. 开头直接进入冲突，不要铺垫太久。
3. 保持短视频强悬念、强情绪、强反转。
4. 适合 AI 配音旁白。
5. 每段不要太长，方便朗读与配音。
6. 不要出现说明性文字或 meta 用语。
7. 不要重复前文剧情。
8. 人物性格必须和总设定一致。
9. 结尾必须留下悬念。
10. 语言要口语化、画面感强。
11. 只能写都市现代背景。
12. 不允许出现修仙、玄幻、穿越、重生、系统爽文、末日、异能、魔法、古代设定。
13. 请直接使用 {profile['label']} 创作，不要翻译，不要混用其他语言，不要输出说明文字。{ja_extra}

请直接输出正文。"""


def build_chapter_strict_retry_prompt(
    chapter_number: int,
    story_bible: str,
    outline: str,
    chapter_outline: str,
    previous_summary: str,
    chapter_words: int,
    language: str = "zh",
    violation_hints: list[str] | None = None,
) -> str:
    lang = normalize_language(language)
    profile = get_profile(lang)
    hints = "、".join(violation_hints or []) or "非都市设定"
    base = build_chapter_prompt(
        chapter_number,
        story_bible,
        outline,
        chapter_outline,
        previous_summary,
        chapter_words,
        lang,
    )
    return f"""{base}

【重要：上一次生成未通过都市题材校验，请重写】
上次命中问题：{hints}

必须遵守：
1. 只能是现代都市背景（当代城市、公司、家庭、职场、商业、法律、警匪等）。
2. 禁止修仙、玄幻、穿越、重生、系统爽文、绑定系统、末日、丧尸、魔法、异能、宗门、修炼、飞升。
3. 可以使用「公司系统、监控系统、银行系统、内部系统」等现代设施用语。
4. 不要写「主角穿越/重生/获得神级系统/灵气复苏」等情节。
5. 全程使用 {profile['label']}，不要翻译，不要混用语言，不要输出解释。
6. 直接输出重写后的章节正文。"""


def build_chapter_ja_extreme_length_retry_prompt(
    chapter_number: int,
    story_bible: str,
    outline: str,
    chapter_outline: str,
    previous_summary: str,
    chapter_words: int,
    previous_content: str,
    previous_length: int,
) -> str:
    """日语章节极端超长（>6000 字符）时的压缩重写 Prompt（仅 ja）。"""
    profile = get_profile("ja")
    return f"""前回の出力は長すぎました（約 {previous_length} 文字）。
同じ第 {chapter_number} 章の内容を、物語の流れを保ったまま、より簡潔な日本語で書き直してください。

{language_directive(profile)}

条件：
1. 2000〜3500文字程度を目安にする
2. 長くても4500文字以内を強く意識する
3. 場面数は2〜3個に絞る
4. 同じ心理描写や説明を繰り返さない
5. 都市現代ドラマとして自然に書く
6. 中国語や英語を混ぜない
7. 解説や注釈は書かず、本文だけ出力する

小说总设定：
{story_bible}

全书章节目录：
{outline}

当前章节大纲：
{chapter_outline}

前文摘要：
{previous_summary or '（这是第一章，没有前文）'}

前回の長すぎる正文（参考用・そのままコピーしない）：
{previous_content[:4000]}{"…" if len(previous_content) > 4000 else ""}

请直接输出压缩后的日语正文。"""


def build_summary_prompt(chapter_content: str, language: str = "zh") -> str:
    lang = normalize_language(language)
    profile = get_profile(lang)
    return f"""请总结以下章节内容，用于后续章节保持上下文一致。
正文语言为 {profile['label']}，摘要也请使用 {profile['label']}。

要求输出：
1. 本章摘要
2. 人物状态变化
3. 新增设定
4. 埋下的伏笔
5. 下一章衔接点

章节正文：
{chapter_content}"""


def build_quality_check_prompt(
    chapter_number: int,
    story_bible: str,
    chapter_outline: str,
    content: str,
    target_words: int,
    language: str = "zh",
) -> str:
    profile = get_profile(language)
    length_spec = resolve_chapter_length(language, target_words)
    length_desc = (
        f"推荐约 {length_spec['target_min']}–{length_spec['target_max']} "
        f"{length_spec.get('unit_label_zh', '字')}（可接受范围 "
        f"{length_spec['acceptable_min']}–{length_spec['acceptable_max']}），以剧情完整为先"
    )
    return f"""你是都市长视频小说文案的质量审核编辑。

请检查以下 {profile['label']} 都市小说章节。
正文是 {profile['label']}，但质量报告请用中文输出。

请评估第 {chapter_number} 章正文质量。章节长度参考：{length_desc}，轻微浮动可接受，明显过长需扣分。

小说总设定（节选）：
{(story_bible or '')[:2000]}

本章大纲：
{chapter_outline or '（无）'}

章节正文：
{content}

评估维度：
1. 开头是否快速进入冲突（强钩子）
2. 是否符合本章大纲与总设定
3. 悬念、反转、情绪是否足够
4. 是否适合 AI 旁白朗读（口语化、画面感、无说明性/meta 用语）
5. 结尾是否有继续观看的钩子
6. 是否保持都市现代背景，无非都市元素
7. 正文是否全程使用 {profile['label']}，无混用语言

请严格输出 JSON（不要 markdown 代码块），格式：
{{
  "score": 0到100的整数,
  "summary": "一句话总评（中文）",
  "issues": [
    {{"code": "issue_code", "severity": "error|warning|info", "message": "具体问题（中文）"}}
  ],
  "suggestions": ["改写建议1（中文）", "改写建议2（中文）"]
}}"""


def build_rewrite_prompt(
    chapter_number: int,
    story_bible: str,
    outline: str,
    chapter_outline: str,
    previous_summary: str,
    content: str,
    quality_report: str,
    target_words: int,
    language: str = "zh",
) -> str:
    profile = get_profile(language)
    length_hint = format_length_guidance_for_rewrite(language, target_words)
    return f"""你是专业都市长视频小说文案作者。请根据质量检查报告，重写第 {chapter_number} 章正文。

请直接用 {profile['label']} 重写正文。
不要翻译。
不要混用其他语言。
不要输出解释。
只输出重写后的正文。

小说总设定：
{story_bible}

全书章节目录：
{outline}

当前章节大纲：
{chapter_outline}

前文摘要：
{previous_summary or '（这是第一章，没有前文）'}

当前正文（待改进）：
{content}

质量检查报告：
{quality_report}

重写要求：
1. 保留本章核心剧情与人物关系，不要写偏。
2. 针对报告中的问题逐项改进。
3. {length_hint}
4. 开头直接进入冲突，结尾留悬念。
5. 适合 AI 配音旁白，段落不宜过长。
6. 不要出现说明性/meta 用语。
7. 只能写都市现代背景，禁止修仙/玄幻/穿越/重生/系统爽文/末日等。
8. 全程使用 {profile['label']}。"""


# 都市爆款模板（与前端 TemplateButtons 保持一致；apply-template 接口使用）
TEMPLATES = {
    "tycoon_revenge": {
        "name": "富豪归来复仇",
        "genre": "都市复仇",
        "protagonist_type": "隐藏身份的神秘富豪",
        "opening_hook": "家族宴会上被赶出门",
        "main_conflict": "家族羞辱",
        "antagonist_type": "伪善兄弟",
        "plot_style": "身份反转",
        "emotion_direction": "主角彻底放下过去",
        "tone": "短视频强悬念",
        "ending_type": "主角夺回一切",
        "target_audience": "男性爽文观众",
    },
    "divorce_reveal": {
        "name": "离婚后身份曝光",
        "genre": "婚姻背叛",
        "protagonist_type": "被妻子背叛的丈夫",
        "opening_hook": "主角被妻子提出离婚",
        "main_conflict": "婚姻背叛",
        "antagonist_type": "背叛前妻",
        "plot_style": "真相曝光",
        "emotion_direction": "前任后悔但主角不回头",
        "tone": "都市爽文风",
        "ending_type": "前任跪求原谅",
        "target_audience": "男性爽文观众",
    },
    "abandoned_heir": {
        "name": "豪门弃子归来",
        "genre": "豪门恩怨",
        "protagonist_type": "被豪门赶出的少爷",
        "opening_hook": "主角回到曾经抛弃他的家族",
        "main_conflict": "豪门争产",
        "antagonist_type": "恶毒继母",
        "plot_style": "主角夺回一切",
        "emotion_direction": "男主归来夺回尊严",
        "tone": "豪门虐恋风",
        "ending_type": "主角夺回家族继承权",
        "target_audience": "豪门复仇观众",
    },
    "gang_revenge": {
        "name": "黑帮复仇",
        "genre": "黑帮复仇",
        "protagonist_type": "被兄弟出卖的男人",
        "opening_hook": "主角从监狱归来",
        "main_conflict": "黑帮威胁",
        "antagonist_type": "黑帮老大",
        "plot_style": "复仇清算",
        "emotion_direction": "无感情线，专注复仇",
        "tone": "黑帮冷酷风",
        "ending_type": "反派全部崩溃",
        "target_audience": "男性爽文观众",
    },
    "heroine_counterattack": {
        "name": "女主逆袭复仇",
        "genre": "女频虐恋",
        "protagonist_type": "被丈夫抛弃的女人",
        "opening_hook": "主角被迫签下离婚协议",
        "main_conflict": "爱情背叛",
        "antagonist_type": "心机闺蜜",
        "plot_style": "绝地翻盘",
        "emotion_direction": "女主逆袭掌控人生",
        "tone": "情绪爆发风",
        "ending_type": "主角成为真正赢家",
        "target_audience": "女性情感观众",
    },
    "workplace_counter": {
        "name": "职场反杀",
        "genre": "职场逆袭",
        "protagonist_type": "被公司开除的员工",
        "opening_hook": "主角被公司当众开除",
        "main_conflict": "公司夺权",
        "antagonist_type": "公司高层",
        "plot_style": "商业反杀",
        "emotion_direction": "无感情线，专注复仇",
        "tone": "都市爽文风",
        "ending_type": "主角建立自己的商业帝国",
        "target_audience": "男性爽文观众",
    },
    "urban_mystery": {
        "name": "都市悬疑真相",
        "genre": "都市悬疑",
        "protagonist_type": "失忆的神秘人物",
        "opening_hook": "主角身份即将曝光",
        "main_conflict": "真相被掩盖",
        "antagonist_type": "幕后大佬",
        "plot_style": "多重反转",
        "emotion_direction": "感情线虐心到底",
        "tone": "悬疑压迫感",
        "ending_type": "真相全面曝光",
        "target_audience": "都市悬疑观众",
    },
    "campus_revenge": {
        "name": "校园霸凌复仇",
        "genre": "校园霸凌复仇",
        "protagonist_type": "从底层爬起的普通人",
        "opening_hook": "主角被前任当众羞辱",
        "main_conflict": "主角被所有人误会",
        "antagonist_type": "校园霸凌者",
        "plot_style": "打脸复仇",
        "emotion_direction": "主角彻底放下过去",
        "tone": "短视频强悬念",
        "ending_type": "所有人后悔",
        "target_audience": "中文短视频观众",
    },
    "business_war": {
        "name": "商业战争",
        "genre": "商业战争",
        "protagonist_type": "破产后归来的继承人",
        "opening_hook": "主角被豪门亲戚羞辱",
        "main_conflict": "商业陷害",
        "antagonist_type": "商业对手",
        "plot_style": "商业反杀",
        "emotion_direction": "主角彻底放下过去",
        "tone": "美剧旁白风",
        "ending_type": "主角建立自己的商业帝国",
        "target_audience": "美国长视频观众",
    },
    "ceo_romance": {
        "name": "霸总虐恋",
        "genre": "霸总爱情",
        "protagonist_type": "被丈夫抛弃的女人",
        "opening_hook": "主角被迫签下离婚协议",
        "main_conflict": "爱情背叛",
        "antagonist_type": "白月光",
        "plot_style": "感情反转",
        "emotion_direction": "感情线先虐后爽",
        "tone": "豪门虐恋风",
        "ending_type": "男女主重新开始",
        "target_audience": "女性情感观众",
    },
}
