// Runs inside the VS Code extension host (extensionTestsPath). No test framework: plain asserts,
// results go to <workspace>/.kitwb-host-result.json, a thrown error fails the run.
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const fs = require('node:fs/promises');
const path = require('node:path');
const vscode = require('vscode');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(what, fn, timeoutMs = 60000) {
  const end = Date.now() + timeoutMs;
  for (;;) {
    const value = await fn();
    if (value) return value;
    if (Date.now() > end) throw new Error(`timeout waiting for ${what}`);
    await sleep(250);
  }
}

async function runEnded(workbench, id) {
  const run = (await workbench.runs()).find((r) => r.id === id);
  return run && run.status !== 'running' ? run : undefined;
}

exports.run = async function run() {
  const workspace = vscode.workspace.workspaceFolders[0].uri.fsPath;
  const config = JSON.parse(await fs.readFile(path.join(workspace, '.kitwb-host-config.json'), 'utf8'));
  const checks = [];
  const check = async (name, fn) => {
    try {
      await fn();
      checks.push({ name, ok: true });
    } catch (error) {
      checks.push({ name, ok: false, error: String(error && error.stack || error) });
    }
  };
  try {
    const ext = vscode.extensions.getExtension('work-kit.kit-workbench');
    await check('extension is present and activates', async () => {
      assert.ok(ext, 'extension found');
      await ext.activate();
      assert.equal(ext.isActive, true);
    });
    const workbench = ext.exports.workbench;

    await check('commands are registered', async () => {
      const all = await vscode.commands.getCommands(true);
      for (const c of ['kitWorkbench.spawnWorker', 'kitWorkbench.startOrchestratorTerminal', 'kitWorkbench.openOrchestratorPanel',
        'kitWorkbench.stopWorker', 'kitWorkbench.listModels', 'kitWorkbench.discoverModels', 'kitWorkbench.setApiKey',
        'kitWorkbench.openOverview', 'kitWorkbench.viewResult', 'kitWorkbench.rerunWorker', 'kitWorkbench.spawnFromTemplate',
        'kitWorkbench.setDefaultWorkerModel', 'kitWorkbench.archiveRuns', 'kitWorkbench.sendSelectionToOrchestrator',
        'kitWorkbench.sendFileToOrchestrator', 'kitWorkbench.refreshStatus', 'kitWorkbench.openTemplatesFolder']) {
        assert.ok(all.includes(c), c);
      }
    });

    await check('language model tools are registered', async () => {
      const names = (vscode.lm.tools || []).map((t) => t.name);
      for (const t of ['kit_spawn_worker', 'kit_list_workers', 'kit_read_result', 'kit_brain_search', 'kit_read_skill']) {
        assert.ok(names.includes(t), `${t} in ${names.join(',')}`);
      }
    });

    await check('registry: file models, built-ins and state dir from settings', async () => {
      assert.equal(workbench.stateDir, config.stateDir);
      const reg = await workbench.registry();
      assert.ok(reg.models.some((m) => m.id === 'fake-local:scripted'));
      assert.ok(reg.models.some((m) => m.id === 'claude-sonnet'));
      const text = await vscode.commands.executeCommand('kitWorkbench.listModels');
      assert.match(text, /fake-local:scripted/);
      await vscode.commands.executeCommand('workbench.action.closeActiveEditor');
    });

    await check('discovery finds models of a local provider', async () => {
      const lines = await vscode.commands.executeCommand('kitWorkbench.discoverModels');
      assert.ok(lines.some((l) => /Fake local: 1 models/.test(l)), lines.join(' | '));
    });

    await check('API worker over an OpenAI-compatible server completes the protocol', async () => {
      const r = await workbench.spawn({ name: 'api-worker', task: 'Write out/hello.txt', model: 'fake-local:scripted', paths: ['out/'], done: 'file exists' }, 'test');
      const run = await waitFor('api worker', () => runEnded(workbench, r.runId));
      assert.equal(run.status, 'done', JSON.stringify(run));
      assert.equal(await fs.readFile(path.join(workspace, 'out/hello.txt'), 'utf8'), 'from the fake server');
      assert.match(await fs.readFile(r.resultFile, 'utf8'), /DONE\n$/);
      const log = await fs.readFile(path.join(config.stateDir, 'runs', r.runId, 'log.jsonl'), 'utf8');
      assert.match(log, /"write_file"/);
      assert.match(await fs.readFile(path.join(config.stateDir, 'runs', r.runId, 'task.md'), 'utf8'), /brain search/);
    });

    await check('vscode.lm provider: worker with a VS Code language model', async () => {
      const models = await vscode.lm.selectChatModels({ vendor: 'kit-test' });
      assert.equal(models.length, 1, 'test model visible through vscode.lm');
      const id = `vscode-lm:kit-test/${models[0].id}`;
      const reg = await workbench.registry();
      assert.ok(reg.models.some((m) => m.id === id), 'vscode.lm model in the registry');
      const r = await workbench.spawn({ name: 'lm-worker', task: 'Write lm-out/hello.txt', model: id, paths: ['lm-out/'], done: 'file exists' }, 'test');
      const run = await waitFor('lm worker', () => runEnded(workbench, r.runId));
      assert.equal(run.status, 'done', JSON.stringify(run));
      assert.equal(await fs.readFile(path.join(workspace, 'lm-out/hello.txt'), 'utf8'), 'from vscode.lm');
      assert.match(await fs.readFile(r.resultFile, 'utf8'), /saw task: true/);
    });

    await check('terminal worker writes its result and is visible', async () => {
      const r = await workbench.spawn({ name: 'term-worker', task: 'Write the result', model: 'fake-cli-default', paths: [], done: '' }, 'test');
      const run = await waitFor('terminal worker', () => runEnded(workbench, r.runId));
      assert.equal(run.status, 'done', JSON.stringify(run));
      const terminal = vscode.window.terminals.find((t) => t.name === 'worker: term-worker');
      assert.ok(terminal, 'worker terminal exists');
      assert.equal(vscode.window.activeTerminal && vscode.window.activeTerminal.name, 'worker: term-worker', 'worker terminal is shown');
      terminal.dispose();
    });

    await check('kit-wb spawn from a terminal orchestrator becomes a run', async () => {
      const out = await new Promise((resolve, reject) => {
        const child = execFile('bash', [config.kitWb, 'spawn', '--name', 'from-cli', '--model', 'fake-local:scripted', '--paths', 'out/', '--no-brain', '--timeout', '30', '-'],
          { env: { ...process.env, KIT_WB_STATE: config.stateDir }, cwd: workspace },
          (error, stdout, stderr) => (error ? reject(new Error(stderr || error.message)) : resolve(stdout)));
        child.stdin.end('Write out/hello.txt again');
      });
      const id = out.trim();
      const run = await waitFor('kit-wb run', () => runEnded(workbench, id));
      assert.equal(run.status, 'done');
      assert.equal(run.origin, 'request');
      assert.match(await fs.readFile(path.join(config.stateDir, 'runs', id, 'task.md'), 'utf8'), /Knowledge search is switched off/);
    });

    await check('orchestrator turn delegates through spawn_worker', async () => {
      const reg = await workbench.registry();
      const model = reg.models.find((m) => m.id === 'fake-local:orchestrate');
      const backend = await workbench.backendFor(reg, model);
      const events = [];
      const history = await workbench.orchestratorTurn(backend, [{ role: 'user', content: 'Please write hello.' }], 'panel',
        new AbortController().signal, (e) => events.push(e.type));
      const last = history[history.length - 1];
      assert.match(last.content, /Started run (\S+)/);
      const id = /Started run (\S+)/.exec(last.content)[1];
      const run = await waitFor('delegated run', () => runEnded(workbench, id));
      assert.equal(run.status, 'done');
      assert.equal(run.origin, 'panel');
      assert.deepEqual(events.slice(0, 2), ['text', 'tool-call']);
    });

    await check('model picker data: readiness per model, ready ones first', async () => {
      const choices = await workbench.modelChoices('worker');
      const by = Object.fromEntries(choices.map((c) => [c.model.id, c]));
      assert.equal(by['fake-local:scripted'].readiness, 'ready');
      assert.equal(by['fake-local:scripted'].local, true);
      assert.equal(by['missing-cli-model'].readiness, 'cli-missing');
      assert.equal(by['fake-cli-default'].readiness, 'ready');
      const firstNotReady = choices.findIndex((c) => c.readiness !== 'ready');
      assert.ok(choices.slice(firstNotReady).every((c) => c.readiness !== 'ready'), 'ready models come first');
    });

    await check('status view: brain, skills, rules, data guard, models', async () => {
      const items = await workbench.status(true);
      const by = Object.fromEntries(items.map((i) => [i.id, i]));
      assert.equal(by.brain.level, 'ok', JSON.stringify(by.brain));
      assert.match(by.brain.more.join('\n'), /no notes for: status/);
      assert.equal(by.skills.detail, '1 installed');
      assert.equal(by.rules.level, 'ok');
      assert.ok(by.dataGuard, 'data guard item present');
      assert.match(by.models.detail, /ready/);
    });

    await check('task template: user and built-in templates, spawn with filled values', async () => {
      const templates = await workbench.templates();
      assert.ok(templates.some((t) => t.name === 'host-template' && t.source === 'user'));
      assert.ok(templates.some((t) => t.name === 'code-review' && t.source === 'builtin'));
      const id = await vscode.commands.executeCommand('kitWorkbench.spawnFromTemplate', { template: 'host-template', values: { file: 'out/hello.txt' } });
      assert.ok(id, 'run id returned');
      const run = await waitFor('template run', () => runEnded(workbench, id));
      assert.equal(run.status, 'done', JSON.stringify(run));
      assert.equal(run.origin, 'template');
      assert.equal(run.modelId, 'fake-local:scripted');
      assert.equal(run.done, 'out/hello.txt exists');
      const task = await fs.readFile(path.join(config.stateDir, 'runs', id, 'task.md'), 'utf8');
      assert.match(task, /Write out\/hello\.txt\./);
      assert.match(task, /skill `test-skill`/);
    });

    await check('worker overview renders cards and status chips', async () => {
      const html = await vscode.commands.executeCommand('kitWorkbench.openOverview');
      assert.match(html, /api-worker/);
      assert.match(html, /host-template/);
      assert.match(html, /Brain:/);
      assert.match(html, /data-action="rerun"/);
      await vscode.commands.executeCommand('workbench.action.closeActiveEditor');
    });

    await check('result view shows sections and the DONE outcome', async () => {
      const done = (await workbench.runs()).find((r) => r.name === 'api-worker' && r.status === 'done');
      const html = await vscode.commands.executeCommand('kitWorkbench.viewResult', done.id);
      assert.match(html, /<h2>What<\/h2>/);
      assert.match(html, /Ends with DONE/);
      assert.match(html, /write_file/);
      await vscode.commands.executeCommand('workbench.action.closeActiveEditor');
    });

    await check('run again with another model keeps task, paths and done criterion', async () => {
      const first = (await workbench.runs()).find((r) => r.name === 'term-worker');
      const again = (await workbench.runs()).find((r) => r.name === 'api-worker' && r.status === 'done');
      const id = await vscode.commands.executeCommand('kitWorkbench.rerunWorker', again.id, 'fake-local:scripted');
      const run = await waitFor('rerun', () => runEnded(workbench, id));
      assert.equal(run.status, 'done', JSON.stringify(run));
      assert.equal(run.origin, 'rerun');
      assert.deepEqual(run.paths, again.paths);
      assert.equal(run.done, again.done);
      const task = await fs.readFile(path.join(config.stateDir, 'runs', id, 'task.md'), 'utf8');
      assert.match(task, /^# Task: api-worker\n\nWrite out\/hello\.txt\n/);
      assert.ok(first, 'terminal run still listed');
    });

    await check('default worker model is set through the picker command', async () => {
      const cfg = () => vscode.workspace.getConfiguration('kitWorkbench');
      assert.equal(await vscode.commands.executeCommand('kitWorkbench.setDefaultWorkerModel', 'fake-local:scripted'), 'fake-local:scripted');
      assert.equal(cfg().get('defaultWorkerModel'), 'fake-local:scripted');
      await cfg().update('defaultWorkerModel', undefined, vscode.ConfigurationTarget.Global);
    });

    await check('send selection goes to the orchestrator panel input', async () => {
      const file = path.join(workspace, 'out', 'hello.txt');
      const doc = await vscode.workspace.openTextDocument(file);
      const editor = await vscode.window.showTextDocument(doc);
      editor.selection = new vscode.Selection(0, 0, 0, 4);
      const target = await vscode.commands.executeCommand('kitWorkbench.sendSelectionToOrchestrator');
      assert.equal(target, 'panel');
      await vscode.commands.executeCommand('workbench.action.closeAllEditors');
    });

    await check('stop ends a running API worker', async () => {
      const r = await workbench.spawn({ name: 'slow', task: 'slow', model: 'fake-local:slow', paths: ['out/'], done: '' }, 'test');
      await sleep(300);
      await workbench.stop(r.runId);
      const run = await waitFor('stopped', () => runEnded(workbench, r.runId));
      assert.equal(run.status, 'stopped');
    });

    await check('archive moves finished runs out of the lists, nothing deleted', async () => {
      const before = (await workbench.runs()).filter((r) => r.status !== 'running').map((r) => r.id);
      assert.ok(before.length > 0);
      const moved = await vscode.commands.executeCommand('kitWorkbench.archiveRuns', 'confirmed');
      assert.deepEqual([...moved].sort(), [...before].sort());
      assert.equal((await workbench.runs()).filter((r) => r.status !== 'running').length, 0);
      await fs.access(path.join(config.stateDir, 'archive', before[0], 'meta.json'));
    });

    await check('orchestrator guide references existing files', async () => {
      const guide = await workbench.orchestratorGuide();
      const text = await fs.readFile(guide, 'utf8');
      const kitWb = /Full path of the command: `([^`]+)`/.exec(text)[1];
      await fs.access(kitWb);
      assert.match(text, /fake-local:scripted/);
    });
  } finally {
    await fs.writeFile(path.join(workspace, '.kitwb-host-result.json'), JSON.stringify(checks, null, 2));
  }
  const failed = checks.filter((c) => !c.ok);
  if (failed.length > 0) {
    throw new Error(`${failed.length} host checks failed: ${failed.map((f) => f.name).join('; ')}`);
  }
};
