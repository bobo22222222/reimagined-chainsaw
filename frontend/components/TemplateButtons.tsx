"use client";

import { TEMPLATES } from "@/lib/constants";

export default function TemplateButtons({
  onApply,
}: {
  onApply: (values: Record<string, string>) => void;
}) {
  return (
    <div className="card">
      <h2 className="text-lg font-semibold mb-1">都市爆款模板</h2>
      <p className="text-sm text-slate-400 mb-4">
        点击模板，自动填充下方全部设定。
      </p>
      <div className="flex flex-wrap gap-2">
        {TEMPLATES.map((t) => (
          <button
            key={t.key}
            className="btn-ghost btn-sm"
            onClick={() => onApply(t.values)}
          >
            {t.name}
          </button>
        ))}
      </div>
    </div>
  );
}
