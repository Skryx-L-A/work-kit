import assert from 'node:assert/strict';
import { test } from 'node:test';
import { orchestratorPrompt, terminalLaunch, workerPrompt } from '../src/commandLine.ts';
import { EMPTY_REGISTRY, effectiveRegistry, findHarness, findModel } from '../src/registry.ts';

const r = effectiveRegistry(EMPTY_REGISTRY);
const opts = { name: 'docs', cwd: '/w', prompt: 'Read /s/task.md', autonomy: false };

test('claude worker: model, prompt as positional argument, no autonomy by default', () => {
  const l = terminalLaunch(r, findHarness(r, 'claude')!, findModel(r, 'claude-sonnet')!, opts);
  assert.equal(l.commandLine, `'claude' '--model' 'sonnet' 'Read /s/task.md'`);
  assert.equal(l.sendPromptAfterStart, false);
  const auto = terminalLaunch(r, findHarness(r, 'claude')!, findModel(r, 'claude-sonnet')!, { ...opts, autonomy: true, effort: 'high' });
  assert.equal(auto.commandLine, `'claude' '--model' 'sonnet' '--effort' 'high' '--dangerously-skip-permissions' 'Read /s/task.md'`);
});

test('a default model drops --model; codex effort uses -c', () => {
  const l = terminalLaunch(r, findHarness(r, 'codex')!, findModel(r, 'codex-default')!, { ...opts, effort: 'low' });
  assert.equal(l.commandLine, `'codex' '-c' 'model_reasoning_effort=low' 'Read /s/task.md'`);
});

test('env templates: empty values are dropped, baseUrl is filled', () => {
  const copilot = terminalLaunch(r, findHarness(r, 'copilot')!, findModel(r, 'copilot-default')!, opts);
  assert.equal(copilot.env.COPILOT_MODEL, undefined);
  assert.equal(copilot.env.BROWSER, 'true');
  assert.equal(copilot.commandLine, `'copilot' '-i' 'Read /s/task.md'`);
  const goose = terminalLaunch(r, findHarness(r, 'goose')!, { ...findModel(r, 'goose-default')!, modelRef: 'qwen3:8b' }, opts);
  assert.equal(goose.env.GOOSE_MODEL, 'qwen3:8b');
  assert.equal(goose.env.OLLAMA_HOST, 'http://127.0.0.1:11434');
  assert.equal(goose.sendPromptAfterStart, true);
});

test('effort map translates or drops the effort', () => {
  const h = { ...findHarness(r, 'claude')!, effortMap: { high: 'max' } };
  const m = findModel(r, 'claude-opus')!;
  assert.match(terminalLaunch(r, h, m, { ...opts, effort: 'high' }).commandLine, /'--effort' 'max'/);
  assert.doesNotMatch(terminalLaunch(r, h, m, { ...opts, effort: 'low' }).commandLine, /--effort/);
});

test('API harnesses are refused', () => {
  assert.throws(() => terminalLaunch(r, findHarness(r, 'api')!, findModel(r, 'claude-sonnet')!, opts), /does not run in a terminal/);
});

test('prompts point at the protocol files', () => {
  assert.match(workerPrompt('/r/task.md', '/r/result.md'), /\/r\/task\.md.*\/r\/result\.md.*DONE/);
  assert.match(orchestratorPrompt('/s/ORCHESTRATOR.md'), /\/s\/ORCHESTRATOR\.md/);
});
