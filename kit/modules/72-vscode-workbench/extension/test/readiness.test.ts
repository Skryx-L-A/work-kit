import assert from 'node:assert/strict';
import { test } from 'node:test';
import { modelChoices, modelReadiness, type ReadinessFacts } from '../src/readiness.ts';
import { effectiveRegistry, parseRegistry } from '../src/registry.ts';

const registry = effectiveRegistry(parseRegistry(JSON.stringify({
  version: 1,
  providers: [{ id: 'local', label: 'Local', kind: 'local', baseUrl: 'http://127.0.0.1:9/v1' }],
  harnesses: [{ id: 'nope', label: 'Missing CLI', command: 'no-such-cli' }],
  models: [
    { id: 'local:a', harness: 'api', provider: 'local', modelRef: 'a' },
    { id: 'cloud:b', harness: 'api', provider: 'openai', modelRef: 'b' },
    { id: 'missing-cli', harness: 'nope', provider: 'local' },
    { id: 'off', harness: 'api', provider: 'local', enabled: false },
    { id: 'no-harness', harness: 'unknown', provider: 'local' },
  ],
})), [{ id: 'vscode-lm:v/x', label: 'X', harness: 'vscode-lm', provider: 'vscode-lm', modelRef: 'x', roles: ['worker'], enabled: true, source: 'vscode-lm' }]);

const facts: ReadinessFacts = {
  commandFound: (c) => c === 'claude',
  hasKey: () => false,
  lmIds: new Set(['vscode-lm:v/x']),
};

function readiness(id: string, f: ReadinessFacts = facts) {
  const model = registry.models.find((m) => m.id === id);
  assert.ok(model, id);
  return modelReadiness(registry, model, f);
}

test('readiness per runner', () => {
  assert.equal(readiness('local:a'), 'ready');
  assert.equal(readiness('cloud:b'), 'no-key');
  assert.equal(readiness('cloud:b', { ...facts, hasKey: (p) => p === 'openai' }), 'ready');
  assert.equal(readiness('missing-cli'), 'cli-missing');
  assert.equal(readiness('claude-sonnet'), 'ready');
  assert.equal(readiness('codex-default'), 'cli-missing');
  assert.equal(readiness('vscode-lm:v/x'), 'ready');
  assert.equal(readiness('vscode-lm:v/x', { ...facts, lmIds: new Set() }), 'unavailable');
  assert.equal(readiness('no-harness'), 'unavailable');
});

test('disabled models report disabled first', () => {
  const off = parseRegistry(JSON.stringify({ models: [{ id: 'off', harness: 'api', provider: 'local', enabled: false }] })).models[0];
  assert.ok(off, 'disabled entries are kept in the file registry');
  assert.equal(modelReadiness(registry, off, facts), 'disabled');
});

test('choices list ready models first and mark locality', () => {
  const choices = modelChoices(registry, registry.models.filter((m) => ['cloud:b', 'local:a', 'missing-cli'].includes(m.id)), facts);
  assert.deepEqual(choices.map((c) => c.model.id), ['local:a', 'cloud:b', 'missing-cli']);
  assert.equal(choices[0].local, true);
  assert.equal(choices[1].local, false);
  assert.equal(choices[0].runner, 'api');
});
