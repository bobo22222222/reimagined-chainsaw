"use client";

import { downloadUrls } from "@/lib/api";

const ITEMS = [
  {
    title: "完整小说 TXT",
    desc: "所有章节正文合并为一个 TXT。",
    url: (id: number) => downloadUrls.projectTxt(id),
  },
  {
    title: "章节 TXT 压缩包",
    desc: "每章一个 TXT，打包为 ZIP。",
    url: (id: number) => downloadUrls.projectChaptersZip(id),
  },
  {
    title: "MP3 配音压缩包",
    desc: "所有已生成的章节配音 MP3。",
    url: (id: number) => downloadUrls.projectAudioZip(id),
  },
  {
    title: "完整项目 ZIP",
    desc: "story_bible / outline / full_novel / chapters / audio。",
    url: (id: number) => downloadUrls.projectFullZip(id),
    primary: true,
  },
];

export default function ExportPanel({ projectId }: { projectId: number }) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      {ITEMS.map((item) => (
        <div key={item.title} className="card flex items-center justify-between">
          <div>
            <div className="font-semibold">{item.title}</div>
            <div className="text-sm text-slate-400">{item.desc}</div>
          </div>
          <a
            className={item.primary ? "btn-primary" : "btn-secondary"}
            href={item.url(projectId)}
            target="_blank"
            rel="noreferrer"
          >
            下载
          </a>
        </div>
      ))}
    </div>
  );
}
