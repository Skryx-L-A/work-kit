import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { acceptRequest, buildRequest, parseRequestFile, readRequest, rejectRequest, requestState } from '../src/requests.ts';
import { createRun, runFiles } from '../src/runs.ts';
import { tempDir } from './helpers.ts';

const KIT_WB = fileURLToPath(new URL('../resources/bin/kit-wb', import.meta.url));

function kitWb(state: string, args: string[], stdin?: string): Promise<{ code: number; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = execFile('bash', [KIT_WB, ...args], { env: { ...process.env, KIT_WB_STATE: state }, timeout: 20_000 }, (error, stdout, stderr) => {
      resolve({ code: error ? (typeof error.code === 'number' ? error.code : 1) : 0, stdout, stderr });
    });
    if (stdin !== undefined) {
      child.stdin?.end(stdin);
    }
  });
}

test('request file parsing and validation', () => {
  const fields = parseRequestFile('name=docs\nmodel=claude-sonnet\npaths=a, b ,\ndone=tests pass\ncwd=/w\nbrain=off\njunk line\n');
  const r = buildRequest(fields, 'Do it.');
  assert.ok(typeof r !== 'string');
  assert.deepEqual(r, { name: 'docs', model: 'claude-sonnet', paths: ['a', 'b'], done: 'tests pass', cwd: '/w', task: 'Do it.', brain: false });
  assert.equal(buildRequest({ name: '' }, 'x'), 'request has no name');
  assert.equal(buildRequest({ name: 'a' }, '  '), 'request has an empty task');
  assert.equal((buildRequest({ name: 'a', model: '' }, 'x') as { model?: string }).model, undefined);
});

test('request states follow the files', async () => {
  const dir = await tempDir();
  assert.equal(await requestState(dir), 'incomplete');
  await writeFile(join(dir, 'task.md'), 'x');
  await writeFile(join(dir, 'request'), 'name=a\n');
  assert.equal(await requestState(dir), 'pending');
  assert.deepEqual(await readRequest(dir), { name: 'a', model: undefined, paths: [], done: '', cwd: undefined, task: 'x', brain: undefined });
  await rejectRequest(dir, 'bad');
  assert.equal(await requestState(dir), 'rejected');
  await acceptRequest(dir, 'run-1');
  assert.equal(await requestState(dir), 'accepted');
});

test('kit-wb spawn writes a complete request and prints the run id', async () => {
  const state = await tempDir();
  const spawn = kitWb(state, ['spawn', '--name', 'docs', '--model', 'm1', '--paths', 'a,b', '--done', 'line1\nline2', '--no-brain', '--timeout', '15', '-'], 'Task text\n');
  // Play the extension: wait for the request, then accept it.
  let reqDir = '';
  for (let i = 0; i < 100 && !reqDir; i++) {
    await new Promise((r) => setTimeout(r, 100));
    const ids = await readdir(join(state, 'requests')).catch(() => []);
    for (const id of ids) {
      if ((await requestState(join(state, 'requests', id))) === 'pending') {
        reqDir = join(state, 'requests', id);
      }
    }
  }
  assert.ok(reqDir, 'request appeared');
  const request = await readRequest(reqDir);
  assert.ok(typeof request !== 'string');
  assert.equal(request.name, 'docs');
  assert.equal(request.model, 'm1');
  assert.deepEqual(request.paths, ['a', 'b']);
  assert.equal(request.done, 'line1 line2');
  assert.equal(request.brain, false);
  assert.equal(request.task, 'Task text\n');
  await acceptRequest(reqDir, 'RUN-42');
  const r = await spawn;
  assert.equal(r.code, 0, r.stderr);
  assert.equal(r.stdout.trim(), 'RUN-42');
});

test('kit-wb spawn reports a rejected request', async () => {
  const state = await tempDir();
  const spawn = kitWb(state, ['spawn', '--name', 'x', '--timeout', '15', '-'], 'T');
  for (let i = 0; i < 100; i++) {
    await new Promise((r) => setTimeout(r, 100));
    const ids = await readdir(join(state, 'requests')).catch(() => []);
    if (ids.length > 0 && (await requestState(join(state, 'requests', ids[0]))) === 'pending') {
      await rejectRequest(join(state, 'requests', ids[0]), 'Unknown model "x"');
      break;
    }
  }
  const r = await spawn;
  assert.notEqual(r.code, 0);
  assert.match(r.stderr, /request rejected: Unknown model "x"/);
});

test('kit-wb list, result and wait read the run files', async () => {
  const state = await tempDir();
  const id = '20260101-000000-aaaa';
  await createRun(state, {
    id, name: 'docs', role: 'worker', modelId: 'm', modelLabel: 'Model M', runner: 'api', cwd: '/w',
    paths: [], done: '', status: 'done', createdAt: '2026-01-01T00:00:00Z',
  }, 'task');
  await writeFile(runFiles(state, id).result, 'All good\nDONE\n');
  const list = await kitWb(state, ['list']);
  assert.match(list.stdout, new RegExp(`${id}\\s+done\\s+docs\\s+Model M`));
  const result = await kitWb(state, ['result', id]);
  assert.match(result.stdout, /status: done/);
  assert.match(result.stdout, /All good/);
  const wait = await kitWb(state, ['wait', id, '--timeout', '5']);
  assert.equal(wait.code, 0);
  const missing = await kitWb(state, ['result', 'nope']);
  assert.notEqual(missing.code, 0);
  const empty = await kitWb(`${state}/none`, ['list']);
  assert.equal(empty.stdout.trim(), 'no runs');
});

test('kit-wb refuses incomplete spawn calls', async () => {
  const state = await tempDir();
  assert.match((await kitWb(state, ['spawn', '-'], 'x')).stderr, /--name is required/);
  assert.match((await kitWb(state, ['spawn', '--name', 'a'])).stderr, /--task-file/);
  await mkdir(join(state, 'requests'), { recursive: true });
  assert.match((await kitWb(state, ['spawn', '--name', 'a', '-'], '')).stderr, /task is empty/);
  assert.deepEqual(await readdir(join(state, 'requests')), []);
  assert.equal((await readFile(KIT_WB, 'utf8')).startsWith('#!/usr/bin/env bash'), true);
});
