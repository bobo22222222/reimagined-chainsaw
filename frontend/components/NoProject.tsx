"use client";

import Link from "next/link";

export default function NoProject() {
  return (
    <div className="card text-slate-400">
      还没有选择项目，请先到{" "}
      <Link href="/projects" className="text-brand-400 underline">
        项目列表
      </Link>{" "}
      进入一个项目，或{" "}
      <Link href="/create" className="text-brand-400 underline">
        创建项目
      </Link>
      。
    </div>
  );
}
