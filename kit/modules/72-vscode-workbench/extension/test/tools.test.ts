import assert from 'node:assert/strict';
import { mkdir, readFile, symlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';
import type { ToolHandler } from '../src/agent/loop.ts';
import { orchestratorTools, resolveInside, spawnInputFrom, workerTools, writeAllowed, type WorkbenchApi } from '../src/agent/tools.ts';
import { Brain } from '../src/brain.ts';
import { tempDir } from './helpers.ts';

const signal = new AbortController().signal;
const byName = (tools: ToolHandler[], name: string) => tools.find((t) => t.spec.name === name)!;
const fakeBrain = new Brain('/nonexistent/brain-cli');

test('resolveInside rejects absolute paths, .. and symlink escapes', async () => {
  const root = await tempDir();
  const outside = await tempDir();
  await mkdir(join(root, 'src'));
  await symlink(outside, join(root, 'escape'));
  assert.equal(await resolveInside(root, 'src/a.ts'), join(root, 'src/a.ts'));
  await assert.rejects(resolveInside(root, '/etc/passwd'), /relative/);
  await assert.rejects(resolveInside(root, '../x'), /outside/);
  await assert.rejects(resolveInside(root, 'src/../../x'), /outside/);
  await assert.rejects(resolveInside(root, 'escape/file.txt'), /outside/);
  await assert.rejects(resolveInside(root, ''), /relative/);
});

test('writeAllowed follows the exclusive paths', () => {
  assert.equal(writeAllowed(['docs/', 'README.md'], 'docs/a.md'), true);
  assert.equal(writeAllowed(['docs/', 'README.md'], 'README.md'), true);
  assert.equal(writeAllowed(['docs'], 'docsx/a.md'), false);
  assert.equal(writeAllowed(['docs'], 'src/a.ts'), false);
  assert.equal(writeAllowed([], 'anything'), true);
  assert.equal(writeAllowed(['.'], 'x/y'), true);
});

test('worker tools read, list, write inside paths and finish with DONE', async () => {
  const root = await tempDir();
  const state = await tempDir();
  await writeFile(join(root, 'in.txt'), 'hello');
  const resultFile = join(state, 'runs/r1/result.md');
  const tools = workerTools({ cwd: root, paths: ['out/'], resultFile, brain: fakeBrain, skillsDir: join(root, 'no-skills') });
  assert.deepEqual(tools.map((t) => t.spec.name), ['read_file', 'list_dir', 'write_file', 'brain_search', 'read_skill', 'finish']);
  assert.equal((await byName(tools, 'read_file').run({ path: 'in.txt' }, signal)).content, 'hello');
  assert.match((await byName(tools, 'write_file').run({ path: 'in.txt', content: 'x' }, signal)).content, /not inside the exclusive paths/);
  assert.equal(await readFile(join(root, 'in.txt'), 'utf8'), 'hello');
  assert.match((await byName(tools, 'write_file').run({ path: 'out/new/file.md', content: 'new' }, signal)).content, /Wrote/);
  assert.equal(await readFile(join(root, 'out/new/file.md'), 'utf8'), 'new');
  assert.deepEqual((await byName(tools, 'list_dir').run({ path: '.' }, signal)).content.split('\n'), ['in.txt', 'out/']);
  assert.match((await byName(tools, 'brain_search').run({ query: 'x' }, signal)).content, /not installed/);
  assert.match((await byName(tools, 'read_skill').run({ name: 'x' }, signal)).content, /No skill/);
  const fin = await byName(tools, 'finish').run({ result: '## What\nDid it' }, signal);
  assert.equal(fin.stop, true);
  assert.equal(await readFile(resultFile, 'utf8'), '## What\nDid it\n\nDONE\n');
  await byName(tools, 'finish').run({ result: 'Could not', success: false }, signal);
  assert.match(await readFile(resultFile, 'utf8'), /FAILED: reported by the worker\n$/);
});

test('knowledge search switched off: no brain tool', () => {
  const worker = workerTools({ cwd: '/w', paths: [], resultFile: '/r', skillsDir: '/s' });
  assert.ok(!worker.some((t) => t.spec.name === 'brain_search'));
  const api: WorkbenchApi = { spawn: async () => ({ runId: '', model: '', resultFile: '' }), describeRuns: async () => '', describeModels: async () => '', readRun: async () => '' };
  assert.ok(!orchestratorTools(api, undefined, '/s', 't').some((t) => t.spec.name === 'brain_search'));
  assert.ok(orchestratorTools(api, fakeBrain, '/s', 't').some((t) => t.spec.name === 'brain_search'));
});

test('orchestrator tools call the workbench', async () => {
  const calls: string[] = [];
  const api: WorkbenchApi = {
    spawn: async (input, origin) => {
      calls.push(`spawn:${input.name}:${input.model}:${input.paths.join('|')}:${input.brain}:${origin}`);
      return { runId: 'R1', model: input.model ?? 'default', resultFile: '/r/result.md' };
    },
    describeRuns: async () => 'RUNS',
    describeModels: async () => 'MODELS',
    readRun: async (id) => `RUN ${id}`,
  };
  const tools = orchestratorTools(api, fakeBrain, '/s', 'chat');
  assert.match((await byName(tools, 'spawn_worker').run({ name: 'w', task: 't', model: 'm', paths: ['a', 'b'], brain: false }, signal)).content, /Started run R1/);
  assert.match((await byName(tools, 'spawn_worker').run({ name: 'w', task: ' ' }, signal)).content, /task is empty/);
  assert.equal((await byName(tools, 'list_workers').run({}, signal)).content, 'RUNS\n\nMODELS');
  assert.equal((await byName(tools, 'read_result').run({ runId: 'R1' }, signal)).content, 'RUN R1');
  assert.deepEqual(calls, ['spawn:w:m:a|b:false:chat']);
});

test('spawnInputFrom accepts comma-separated paths', () => {
  assert.deepEqual(spawnInputFrom({ name: 'x', task: 't', paths: 'a, b,' }).paths, ['a', 'b']);
  assert.equal(spawnInputFrom({ task: 't' }).name, 'worker');
  assert.equal(spawnInputFrom({ task: 't', brain: true }).brain, undefined);
});
