import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';
import {
  archiveRuns,
  createRun,
  isOrphaned,
  lastActivity,
  listRuns,
  markRun,
  parseMeta,
  readMeta,
  renderTask,
  resultIsDone,
  runFiles,
  settleFromResult,
  type RunMeta,
} from '../src/runs.ts';
import { tempDir } from './helpers.ts';

const spec = { name: 'docs', task: 'Update the README.', paths: ['README.md'], done: 'README lists install steps', cwd: '/w', resultFile: '/s/result.md', brain: true };

function meta(id: string, createdAt: string): RunMeta {
  return {
    id, name: 'docs', role: 'worker', modelId: 'm', modelLabel: 'M', runner: 'api', cwd: '/w',
    paths: [], done: '', status: 'running', createdAt,
  };
}

test('task file carries task, paths, done criterion and protocol', () => {
  const text = renderTask(spec);
  assert.match(text, /^# Task: docs/);
  assert.match(text, /- `README\.md`/);
  assert.match(text, /README lists install steps/);
  assert.match(text, /`\/s\/result\.md`/);
  assert.match(text, /exactly `DONE`/);
  assert.match(text, /brain search/);
});

test('knowledge search step can be switched off per task', () => {
  const text = renderTask({ ...spec, brain: false });
  assert.doesNotMatch(text, /brain search "/);
  assert.match(text, /Knowledge search is switched off/);
});

test('empty paths and done criterion get explicit defaults', () => {
  const text = renderTask({ ...spec, paths: [], done: '' });
  assert.match(text, /none given/);
  assert.match(text, /Not given/);
});

test('DONE marker: last non-empty line only', () => {
  assert.equal(resultIsDone('## What\nx\n\nDONE\n\n'), true);
  assert.equal(resultIsDone('DONE\nmore'), false);
  assert.equal(resultIsDone('FAILED: x'), false);
  assert.equal(resultIsDone(''), false);
  assert.equal(resultIsDone('  DONE  '), true);
});

test('parseMeta tolerates garbage and unknown status', () => {
  assert.equal(parseMeta('nope'), undefined);
  assert.equal(parseMeta('{}'), undefined);
  assert.equal(parseMeta(JSON.stringify({ id: 'a', name: 'b', status: 'weird' }))?.status, 'failed');
});

test('create, list, settle and mark runs', async () => {
  const dir = await tempDir();
  await createRun(dir, meta('20260101-000000-aaaa', '2026-01-01T00:00:00Z'), 'task a');
  await createRun(dir, meta('20260102-000000-bbbb', '2026-01-02T00:00:00Z'), 'task b');
  assert.deepEqual((await listRuns(dir)).map((r) => r.id), ['20260102-000000-bbbb', '20260101-000000-aaaa']);
  assert.equal(await readFile(runFiles(dir, '20260101-000000-aaaa').task, 'utf8'), 'task a');

  assert.equal(await settleFromResult(dir, '20260101-000000-aaaa'), undefined, 'no result yet');
  await writeFile(runFiles(dir, '20260101-000000-aaaa').result, 'ok\nDONE\n');
  assert.equal((await settleFromResult(dir, '20260101-000000-aaaa'))?.status, 'done');
  assert.equal(await settleFromResult(dir, '20260101-000000-aaaa'), undefined, 'already settled');

  await writeFile(runFiles(dir, '20260102-000000-bbbb').result, 'half\nFAILED: no access\n');
  const failed = await settleFromResult(dir, '20260102-000000-bbbb');
  assert.equal(failed?.status, 'failed');
  assert.equal(failed?.reason, 'FAILED: no access');

  await createRun(dir, meta('20260103-000000-cccc', '2026-01-03T00:00:00Z'), 'task c');
  assert.equal((await markRun(dir, '20260103-000000-cccc', 'stopped', 'by user'))?.status, 'stopped');
  assert.equal((await markRun(dir, '20260103-000000-cccc', 'failed'))?.status, 'stopped', 'a settled run stays');
  assert.equal((await readMeta(dir, '20260103-000000-cccc'))?.reason, 'by user');
  assert.deepEqual(await listRuns(`${dir}/missing`), []);
});

test('only runs of a vanished extension host are orphaned', () => {
  const base = meta('x', '2026-01-01T00:00:00Z');
  assert.equal(isOrphaned({ ...base, owner: 111 }, () => false), true);
  assert.equal(isOrphaned({ ...base, owner: 111 }, () => true), false, 'another live window owns it');
  assert.equal(isOrphaned({ ...base, owner: process.pid }, () => false), false);
  assert.equal(isOrphaned({ ...base }, () => false), true, 'no owner recorded');
  assert.equal(isOrphaned({ ...base, status: 'done', owner: 111 }, () => false), false);
});

test('archiving moves finished runs and keeps running ones', async () => {
  const dir = await tempDir();
  await createRun(dir, meta('a-run', '2026-01-01T00:00:00Z'), 'task');
  await createRun(dir, { ...meta('b-done', '2026-01-02T00:00:00Z'), status: 'done' }, 'task');
  await createRun(dir, { ...meta('c-failed', '2026-01-03T00:00:00Z'), status: 'failed' }, 'task');
  assert.ok(await lastActivity(dir, 'a-run'));
  assert.equal(await lastActivity(dir, 'nope'), undefined);
  assert.deepEqual(await archiveRuns(dir, 0, ['b-done']), ['b-done']);
  assert.deepEqual((await listRuns(dir)).map((r) => r.id), ['c-failed', 'a-run']);
  assert.deepEqual(await archiveRuns(dir), ['c-failed']);
  assert.deepEqual((await listRuns(dir)).map((r) => r.id), ['a-run']);
  assert.ok(await readFile(join(dir, 'archive', 'b-done', 'task.md'), 'utf8'));
  assert.deepEqual(await archiveRuns(dir), []);
});
