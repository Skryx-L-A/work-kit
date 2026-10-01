// The VS Code Language Model API provider, tested against a fake `lm` binding and model.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { LmBackend, toLmMessages, type LmBindings, type LmChatModel } from '../src/agent/lmBackend.ts';
import type { ChatMessage, ToolCall } from '../src/agent/loop.ts';

type Part = { kind: 'text'; value: string } | { kind: 'call'; callId: string; name: string; input: object } | { kind: 'result'; callId: string; content: unknown[] };
type Msg = { role: 'user' | 'assistant'; parts: Part[] };

function fakeBindings(log: { cancelled: number; disposed: number }): LmBindings {
  return {
    user: (parts) => ({ role: 'user', parts }) as Msg,
    assistant: (parts) => ({ role: 'assistant', parts }) as Msg,
    textPart: (value) => ({ kind: 'text', value }),
    toolCallPart: (callId, name, input) => ({ kind: 'call', callId, name, input }),
    toolResultPart: (callId, content) => ({ kind: 'result', callId, content }),
    textOf: (p) => ((p as Part).kind === 'text' ? (p as { value: string }).value : undefined),
    toolCallOf: (p) => {
      const part = p as Part;
      return part.kind === 'call' ? ({ id: part.callId, name: part.name, input: part.input as Record<string, unknown> } satisfies ToolCall) : undefined;
    },
    cancellation: (signal) => {
      const token = { isCancellationRequested: signal.aborted };
      signal.addEventListener('abort', () => {
        token.isCancellationRequested = true;
        log.cancelled++;
      });
      return { token, dispose: () => void log.disposed++ };
    },
    toolModeAuto: 'auto-mode',
  };
}

function fakeModel(response: Part[], seen: { messages?: unknown[]; options?: Record<string, unknown>; token?: unknown }): LmChatModel {
  return {
    id: 'gpt-test', name: 'GPT Test', vendor: 'copilot', family: 'gpt', maxInputTokens: 1000,
    sendRequest: async (messages, options, token) => {
      seen.messages = messages;
      seen.options = options;
      seen.token = token;
      return {
        stream: (async function* () {
          for (const p of response) {
            yield p;
          }
        })(),
      };
    },
  };
}

test('system text becomes the first user message; tool results are grouped', () => {
  const lm = fakeBindings({ cancelled: 0, disposed: 0 });
  const messages: ChatMessage[] = [
    { role: 'system', content: 'rules' },
    { role: 'user', content: 'task' },
    { role: 'assistant', content: 'calling', toolCalls: [{ id: 'a', name: 'read_file', input: { path: 'x' } }, { id: 'b', name: 'list_dir', input: {} }] },
    { role: 'tool', toolCallId: 'a', name: 'read_file', content: 'file text' },
    { role: 'tool', toolCallId: 'b', name: 'list_dir', content: 'x' },
    { role: 'assistant', content: 'done' },
  ];
  const out = toLmMessages(messages, lm) as Msg[];
  assert.deepEqual(out.map((m) => m.role), ['user', 'user', 'assistant', 'user', 'assistant']);
  assert.deepEqual(out[0].parts, [{ kind: 'text', value: 'rules' }]);
  assert.deepEqual(out[2].parts.map((p) => p.kind), ['text', 'call', 'call']);
  assert.deepEqual(out[3].parts.map((p) => (p as { callId: string }).callId), ['a', 'b']);
  assert.deepEqual((out[3].parts[0] as { content: unknown[] }).content, [{ kind: 'text', value: 'file text' }]);
});

test('an assistant turn with only tool calls has no empty text part', () => {
  const out = toLmMessages([{ role: 'assistant', content: '', toolCalls: [{ id: 'a', name: 't', input: {} }] }], fakeBindings({ cancelled: 0, disposed: 0 })) as Msg[];
  assert.deepEqual(out[0].parts.map((p) => p.kind), ['call']);
});

test('send streams text, collects tool calls, passes tools and cancellation', async () => {
  const log = { cancelled: 0, disposed: 0 };
  const seen: { messages?: unknown[]; options?: Record<string, unknown>; token?: unknown } = {};
  const model = fakeModel([
    { kind: 'text', value: 'Hel' },
    { kind: 'text', value: 'lo' },
    { kind: 'call', callId: 'c1', name: 'spawn_worker', input: { name: 'w' } },
  ], seen);
  const backend = new LmBackend(model, fakeBindings(log), 'because');
  assert.equal(backend.label, 'GPT Test (copilot)');
  const abort = new AbortController();
  const reply = await backend.send([{ role: 'user', content: 'hi' }], [{ name: 'spawn_worker', description: 'd', parameters: { type: 'object' } }], abort.signal);
  assert.equal(reply.text, 'Hello');
  assert.deepEqual(reply.toolCalls, [{ id: 'c1', name: 'spawn_worker', input: { name: 'w' } }]);
  assert.equal(seen.options?.justification, 'because');
  assert.equal(seen.options?.toolMode, 'auto-mode');
  assert.deepEqual(seen.options?.tools, [{ name: 'spawn_worker', description: 'd', inputSchema: { type: 'object' } }]);
  assert.equal(log.disposed, 1);
  abort.abort();
  assert.equal(log.cancelled, 1);
});

test('without tools no tool options are sent; errors still dispose', async () => {
  const log = { cancelled: 0, disposed: 0 };
  const seen: { options?: Record<string, unknown> } = {};
  await new LmBackend(fakeModel([{ kind: 'text', value: 'x' }], seen), fakeBindings(log), 'j').send([], [], new AbortController().signal);
  assert.equal(seen.options?.tools, undefined);
  const failing: LmChatModel = { ...fakeModel([], {}), sendRequest: async () => { throw new Error('no consent'); } };
  await assert.rejects(new LmBackend(failing, fakeBindings(log), 'j').send([], [], new AbortController().signal), /no consent/);
  assert.equal(log.disposed, 2);
});
