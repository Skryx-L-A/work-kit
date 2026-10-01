// Display helpers without a vscode import, so they are unit-testable.

export function relativeTime(iso: string | undefined, now: Date = new Date()): string {
  if (!iso) {
    return 'unknown';
  }
  const then = Date.parse(iso);
  if (Number.isNaN(then)) {
    return 'unknown';
  }
  const seconds = Math.round((now.getTime() - then) / 1000);
  if (seconds < 60) {
    return 'just now';
  }
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    return `${minutes} min ago`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return hours === 1 ? '1 hour ago' : `${hours} hours ago`;
  }
  const days = Math.floor(hours / 24);
  if (days < 7) {
    return days === 1 ? 'yesterday' : `${days} days ago`;
  }
  const weeks = Math.floor(days / 7);
  if (weeks < 5) {
    return weeks === 1 ? '1 week ago' : `${weeks} weeks ago`;
  }
  const months = Math.floor(days / 30);
  if (months < 12) {
    return months === 1 ? '1 month ago' : `${months} months ago`;
  }
  const years = Math.floor(days / 365);
  return years === 1 ? '1 year ago' : `${years} years ago`;
}

/** Collapses whitespace and cuts to a preview length. */
export function previewText(text: string, maxLength = 180): string {
  const flat = text.replace(/\s+/g, ' ').trim();
  if (flat.length <= maxLength) {
    return flat;
  }
  return flat.slice(0, maxLength - 1).trimEnd() + '…';
}

export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Single-quotes a value for a POSIX shell command line. */
export function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

/** Short run/request id: sortable timestamp plus random suffix. */
export function newId(now: Date = new Date(), random: () => number = Math.random): string {
  const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\..*$/, '').replace('T', '-');
  const suffix = Math.floor(random() * 36 ** 4).toString(36).padStart(4, '0');
  return `${stamp}-${suffix}`;
}

/** Lowercase slug for names used in file paths and terminal titles. */
export function slug(text: string, fallback = 'worker'): string {
  const s = text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40);
  return s || fallback;
}

/** Text sent to an orchestrator for an editor selection: "path:line" and the selected text. */
export function selectionReference(relPath: string, startLine: number, endLine: number, text: string): string {
  const where = endLine > startLine ? `${relPath}:${startLine}-${endLine}` : `${relPath}:${startLine}`;
  const fence = text.includes('```') ? '~~~' : '```';
  return `${where}\n${fence}\n${text.replace(/\s+$/, '')}\n${fence}\n`;
}
