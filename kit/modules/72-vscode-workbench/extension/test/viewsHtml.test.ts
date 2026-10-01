import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { RunMeta } from '../src/runs.ts';
import { cardActions, duration, isQuiet, logPreview, renderCard, renderOverview, renderResultView } from '../src/viewsHtml.ts';

const now = new Date('2026-09-25T12:00:00Z');

function meta(over: Partial<RunMeta> = {}): RunMeta {
  return {
    id: '20260925-110000-abcd', name: 'docs', role: 'worker', modelId: 'm', modelLabel: 'Model M', runner: 'api', cwd: '/w',
    paths: ['README.md'], done: 'README ok', status: 'running', createdAt: '2026-09-25T11:00:00Z', ...over,
  };
}

test('duration and quiet flag', () => {
  assert.equal(duration('2026-09-25T11:00:00Z', '2026-09-25T11:00:30Z'), '30 s');
  assert.equal(duration('2026-09-25T11:00:00Z', undefined, now), '1 h 0 min');
  assert.equal(duration('bad', undefined, now), '');
  const card = { meta: meta(), lastActivity: '2026-09-25T11:30:00Z' };
  assert.equal(isQuiet(card, 15, now), true);
  assert.equal(isQuiet(card, 45, now), false);
  assert.equal(isQuiet(card, 0, now), false);
  assert.equal(isQuiet({ ...card, meta: meta({ status: 'done' }) }, 15, now), false);
});

test('actions depend on the status', () => {
  assert.ok(cardActions(meta()).includes('stop'));
  assert.ok(!cardActions(meta()).includes('rerun'));
  assert.ok(cardActions(meta({ status: 'failed' })).includes('rerun'));
  assert.ok(cardActions(meta({ status: 'done' })).includes('archive'));
});

test('cards escape every value and show the result summary', () => {
  const html = renderCard({
    meta: meta({ name: '<b>x</b>', status: 'done', reason: '"quoted"' }),
    result: '## What\nchanged <script>alert(1)</script>\n\n## Open\nask IT\n\nDONE\n',
  }, 15, now);
  assert.doesNotMatch(html, /<script>|<b>x<\/b>/);
  assert.match(html, /&lt;b&gt;x&lt;\/b&gt;/);
  assert.match(html, /changed &lt;script&gt;/);
  assert.match(html, /Open:<\/span> ask IT/);
  assert.match(html, /data-action="rerun"/);
});

test('overview has counts, filters, status chips and a nonce-only script', () => {
  const html = renderOverview({
    cards: [{ meta: meta() }, { meta: meta({ id: 'b', status: 'failed' }) }],
    status: [{ id: 'brain', label: 'Brain', level: 'missing', detail: 'not installed' }],
    quietMinutes: 15,
    templates: 6,
    now,
  }, 'NONCE1', 'vscode-resource:');
  assert.match(html, /script-src 'nonce-NONCE1'/);
  assert.equal((html.match(/<script/g) ?? []).length, 1);
  assert.match(html, /<script nonce="NONCE1">/);
  assert.match(html, /running \(1\)/);
  assert.match(html, /failed \(1\)/);
  assert.match(html, /Brain: not installed/);
  assert.match(html, /From template \(6\)/);
  assert.match(renderOverview({ cards: [], status: [], quietMinutes: 15, templates: 0 }, 'n', 'c'), /No workers yet/);
});

test('result view shows meta, sections, outcome, task and log', () => {
  const html = renderResultView({
    meta: meta({ status: 'failed', endedAt: '2026-09-25T11:10:00Z' }),
    result: '## What\nhalf done\n\nFAILED: tests red',
    task: '# Task: docs\n\nDo <it>',
    log: ['11:00:01 tool-call: read_file {}'],
    now,
  }, 'N2', 'c');
  assert.match(html, /<h2>What<\/h2><pre>half done<\/pre>/);
  assert.match(html, /FAILED: tests red/);
  assert.match(html, /ran 10 min/);
  assert.match(html, /Do &lt;it&gt;/);
  assert.match(html, /read_file/);
  assert.match(html, /data-action="rerun"/);
  assert.match(html, /"20260925-110000-abcd"/);
  assert.match(renderResultView({ meta: meta() }, 'n', 'c'), /No result file yet/);
});

test('log preview shortens entries and skips partial lines', () => {
  const lines = logPreview([
    JSON.stringify({ at: '2026-09-25T11:00:01.000Z', type: 'text', text: 'hello' }),
    JSON.stringify({ at: '2026-09-25T11:00:02.000Z', type: 'tool-call', name: 'write_file', input: { path: 'a' } }),
    JSON.stringify({ at: '2026-09-25T11:00:03.000Z', type: 'tool-result', name: 'write_file', content: 'ok' }),
    '{"partial',
  ].join('\n'));
  assert.deepEqual(lines, ['11:00:01 text: hello', '11:00:02 tool-call: write_file {"path":"a"}', '11:00:03 tool-result: write_file -> ok']);
  assert.equal(logPreview(lines.map(() => JSON.stringify({ type: 'text', text: 'x' })).join('\n'), 2).length, 2);
});
