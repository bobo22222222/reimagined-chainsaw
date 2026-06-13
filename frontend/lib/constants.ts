// 都市小说快捷设定的所有下拉选项 + 都市爆款模板。
// 严格限制都市现代题材，绝不包含玄幻 / 修仙 / 穿越 / 重生 / 系统 / 末日。

export const TARGET_WORDS_OPTIONS = [
  { label: "5千字", value: 5000 },
  { label: "1万字", value: 10000 },
  { label: "2万字", value: 20000 },
  { label: "5万字", value: 50000 },
  { label: "10万字", value: 100000 },
  { label: "20万字", value: 200000 },
];

/** 将 target_words 数值格式化为选项标签，未知值则原样显示。 */
export function formatTargetWords(value: number | undefined): string {
  if (value == null) return "—";
  const opt = TARGET_WORDS_OPTIONS.find((o) => o.value === value);
  return opt?.label ?? `${value}字`;
}

export const CHAPTER_WORDS_OPTIONS = [
  { label: "2000 字", value: 2000 },
  { label: "3000 字", value: 3000 },
  { label: "4000 字", value: 4000 },
  { label: "5000 字", value: 5000 },
];

export const LANGUAGE_OPTIONS = [
  { label: "中文", value: "zh" },
  { label: "英文", value: "en" },
  { label: "西班牙语", value: "es" },
  { label: "日语", value: "ja" },
];

export const LANGUAGE_LABEL: Record<string, string> = {
  zh: "中文",
  en: "英文",
  es: "西班牙语",
  ja: "日语",
};

export function languageLabel(code: string | undefined): string {
  if (!code) return "—";
  return LANGUAGE_LABEL[code] || code;
}

export const DEFAULT_VOICE_BY_LANGUAGE: Record<string, string> = {
  zh: "zh_male",
  en: "en_male",
  es: "es_male",
  ja: "ja_male",
};

export const VOICE_GROUPS = [
  { lang: "zh", label: "中文音色", keys: ["zh_male", "zh_female"] },
  { lang: "en", label: "英文音色", keys: ["en_male", "en_female"] },
  { lang: "es", label: "西班牙语音色", keys: ["es_male", "es_female"] },
  { lang: "ja", label: "日语音色", keys: ["ja_male", "ja_female"] },
];

export const GENRE_OPTIONS = [
  "都市复仇",
  "豪门恩怨",
  "霸总爱情",
  "女频虐恋",
  "都市悬疑",
  "犯罪推理",
  "黑帮复仇",
  "职场逆袭",
  "商业战争",
  "婚姻背叛",
  "家族争产",
  "身份反转",
  "校园霸凌复仇",
  "都市情感",
  "富豪归来",
];

export const PROTAGONIST_OPTIONS = [
  "被家族抛弃的男人",
  "被豪门赶出的少爷",
  "隐藏身份的神秘富豪",
  "被妻子背叛的丈夫",
  "被丈夫抛弃的女人",
  "被陷害入狱的男人",
  "破产后归来的继承人",
  "从底层爬起的普通人",
  "被公司开除的员工",
  "被闺蜜背叛的女人",
  "被兄弟出卖的男人",
  "失忆的神秘人物",
  "隐藏实力的商业大佬",
  "被所有人看不起的上门女婿",
];

export const OPENING_OPTIONS = [
  "婚礼现场被羞辱",
  "家族宴会上被赶出门",
  "主角被妻子提出离婚",
  "主角发现伴侣出轨",
  "主角被兄弟陷害入狱",
  "主角从监狱归来",
  "主角在葬礼上突然出现",
  "主角被公司当众开除",
  "主角被豪门亲戚羞辱",
  "主角被前任当众羞辱",
  "主角发现孩子不是自己的",
  "主角被迫签下离婚协议",
  "主角身份即将曝光",
  "主角回到曾经抛弃他的家族",
];

export const CONFLICT_OPTIONS = [
  "家族羞辱",
  "婚姻背叛",
  "兄弟反目",
  "商业陷害",
  "豪门争产",
  "公司夺权",
  "亲情冷漠",
  "爱情背叛",
  "黑帮威胁",
  "身份被隐藏",
  "真相被掩盖",
  "主角被所有人误会",
  "反派抢走主角的一切",
  "主角暗中布局复仇",
];

export const ANTAGONIST_OPTIONS = [
  "伪善兄弟",
  "冷漠父亲",
  "恶毒继母",
  "贪婪亲戚",
  "背叛前妻",
  "背叛前夫",
  "心机闺蜜",
  "商业对手",
  "黑帮老大",
  "豪门家族",
  "公司高层",
  "假富豪",
  "白月光",
  "幕后大佬",
  "校园霸凌者",
];

export const PLOT_STYLE_OPTIONS = [
  "身份反转",
  "打脸复仇",
  "财富碾压",
  "智商压制",
  "商业反杀",
  "真相曝光",
  "感情反转",
  "绝地翻盘",
  "幕后操控",
  "复仇清算",
  "豪门崩塌",
  "反派跪求原谅",
  "主角夺回一切",
  "所有人后悔",
  "多重反转",
];

export const EMOTION_OPTIONS = [
  "主角彻底放下过去",
  "前任后悔但主角不回头",
  "男女主破镜重圆",
  "主角黑化复仇",
  "主角遇到真正爱他的人",
  "女主逆袭掌控人生",
  "男主归来夺回尊严",
  "感情线虐心到底",
  "感情线先虐后爽",
  "无感情线，专注复仇",
];

export const TONE_OPTIONS = [
  "短视频强悬念",
  "都市爽文风",
  "豪门虐恋风",
  "美剧旁白风",
  "电影解说风",
  "悬疑压迫感",
  "黑帮冷酷风",
  "情绪爆发风",
  "第一人称沉浸式",
  "第三人称旁白式",
];

export const ENDING_OPTIONS = [
  "主角彻底复仇成功",
  "主角夺回家族继承权",
  "反派全部崩溃",
  "前任跪求原谅",
  "主角成为真正赢家",
  "真相全面曝光",
  "豪门家族瓦解",
  "主角建立自己的商业帝国",
  "男女主重新开始",
  "开放式反转结局",
  "所有人付出代价",
];

export const AUDIENCE_OPTIONS = [
  "中文短视频观众",
  "美国长视频观众",
  "日本解说观众",
  "西语短剧观众",
  "女性情感观众",
  "男性爽文观众",
  "都市悬疑观众",
  "豪门复仇观众",
];

export interface UrbanField {
  key: string;
  label: string;
  options: string[];
}

export const URBAN_FIELDS: UrbanField[] = [
  { key: "genre", label: "题材类型", options: GENRE_OPTIONS },
  { key: "protagonist_type", label: "主角身份", options: PROTAGONIST_OPTIONS },
  { key: "opening_hook", label: "故事开局", options: OPENING_OPTIONS },
  { key: "main_conflict", label: "主要冲突", options: CONFLICT_OPTIONS },
  { key: "antagonist_type", label: "反派类型", options: ANTAGONIST_OPTIONS },
  { key: "plot_style", label: "爽点类型", options: PLOT_STYLE_OPTIONS },
  { key: "emotion_direction", label: "情感方向", options: EMOTION_OPTIONS },
  { key: "tone", label: "文风选择", options: TONE_OPTIONS },
  { key: "ending_type", label: "结局方向", options: ENDING_OPTIONS },
  { key: "target_audience", label: "目标受众", options: AUDIENCE_OPTIONS },
];

export interface UrbanTemplate {
  key: string;
  name: string;
  values: Record<string, string>;
}

export const TEMPLATES: UrbanTemplate[] = [
  {
    key: "tycoon_revenge",
    name: "富豪归来复仇",
    values: {
      genre: "都市复仇",
      protagonist_type: "隐藏身份的神秘富豪",
      opening_hook: "家族宴会上被赶出门",
      main_conflict: "家族羞辱",
      antagonist_type: "伪善兄弟",
      plot_style: "身份反转",
      emotion_direction: "主角彻底放下过去",
      tone: "短视频强悬念",
      ending_type: "主角夺回一切",
      target_audience: "男性爽文观众",
    },
  },
  {
    key: "divorce_reveal",
    name: "离婚后身份曝光",
    values: {
      genre: "婚姻背叛",
      protagonist_type: "被妻子背叛的丈夫",
      opening_hook: "主角被妻子提出离婚",
      main_conflict: "婚姻背叛",
      antagonist_type: "背叛前妻",
      plot_style: "真相曝光",
      emotion_direction: "前任后悔但主角不回头",
      tone: "都市爽文风",
      ending_type: "前任跪求原谅",
      target_audience: "男性爽文观众",
    },
  },
  {
    key: "abandoned_heir",
    name: "豪门弃子归来",
    values: {
      genre: "豪门恩怨",
      protagonist_type: "被豪门赶出的少爷",
      opening_hook: "主角回到曾经抛弃他的家族",
      main_conflict: "豪门争产",
      antagonist_type: "恶毒继母",
      plot_style: "主角夺回一切",
      emotion_direction: "男主归来夺回尊严",
      tone: "豪门虐恋风",
      ending_type: "主角夺回家族继承权",
      target_audience: "豪门复仇观众",
    },
  },
  {
    key: "gang_revenge",
    name: "黑帮复仇",
    values: {
      genre: "黑帮复仇",
      protagonist_type: "被兄弟出卖的男人",
      opening_hook: "主角从监狱归来",
      main_conflict: "黑帮威胁",
      antagonist_type: "黑帮老大",
      plot_style: "复仇清算",
      emotion_direction: "无感情线，专注复仇",
      tone: "黑帮冷酷风",
      ending_type: "反派全部崩溃",
      target_audience: "男性爽文观众",
    },
  },
  {
    key: "heroine_counterattack",
    name: "女主逆袭复仇",
    values: {
      genre: "女频虐恋",
      protagonist_type: "被丈夫抛弃的女人",
      opening_hook: "主角被迫签下离婚协议",
      main_conflict: "爱情背叛",
      antagonist_type: "心机闺蜜",
      plot_style: "绝地翻盘",
      emotion_direction: "女主逆袭掌控人生",
      tone: "情绪爆发风",
      ending_type: "主角成为真正赢家",
      target_audience: "女性情感观众",
    },
  },
  {
    key: "workplace_counter",
    name: "职场反杀",
    values: {
      genre: "职场逆袭",
      protagonist_type: "被公司开除的员工",
      opening_hook: "主角被公司当众开除",
      main_conflict: "公司夺权",
      antagonist_type: "公司高层",
      plot_style: "商业反杀",
      emotion_direction: "无感情线，专注复仇",
      tone: "都市爽文风",
      ending_type: "主角建立自己的商业帝国",
      target_audience: "男性爽文观众",
    },
  },
  {
    key: "urban_mystery",
    name: "都市悬疑真相",
    values: {
      genre: "都市悬疑",
      protagonist_type: "失忆的神秘人物",
      opening_hook: "主角身份即将曝光",
      main_conflict: "真相被掩盖",
      antagonist_type: "幕后大佬",
      plot_style: "多重反转",
      emotion_direction: "感情线虐心到底",
      tone: "悬疑压迫感",
      ending_type: "真相全面曝光",
      target_audience: "都市悬疑观众",
    },
  },
  {
    key: "campus_revenge",
    name: "校园霸凌复仇",
    values: {
      genre: "校园霸凌复仇",
      protagonist_type: "从底层爬起的普通人",
      opening_hook: "主角被前任当众羞辱",
      main_conflict: "主角被所有人误会",
      antagonist_type: "校园霸凌者",
      plot_style: "打脸复仇",
      emotion_direction: "主角彻底放下过去",
      tone: "短视频强悬念",
      ending_type: "所有人后悔",
      target_audience: "中文短视频观众",
    },
  },
  {
    key: "business_war",
    name: "商业战争",
    values: {
      genre: "商业战争",
      protagonist_type: "破产后归来的继承人",
      opening_hook: "主角被豪门亲戚羞辱",
      main_conflict: "商业陷害",
      antagonist_type: "商业对手",
      plot_style: "商业反杀",
      emotion_direction: "主角彻底放下过去",
      tone: "美剧旁白风",
      ending_type: "主角建立自己的商业帝国",
      target_audience: "美国长视频观众",
    },
  },
  {
    key: "ceo_romance",
    name: "霸总虐恋",
    values: {
      genre: "霸总爱情",
      protagonist_type: "被丈夫抛弃的女人",
      opening_hook: "主角被迫签下离婚协议",
      main_conflict: "爱情背叛",
      antagonist_type: "白月光",
      plot_style: "感情反转",
      emotion_direction: "感情线先虐后爽",
      tone: "豪门虐恋风",
      ending_type: "男女主重新开始",
      target_audience: "女性情感观众",
    },
  },
];

export const VOICE_OPTIONS = [
  { key: "zh_male", label: "中文男声 (Yunxi)" },
  { key: "zh_female", label: "中文女声 (Xiaoxiao)" },
  { key: "en_male", label: "英文男声 (Guy)" },
  { key: "en_female", label: "英文女声 (Jenny)" },
  { key: "es_male", label: "西语男声 (Alvaro)" },
  { key: "es_female", label: "西语女声 (Elvira)" },
  { key: "ja_male", label: "日语男声 (Keita)" },
  { key: "ja_female", label: "日语女声 (Nanami)" },
];

export const RATE_OPTIONS = [
  { label: "-20%", value: "-20%" },
  { label: "-10%", value: "-10%" },
  { label: "正常", value: "+0%" },
  { label: "+10%", value: "+10%" },
  { label: "+20%", value: "+20%" },
];
