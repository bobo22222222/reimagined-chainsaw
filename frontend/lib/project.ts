// 当前选中项目（存 localStorage，跨页面共享）。
const KEY = "current_project_id";
const EVENT = "current-project-change";

export function getCurrentProjectId(): number | null {
  if (typeof window === "undefined") return null;
  const v = window.localStorage.getItem(KEY);
  return v ? Number(v) : null;
}

export function setCurrentProjectId(id: number | null): void {
  if (typeof window === "undefined") return;
  if (id === null) {
    window.localStorage.removeItem(KEY);
  } else {
    window.localStorage.setItem(KEY, String(id));
  }
  window.dispatchEvent(new Event(EVENT));
}

export function onProjectChange(cb: () => void): () => void {
  window.addEventListener(EVENT, cb);
  window.addEventListener("storage", cb);
  return () => {
    window.removeEventListener(EVENT, cb);
    window.removeEventListener("storage", cb);
  };
}
