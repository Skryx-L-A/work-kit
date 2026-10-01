// HTML for the worker overview (grid of cards) and the result view. Pure module: no vscode
// import, every value is escaped, scripts run only with the nonce, messages go back through
// postMessage as { type: 'action', action, runId }.
import { escapeHtml, previewText, relativeTime } from './format.ts';
import { parseResult, section, type ParsedResult } from './results.ts';
import type { RunMeta } from './runs.ts';
import type { StatusItem } from './status.ts';

export interface RunCard {
  meta: RunMeta;
  result?: string;
  /** Newest change of the run's files (log, result, meta). */
  lastActivity?: string;
}

export type CardAction = 'show' | 'result' | 'task' | 'stop' | 'rerun' | 'archive';

const STATUS_ICON: Record<RunMeta['status'], string> = { running: '●', done: '✓', failed: '✕', stopped: '■' };
const LEVEL_ICON: Record<StatusItem['level'], string> = { ok: '✓', off: '–', warn: '!', missing: '○' };

export function duration(startIso: string, endIso: string | undefined, now: Date = new Date()): string {
  const start = Date.parse(startIso);
  const end = endIso ? Date.parse(endIso) : now.getTime();
  if (Number.isNaN(start) || Number.isNaN(end) || end < start) {
    return '';
  }
  const s = Math.round((end - start) / 1000);
  if (s < 60) {
    return `${s} s`;
  }
  const m = Math.floor(s / 60);
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`;
}

/** A running run with no file change for `quietMinutes` is flagged, not failed. */
export function isQuiet(card: RunCard, quietMinutes: number, now: Date = new Date()): boolean {
  if (card.meta.status !== 'running' || quietMinutes <= 0 || !card.lastActivity) {
    return false;
  }
  return now.getTime() - Date.parse(card.lastActivity) > quietMinutes * 60_000;
}

export function cardActions(meta: RunMeta): CardAction[] {
  return meta.status === 'running'
    ? ['show', 'task', 'result', 'stop']
    : ['result', 'task', 'show', 'rerun', 'archive'];
}

const ACTION_LABEL: Record<CardAction, string> = {
  show: 'Show', result: 'Result', task: 'Task', stop: 'Stop', rerun: 'Run again…', archive: 'Archive',
};

function summaryOf(parsed: ParsedResult | undefined): { what?: string; open?: string } {
  if (!parsed) {
    return {};
  }
  const what = section(parsed, 'What', 'Result', 'Summary') ?? parsed.sections[0]?.text;
  const open = section(parsed, 'Open', 'Open points');
  return { what: what ? previewText(what, 220) : undefined, open: open ? previewText(open, 160) : undefined };
}

export function renderCard(card: RunCard, quietMinutes: number, now: Date = new Date()): string {
  const m = card.meta;
  const parsed = card.result?.trim() ? parseResult(card.result) : undefined;
  const { what, open } = summaryOf(parsed);
  const quiet = isQuiet(card, quietMinutes, now);
  const facts = [
    `${escapeHtml(m.modelLabel)} <span class="dim">(${escapeHtml(m.runner)})</span>`,
    `started ${escapeHtml(relativeTime(m.createdAt, now))}${duration(m.createdAt, m.endedAt, now) ? `, ${escapeHtml(duration(m.createdAt, m.endedAt, now))}` : ''}`,
    m.origin ? `from ${escapeHtml(m.origin)}` : '',
  ].filter(Boolean).join(' · ');
  const buttons = cardActions(m)
    .map((a) => `<button class="${a === 'stop' ? 'danger' : 'secondary'}" data-action="${a}" data-run="${escapeHtml(m.id)}">${ACTION_LABEL[a]}</button>`)
    .join('');
  return `<article class="card ${m.status}${quiet ? ' quiet' : ''}" data-status="${m.status}" data-run="${escapeHtml(m.id)}">
  <header><span class="icon">${STATUS_ICON[m.status]}</span><strong>${escapeHtml(m.name)}</strong>
    <span class="badge">${m.status}</span>${quiet ? `<span class="badge warn" title="No file change for more than ${quietMinutes} min">quiet since ${escapeHtml(relativeTime(card.lastActivity, now))}</span>` : ''}</header>
  <div class="facts">${facts}</div>
  <div class="facts">Paths: ${escapeHtml(m.paths.join(', ') || 'none given')}</div>
  <div class="facts">Done when: ${escapeHtml(m.done || 'not given')}</div>
  ${m.reason ? `<div class="reason">${escapeHtml(m.reason)}</div>` : ''}
  ${what ? `<div class="what">${escapeHtml(what)}</div>` : m.status === 'running' ? '<div class="dim">No result yet.</div>' : ''}
  ${open ? `<div class="open"><span class="dim">Open:</span> ${escapeHtml(open)}</div>` : ''}
  <footer>${buttons}</footer>
</article>`;
}

function statusChips(items: readonly StatusItem[]): string {
  return items
    .map((i) => `<span class="chip ${i.level}" title="${escapeHtml([i.detail, ...(i.more ?? [])].join('\n'))}">${LEVEL_ICON[i.level]} ${escapeHtml(i.label)}: ${escapeHtml(i.detail)}</span>`)
    .join('');
}

const BASE_CSS = `
  body { font-family: var(--vscode-font-family); font-size: var(--vscode-font-size); color: var(--vscode-foreground); margin: 0; padding: 12px 16px; }
  button { font: inherit; color: var(--vscode-button-foreground); background: var(--vscode-button-background); border: 0; padding: 3px 10px; cursor: pointer; border-radius: 2px; }
  button.secondary { color: var(--vscode-button-secondaryForeground); background: var(--vscode-button-secondaryBackground); }
  button.danger { background: var(--vscode-inputValidation-errorBackground, #a1260d); color: var(--vscode-button-foreground); }
  button:focus-visible { outline: 1px solid var(--vscode-focusBorder); outline-offset: 1px; }
  .dim { color: var(--vscode-descriptionForeground); }
  .badge { font-size: 0.85em; padding: 0 6px; border-radius: 8px; background: var(--vscode-badge-background); color: var(--vscode-badge-foreground); margin-left: 6px; }
  .badge.warn { background: var(--vscode-inputValidation-warningBackground, #6b5500); }
`;

export interface OverviewData {
  cards: RunCard[];
  status: StatusItem[];
  quietMinutes: number;
  templates: number;
  now?: Date;
}

export function renderOverview(data: OverviewData, nonce: string, cspSource: string): string {
  const now = data.now ?? new Date();
  const counts = { running: 0, done: 0, failed: 0, stopped: 0 } as Record<RunMeta['status'], number>;
  for (const c of data.cards) {
    counts[c.meta.status]++;
  }
  const filters = (['all', 'running', 'done', 'failed', 'stopped'] as const)
    .map((f) => `<button class="secondary filter" data-filter="${f}">${f}${f === 'all' ? ` (${data.cards.length})` : ` (${counts[f]})`}</button>`)
    .join('');
  const cards = data.cards.map((c) => renderCard(c, data.quietMinutes, now)).join('\n');
  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Workers</title>
<style>${BASE_CSS}
  .bar { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; margin-bottom: 10px; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; }
  .chip { font-size: 0.9em; padding: 2px 8px; border-radius: 10px; border: 1px solid var(--vscode-panel-border, #555); }
  .chip.ok { border-color: var(--vscode-testing-iconPassed, #388a34); }
  .chip.warn { border-color: var(--vscode-editorWarning-foreground, #cca700); }
  .chip.missing, .chip.off { color: var(--vscode-descriptionForeground); }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 10px; }
  .card { border: 1px solid var(--vscode-panel-border, #555); border-left-width: 3px; border-radius: 3px; padding: 8px 10px; display: flex; flex-direction: column; gap: 4px; background: var(--vscode-editorWidget-background); }
  .card.running { border-left-color: var(--vscode-progressBar-background, #0e70c0); }
  .card.done { border-left-color: var(--vscode-testing-iconPassed, #388a34); }
  .card.failed { border-left-color: var(--vscode-testing-iconFailed, #c72e0f); }
  .card.quiet { border-left-color: var(--vscode-editorWarning-foreground, #cca700); }
  .card header { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
  .facts { font-size: 0.9em; color: var(--vscode-descriptionForeground); overflow-wrap: anywhere; }
  .what { white-space: pre-wrap; overflow-wrap: anywhere; }
  .reason { color: var(--vscode-errorForeground); overflow-wrap: anywhere; }
  .card footer { display: flex; gap: 4px; flex-wrap: wrap; margin-top: 4px; }
  .empty { padding: 24px 0; }
</style></head>
<body>
<div class="bar">
  <button data-cmd="spawn">Spawn worker</button>
  <button class="secondary" data-cmd="template">From template (${data.templates})</button>
  <button class="secondary" data-cmd="orchestrator">Orchestrator</button>
  <button class="secondary" data-cmd="refresh">Refresh</button>
  <button class="secondary" data-cmd="archive">Archive finished</button>
</div>
<div class="chips">${statusChips(data.status)}</div>
<div class="bar">${filters}</div>
${data.cards.length === 0 ? '<div class="empty dim">No workers yet. Spawn one, start from a template, or ask the orchestrator.</div>' : `<div class="grid">${cards}</div>`}
<script nonce="${nonce}">
  const vscode = acquireVsCodeApi();
  const state = vscode.getState() || { filter: 'all' };
  function applyFilter() {
    document.querySelectorAll('.card').forEach((c) => { c.hidden = state.filter !== 'all' && c.dataset.status !== state.filter; });
    document.querySelectorAll('.filter').forEach((b) => b.classList.toggle('secondary', b.dataset.filter !== state.filter));
  }
  document.body.addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.filter) { state.filter = b.dataset.filter; vscode.setState(state); applyFilter(); return; }
    if (b.dataset.cmd) { vscode.postMessage({ type: 'command', command: b.dataset.cmd }); return; }
    if (b.dataset.action) { vscode.postMessage({ type: 'action', action: b.dataset.action, runId: b.dataset.run }); }
  });
  applyFilter();
</script>
</body></html>`;
}

export interface ResultViewData {
  meta: RunMeta;
  result?: string;
  task?: string;
  /** Last log lines of an API worker, already shortened. */
  log?: string[];
  now?: Date;
}

export function renderResultView(data: ResultViewData, nonce: string, cspSource: string): string {
  const m = data.meta;
  const now = data.now ?? new Date();
  const parsed = data.result?.trim() ? parseResult(data.result) : undefined;
  const sections = parsed
    ? parsed.sections.map((s) => `<section>${s.heading ? `<h2>${escapeHtml(s.heading)}</h2>` : ''}<pre>${escapeHtml(s.text)}</pre></section>`).join('\n')
    : '<p class="dim">No result file yet.</p>';
  const outcome = parsed
    ? parsed.outcome === 'done'
      ? '<p class="ok">Ends with DONE.</p>'
      : parsed.outcome === 'failed'
        ? `<p class="bad">FAILED: ${escapeHtml(parsed.failure ?? '')}</p>`
        : '<p class="dim">No end marker yet (DONE or FAILED).</p>'
    : '';
  const actions = (['result', 'task', 'show', ...(m.status === 'running' ? ['stop'] : ['rerun'])] as CardAction[])
    .map((a) => `<button class="${a === 'stop' ? 'danger' : 'secondary'}" data-action="${a}">${a === 'result' ? 'Open file' : ACTION_LABEL[a]}</button>`)
    .join('');
  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Result: ${escapeHtml(m.name)}</title>
<style>${BASE_CSS}
  h1 { font-size: 1.3em; margin: 0 0 6px; }
  h2 { font-size: 1.05em; margin: 14px 0 4px; }
  dl { display: grid; grid-template-columns: max-content 1fr; gap: 2px 12px; margin: 8px 0; }
  dt { color: var(--vscode-descriptionForeground); }
  dd { margin: 0; overflow-wrap: anywhere; }
  pre { white-space: pre-wrap; overflow-wrap: anywhere; font-family: var(--vscode-editor-font-family); margin: 0; }
  .ok { color: var(--vscode-testing-iconPassed, #388a34); }
  .bad { color: var(--vscode-errorForeground); }
  details { margin-top: 14px; }
  .bar { display: flex; gap: 6px; flex-wrap: wrap; }
</style></head>
<body>
<h1>${escapeHtml(m.name)} <span class="badge">${m.status}</span></h1>
<div class="bar">${actions}</div>
<dl>
  <dt>Run</dt><dd>${escapeHtml(m.id)}</dd>
  <dt>Model</dt><dd>${escapeHtml(m.modelLabel)} (${escapeHtml(m.runner)})</dd>
  <dt>Started</dt><dd>${escapeHtml(relativeTime(m.createdAt, now))}${duration(m.createdAt, m.endedAt, now) ? `, ran ${escapeHtml(duration(m.createdAt, m.endedAt, now))}` : ''}</dd>
  <dt>Working dir</dt><dd>${escapeHtml(m.cwd)}</dd>
  <dt>Paths</dt><dd>${escapeHtml(m.paths.join(', ') || 'none given')}</dd>
  <dt>Done when</dt><dd>${escapeHtml(m.done || 'not given')}</dd>
  ${m.reason ? `<dt>Reason</dt><dd class="bad">${escapeHtml(m.reason)}</dd>` : ''}
</dl>
${outcome}
${sections}
${data.task ? `<details><summary>Task</summary><pre>${escapeHtml(data.task)}</pre></details>` : ''}
${data.log && data.log.length > 0 ? `<details><summary>Log (last ${data.log.length} entries)</summary><pre>${escapeHtml(data.log.join('\n'))}</pre></details>` : ''}
<p class="dim">Review every AI result before you use it.</p>
<script nonce="${nonce}">
  const vscode = acquireVsCodeApi();
  document.body.addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (b && b.dataset.action) vscode.postMessage({ type: 'action', action: b.dataset.action, runId: ${JSON.stringify(m.id).replace(/</g, '\\u003c')} });
  });
</script>
</body></html>`;
}

/** Shortens log.jsonl lines for the result view: type, tool name, and a text preview. */
export function logPreview(jsonl: string, max = 30): string[] {
  const out: string[] = [];
  for (const line of jsonl.split('\n')) {
    if (!line.trim()) {
      continue;
    }
    try {
      const e = JSON.parse(line) as { at?: string; type?: string; name?: string; text?: string; content?: string; input?: unknown };
      const time = e.at ? e.at.slice(11, 19) : '';
      const body = e.type === 'text'
        ? previewText(e.text ?? '', 160)
        : e.type === 'tool-call'
          ? `${e.name} ${previewText(JSON.stringify(e.input ?? {}), 140)}`
          : `${e.name} -> ${previewText(e.content ?? '', 140)}`;
      out.push(`${time} ${e.type ?? '?'}: ${body}`);
    } catch {
      // A partial line while the worker writes: skip.
    }
  }
  return out.slice(-max);
}
