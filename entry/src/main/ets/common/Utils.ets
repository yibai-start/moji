export function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export function nowMs(): number {
  return new Date().getTime();
}

export function startOfDay(ms: number): number {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function endOfDay(ms: number): number {
  const d = new Date(ms);
  d.setHours(23, 59, 59, 999);
  return d.getTime();
}

export function isSameDay(a: number, b: number): boolean {
  const da = new Date(a);
  const db = new Date(b);
  return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth() && da.getDate() === db.getDate();
}

export function isOverdue(dueAt: number, done: boolean): boolean {
  return !done && dueAt > 0 && dueAt < nowMs();
}

export function timePart(ms: number): string {
  const d = new Date(ms);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

export function dateTimePart(ms: number): string {
  const d = new Date(ms);
  return `${d.getMonth() + 1}月${d.getDate()}日 ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

export function formatDue(dueAt: number): string {
  if (dueAt <= 0) {
    return '无截止时间';
  }
  const now = nowMs();
  if (isSameDay(dueAt, now)) {
    return `今天 ${timePart(dueAt)}`;
  }
  if (isSameDay(dueAt, now + 24 * 60 * 60 * 1000)) {
    return `明天 ${timePart(dueAt)}`;
  }
  return dateTimePart(dueAt);
}

export function formatRelative(ms: number): string {
  const diff = nowMs() - ms;
  if (diff < 60 * 1000) {
    return '刚刚';
  }
  if (diff < 60 * 60 * 1000) {
    return `${Math.floor(diff / 60000)} 分钟前`;
  }
  if (isSameDay(ms, nowMs())) {
    return `${Math.floor(diff / 3600000)} 小时前`;
  }
  const d = new Date(ms);
  const now = new Date();
  if (d.getFullYear() === now.getFullYear()) {
    return `${d.getMonth() + 1}月${d.getDate()}日`;
  }
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`;
}

export function excerpt(text: string, max: number): string {
  const single = text.replace(/\s+/g, ' ').trim();
  if (single.length <= max) {
    return single;
  }
  return `${single.substring(0, max)}…`;
}

export function todayLabel(): string {
  const d = new Date();
  const week: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  return `${d.getMonth() + 1}月${d.getDate()}日 ${week[d.getDay()]}`;
}

export function truncate(text: string, max: number): string {
  if (text.length <= max) {
    return text;
  }
  return `${text.substring(0, max)}…`;
}

export function withAlpha(color: string, alphaHex: string): string {
  if (color.startsWith('#') && color.length === 7) {
    return `#${alphaHex}${color.substring(1)}`;
  }
  return color;
}

// 图文混排正文：图片以 %%img:文件名%% 标记内嵌在文本中。
export class NoteSegment {
  isImage: boolean = false;
  text: string = '';
  image: string = '';
}

export function noteImageNames(content: string): string[] {
  const result: string[] = [];
  const re = /%%img:([^%]+)%%/g;
  let m: RegExpExecArray | null = re.exec(content);
  while (m !== null) {
    const name: string = m[1];
    if (result.indexOf(name) < 0) {
      result.push(name);
    }
    m = re.exec(content);
  }
  return result;
}

export function notePlainText(content: string): string {
  return content.replace(/%%img:[^%]+%%/g, '');
}

export function parseNoteContent(content: string): NoteSegment[] {
  const segments: NoteSegment[] = [];
  const pushText = (raw: string): void => {
    if (raw.length > 0) {
      const seg: NoteSegment = new NoteSegment();
      seg.text = raw;
      segments.push(seg);
    }
  };
  const re = /%%img:([^%]+)%%/g;
  let last = 0;
  let m: RegExpExecArray | null = re.exec(content);
  while (m !== null) {
    pushText(content.substring(last, m.index));
    const seg: NoteSegment = new NoteSegment();
    seg.isImage = true;
    seg.image = m[1];
    segments.push(seg);
    last = m.index + m[0].length;
    m = re.exec(content);
  }
  pushText(content.substring(last));
  return segments;
}

export function imageFileName(uri: string): string {
  const slash: number = uri.lastIndexOf('/');
  return slash < 0 ? uri : uri.substring(slash + 1);
}
