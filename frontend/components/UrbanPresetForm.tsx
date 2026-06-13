"use client";

import { URBAN_FIELDS } from "@/lib/constants";

export type UrbanValues = Record<string, string>;

export default function UrbanPresetForm({
  values,
  onChange,
}: {
  values: UrbanValues;
  onChange: (key: string, value: string) => void;
}) {
  return (
    <div className="card">
      <h2 className="text-lg font-semibold mb-1">都市小说快捷设定</h2>
      <p className="text-sm text-slate-400 mb-5">
        请选择都市小说的核心设定，系统会根据这些选项自动生成总设定、章节目录和正文。
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {URBAN_FIELDS.map((field) => (
          <div key={field.key}>
            <label className="label">{field.label}</label>
            <select
              className="input"
              value={values[field.key] || ""}
              onChange={(e) => onChange(field.key, e.target.value)}
            >
              <option value="">请选择</option>
              {field.options.map((opt) => (
                <option key={opt} value={opt}>
                  {opt}
                </option>
              ))}
            </select>
          </div>
        ))}
      </div>

      <div className="mt-4">
        <label className="label">自定义补充设定</label>
        <textarea
          className="input min-h-[120px]"
          value={values.custom_setting || ""}
          onChange={(e) => onChange("custom_setting", e.target.value)}
          placeholder={`例如：
主角三年前被妻子陷害入狱，如今带着隐藏身份回归。
反派是主角的亲哥哥，表面温和，实际一直在夺权。
故事前半段虐主，后半段强势反杀。`}
        />
      </div>
    </div>
  );
}
