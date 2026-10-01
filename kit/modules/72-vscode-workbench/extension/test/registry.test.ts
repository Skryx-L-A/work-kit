import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  BUILTIN_HARNESSES,
  BUILTIN_MODELS,
  BUILTIN_PROVIDERS,
  dataStaysLocal,
  effectiveRegistry,
  EMPTY_REGISTRY,
  fillArgs,
  fillPlaceholders,
  findHarness,
  findModel,
  findProvider,
  modelsForRole,
  parseRegistry,
  runnerOf,
  unknownPlaceholders,
} from '../src/registry.ts';

test('broken or missing registry files give an empty registry', () => {
  assert.deepEqual(parseRegistry(undefined), EMPTY_REGISTRY);
  assert.deepEqual(parseRegistry('{not json'), EMPTY_REGISTRY);
  assert.deepEqual(parseRegistry('[]'), EMPTY_REGISTRY);
});

test('each entry is validated on its own', () => {
  const r = parseRegistry(JSON.stringify({
    version: 2,
    providers: [{ id: 'p1', label: 'P1', kind: 'local', baseUrl: 'http://127.0.0.1:9000/v1' }, { id: 'bad', kind: 'nope' }],
    harnesses: [{ id: 'h1', command: 'h1' }, { id: 'nocommand' }],
    models: [{ id: 'm1', harness: 'h1', provider: 'p1' }, { id: 'm2' }, 'garbage'],
  }));
  assert.equal(r.version, 2);
  assert.deepEqual(r.providers.map((p) => p.id), ['p1']);
  assert.equal(r.providers[0].api, 'openai');
  assert.deepEqual(r.harnesses.map((h) => h.id), ['h1']);
  assert.equal(r.harnesses[0].runner, 'terminal');
  assert.deepEqual(r.models.map((m) => m.id), ['m1']);
  assert.equal(r.models[0].modelRef, 'm1');
  assert.deepEqual(r.models[0].roles, ['worker']);
  assert.equal(r.models[0].enabled, true);
});

test('the terminal workbench registry spelling is understood', () => {
  const r = parseRegistry(JSON.stringify({
    providers: [{ id: 'ollama2', label: 'Ollama', kind: 'local', baseUrl: 'http://127.0.0.1:11434' }],
    harnesses: [{
      id: 'x', label: 'X', command: 'x', args: ['--model', '{model}'],
      effort: { style: 'arg', args: ['--effort', '{effort}'], map: { high: 'hi' } },
      autonomy: { args: ['--yes'] },
      readyPattern: 'ignored',
    }, {
      id: 'y', label: 'Y', command: 'y', effort: { style: 'none', args: [] },
    }],
    models: [{ id: 'a', label: 'A', harness: 'x', provider: 'ollama2', modelRef: 'qwen:8b', roles: ['worker', 'orchestrator', 'bogus'], machines: ['mac'] }],
  }));
  assert.equal(r.providers[0].api, 'ollama');
  const x = r.harnesses[0];
  assert.deepEqual(x.effortArgs, ['--effort', '{effort}']);
  assert.deepEqual(x.effortMap, { high: 'hi' });
  assert.deepEqual(x.autonomyArgs, ['--yes']);
  assert.equal(r.harnesses[1].effortArgs, undefined);
  assert.deepEqual(r.models[0].roles, ['worker', 'orchestrator']);
});

test('file entries override built-ins with the same id, run-time models are added', () => {
  const file = parseRegistry(JSON.stringify({
    providers: [{ id: 'ollama', label: 'Remote-free Ollama', kind: 'local', baseUrl: 'http://127.0.0.1:11999' }],
    models: [{ id: 'claude-sonnet', label: 'Mine', harness: 'claude', provider: 'claude-subscription', modelRef: 'sonnet', enabled: false }],
  }));
  const extra = [{ ...BUILTIN_MODELS[0], id: 'vscode-lm:copilot/gpt-x', harness: 'vscode-lm', provider: 'vscode-lm', source: 'vscode-lm' as const }];
  const r = effectiveRegistry(file, extra);
  assert.equal(findProvider(r, 'ollama')?.baseUrl, 'http://127.0.0.1:11999');
  assert.equal(r.providers.length, BUILTIN_PROVIDERS.length);
  assert.equal(findModel(r, 'claude-sonnet')?.label, 'Mine');
  assert.ok(!modelsForRole(r, 'worker').some((m) => m.id === 'claude-sonnet'));
  assert.equal(runnerOf(r, findModel(r, 'vscode-lm:copilot/gpt-x')!), 'vscode-lm');
});

test('built-ins cover the VS Code LM API, the HTTP API and every terminal harness', () => {
  const r = effectiveRegistry(EMPTY_REGISTRY);
  assert.equal(findHarness(r, 'vscode-lm')?.runner, 'vscode-lm');
  assert.equal(findHarness(r, 'api')?.runner, 'api');
  assert.equal(findProvider(r, 'vscode-lm')?.kind, 'vscode');
  for (const h of BUILTIN_HARNESSES.filter((b) => b.runner === 'terminal')) {
    const m = findModel(r, `${h.id}-default`);
    assert.ok(m, `default model for ${h.id}`);
    assert.equal(m.modelRef, '');
    assert.ok(findProvider(r, m.provider), `provider of ${m.id}`);
    for (const arg of [...(h.args ?? []), ...(h.promptArgs ?? []), ...Object.values(h.env ?? {})]) {
      assert.deepEqual(unknownPlaceholders(arg), [], `${h.id}: ${arg}`);
    }
  }
  for (const p of BUILTIN_PROVIDERS.filter((b) => b.api === 'openai' || b.api === 'ollama')) {
    assert.match(p.baseUrl ?? '', /^https?:\/\//, p.id);
  }
});

test('placeholders fill, and an empty value drops its option flag', () => {
  const r = effectiveRegistry(EMPTY_REGISTRY);
  assert.deepEqual(fillArgs(['--model', '{model}', '--x'], { model: 'm' }), ['--model', 'm', '--x']);
  assert.deepEqual(fillArgs(['--model', '{model}', '--x'], {}), ['--x']);
  assert.deepEqual(fillArgs(['-c', 'model_reasoning_effort={effort}'], {}), []);
  assert.deepEqual(fillArgs(['{prompt}'], { prompt: 'hi there' }), ['hi there']);
  assert.equal(fillPlaceholders('{baseUrl:ollama}/v1', {}, r), 'http://127.0.0.1:11434/v1');
  assert.equal(fillPlaceholders('{unknown}', {}), '{unknown}');
  assert.deepEqual(unknownPlaceholders('{model} {secret:x} {baseUrl:y}'), ['secret:x']);
});

test('data locality: model override, provider override, local kind', () => {
  const r = effectiveRegistry(EMPTY_REGISTRY);
  const m = { ...BUILTIN_MODELS[0] };
  assert.equal(dataStaysLocal(m, findProvider(r, 'ollama')), true);
  assert.equal(dataStaysLocal(m, findProvider(r, 'openai')), false);
  assert.equal(dataStaysLocal(m, findProvider(r, 'vscode-lm')), false);
  assert.equal(dataStaysLocal(m, undefined), false);
  assert.equal(dataStaysLocal({ ...m, dataStaysLocal: true }, findProvider(r, 'openai')), true);
  assert.equal(dataStaysLocal(m, { ...findProvider(r, 'openai')!, dataStaysLocal: true }), true);
});
