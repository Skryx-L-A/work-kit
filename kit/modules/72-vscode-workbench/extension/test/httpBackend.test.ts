import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chatCompletionsUrl, HttpBackend, parseCompletion, toOpenAiMessages } from '../src/agent/httpBackend.ts';
import { runAgentLoop, type ToolHandler } from '../src/agent/loop.ts';
import { completion, startFakeOpenAi } from './fakeOpenAi.ts';

test('chat completions URL per provider API', () => {
  assert.equal(chatCompletionsUrl('http://127.0.0.1:11434', 'ollama'), 'http://127.0.0.1:11434/v1/chat/completions');
  assert.equal(chatCompletionsUrl('http://127.0.0.1:11434/v1/', 'ollama'), 'http://127.0.0.1:11434/v1/chat/completions');
  assert.equal(chatCompletionsUrl('https://api.openai.com/v1/', 'openai'), 'https://api.openai.com/v1/chat/completions');
});

test('message translation to the OpenAI format', () => {
  const out = toOpenAiMessages([
    { role: 'system', content: 's' },
    { role: 'assistant', content: '', toolCalls: [{ id: 'c', name: 't', input: { a: 1 } }] },
    { role: 'tool', toolCallId: 'c', name: 't', content: 'r' },
  ]);
  assert.deepEqual(out, [
    { role: 'system', content: 's' },
    { role: 'assistant', content: null, tool_calls: [{ id: 'c', type: 'function', function: { name: 't', arguments: '{"a":1}' } }] },
    { role: 'tool', tool_call_id: 'c', content: 'r' },
  ]);
});

test('completion parsing tolerates missing ids and broken arguments', () => {
  const r = parseCompletion({ choices: [{ message: { content: null, tool_calls: [{ function: { name: 'x', arguments: '{bad' } }] } }] });
  assert.deepEqual(r, { text: '', toolCalls: [{ id: 'call_0', name: 'x', input: {} }] });
  assert.deepEqual(parseCompletion({}), { text: '', toolCalls: [] });
});

test('agent loop over HTTP: tools, auth header, and final answer', async () => {
  const server = await startFakeOpenAi((_body, i) => (i === 0
    ? [200, completion(null, [{ id: 'c1', name: 'echo', args: { v: 'x' } }])]
    : [200, completion('all done')]));
  try {
    const backend = new HttpBackend({ label: 'fake', url: `${server.url}/v1/chat/completions`, model: 'm-1', apiKey: 'test-key-not-secret' });
    const echo: ToolHandler = { spec: { name: 'echo', description: 'e', parameters: { type: 'object' } }, run: async (i) => ({ content: `got ${String(i.v)}` }) };
    const r = await runAgentLoop(backend, [{ role: 'user', content: 'go' }], [echo], { maxSteps: 5, signal: new AbortController().signal });
    assert.equal(r.finalText, 'all done');
    assert.equal(server.seen.length, 2);
    assert.equal(server.seen[0].headers.authorization, 'Bearer test-key-not-secret');
    assert.equal(server.seen[0].body.model, 'm-1');
    assert.equal(server.seen[0].body.tool_choice, 'auto');
    const second = server.seen[1].body.messages as Record<string, unknown>[];
    assert.deepEqual(second.at(-1), { role: 'tool', tool_call_id: 'c1', content: 'got x' });
  } finally {
    await server.close();
  }
});

test('HTTP errors surface status and body, never the key', async () => {
  const server = await startFakeOpenAi(() => [401, { error: 'invalid key' }]);
  try {
    const backend = new HttpBackend({ label: 'fake', url: `${server.url}/v1/chat/completions`, model: 'm', apiKey: 'sk-should-not-appear' });
    await assert.rejects(backend.send([], [], new AbortController().signal), (error: Error) => {
      assert.match(error.message, /HTTP 401/);
      assert.doesNotMatch(error.message, /sk-should-not-appear/);
      return true;
    });
    const noKey = new HttpBackend({ label: 'fake', url: `${server.url}/v1/chat/completions`, model: 'm' });
    await assert.rejects(noKey.send([], [], new AbortController().signal));
    assert.equal(server.seen[1].headers.authorization, undefined);
    assert.equal(server.seen[1].body.tools, undefined);
  } finally {
    await server.close();
  }
});
