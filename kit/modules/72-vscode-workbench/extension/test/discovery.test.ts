import assert from 'node:assert/strict';
import { test } from 'node:test';
import { discoverProvider, modelsUrl, parseModelList } from '../src/discovery.ts';
import { BUILTIN_PROVIDERS, type Provider } from '../src/registry.ts';
import { startFakeOpenAi } from './fakeOpenAi.ts';

const ollama = BUILTIN_PROVIDERS.find((p) => p.id === 'ollama')!;
const llamacpp = BUILTIN_PROVIDERS.find((p) => p.id === 'llamacpp')!;
const openai = BUILTIN_PROVIDERS.find((p) => p.id === 'openai')!;

test('model list URLs', () => {
  assert.equal(modelsUrl(ollama), 'http://127.0.0.1:11434/api/tags');
  assert.equal(modelsUrl(llamacpp), 'http://127.0.0.1:8080/v1/models');
  assert.equal(modelsUrl({ ...llamacpp, baseUrl: undefined }), undefined);
});

test('model list parsing', () => {
  assert.deepEqual(parseModelList(ollama, { models: [{ name: 'qwen3:8b' }, { model: 'x' }, {}] }), ['qwen3:8b', 'x']);
  assert.deepEqual(parseModelList(llamacpp, { data: [{ id: 'a' }] }), ['a']);
  assert.deepEqual(parseModelList(llamacpp, 'garbage'), []);
});

test('discovery talks to local providers only', async () => {
  await assert.rejects(discoverProvider(openai), /not local/);
  const server = await startFakeOpenAi(() => [500, {}], ['m1', 'm2']);
  try {
    const local: Provider = { ...llamacpp, id: 'test-local', baseUrl: `${server.url}/v1` };
    const models = await discoverProvider(local);
    assert.deepEqual(models.map((m) => m.id), ['test-local:m1', 'test-local:m2']);
    assert.equal(models[0].harness, 'api');
    assert.equal(models[0].source, 'discovered');
    const tags = await discoverProvider({ ...ollama, id: 'test-ollama', baseUrl: server.url });
    assert.deepEqual(tags.map((m) => m.modelRef), ['m1', 'm2']);
  } finally {
    await server.close();
  }
});
