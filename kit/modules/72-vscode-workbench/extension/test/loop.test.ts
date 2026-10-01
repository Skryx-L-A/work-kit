import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseArguments, runAgentLoop, type BackendReply, type ChatBackend, type ChatMessage, type ToolHandler } from '../src/agent/loop.ts';

class ScriptedBackend implements ChatBackend {
  readonly label = 'scripted';
  readonly seen: ChatMessage[][] = [];
  private readonly replies: BackendReply[];
  constructor(replies: BackendReply[]) {
    this.replies = replies;
  }
  async send(messages: readonly ChatMessage[]): Promise<BackendReply> {
    this.seen.push([...messages]);
    return this.replies.shift() ?? { text: 'out of script', toolCalls: [] };
  }
}

const echo: ToolHandler = {
  spec: { name: 'echo', description: 'echo', parameters: { type: 'object' } },
  async run(input) {
    return { content: `echo:${String(input.v)}` };
  },
};
const boom: ToolHandler = {
  spec: { name: 'boom', description: 'fails', parameters: { type: 'object' } },
  async run() {
    throw new Error('kaputt');
  },
};
const finish: ToolHandler = {
  spec: { name: 'finish', description: 'stop', parameters: { type: 'object' } },
  async run() {
    return { content: 'bye', stop: true };
  },
};

const start: ChatMessage[] = [{ role: 'system', content: 's' }, { role: 'user', content: 'u' }];
const opts = () => ({ maxSteps: 10, signal: new AbortController().signal });

test('tool calls run and their results go back to the model', async () => {
  const backend = new ScriptedBackend([
    { text: 'thinking', toolCalls: [{ id: 'c1', name: 'echo', input: { v: 1 } }, { id: 'c2', name: 'nope', input: {} }, { id: 'c3', name: 'boom', input: {} }] },
    { text: 'final answer', toolCalls: [] },
  ]);
  const events: string[] = [];
  const r = await runAgentLoop(backend, start, [echo, boom], { ...opts(), onEvent: (e) => { events.push(e.type); } });
  assert.equal(r.stoppedBy, 'final');
  assert.equal(r.steps, 2);
  assert.equal(r.finalText, 'final answer');
  const second = backend.seen[1];
  const tools = second.filter((m) => m.role === 'tool') as Extract<ChatMessage, { role: 'tool' }>[];
  assert.deepEqual(tools.map((t) => t.toolCallId), ['c1', 'c2', 'c3']);
  assert.equal(tools[0].content, 'echo:1');
  assert.match(tools[1].content, /unknown tool "nope"/);
  assert.equal(tools[2].content, 'Error: kaputt');
  assert.deepEqual(events, ['text', 'tool-call', 'tool-result', 'tool-call', 'tool-result', 'tool-call', 'tool-result', 'text']);
  assert.equal(start.length, 2, 'input messages are not mutated');
});

test('a stopping tool ends the loop', async () => {
  const backend = new ScriptedBackend([{ text: '', toolCalls: [{ id: 'f', name: 'finish', input: {} }] }]);
  const r = await runAgentLoop(backend, start, [finish], opts());
  assert.equal(r.stoppedBy, 'tool-stop');
  assert.equal(r.messages.at(-1)?.role, 'tool');
});

test('step limit and abort', async () => {
  const loopForever = new ScriptedBackend(Array.from({ length: 20 }, (_, i) => ({ text: '', toolCalls: [{ id: `c${i}`, name: 'echo', input: {} }] })));
  const r = await runAgentLoop(loopForever, start, [echo], { maxSteps: 3, signal: new AbortController().signal });
  assert.equal(r.stoppedBy, 'max-steps');
  assert.equal(loopForever.seen.length, 3);

  const abort = new AbortController();
  abort.abort();
  const r2 = await runAgentLoop(new ScriptedBackend([]), start, [], { maxSteps: 3, signal: abort.signal });
  assert.equal(r2.stoppedBy, 'aborted');
  assert.equal(r2.steps, 0);
});

test('huge tool output is truncated', async () => {
  const big: ToolHandler = { spec: { name: 'big', description: '', parameters: {} }, run: async () => ({ content: 'x'.repeat(70_000) }) };
  const backend = new ScriptedBackend([{ text: '', toolCalls: [{ id: 'b', name: 'big', input: {} }] }, { text: 'ok', toolCalls: [] }]);
  const r = await runAgentLoop(backend, start, [big], opts());
  const tool = r.messages.find((m) => m.role === 'tool') as Extract<ChatMessage, { role: 'tool' }>;
  assert.ok(tool.content.length < 61_000);
  assert.match(tool.content, /truncated: 10000 more characters/);
});

test('parseArguments accepts objects and JSON strings only', () => {
  assert.deepEqual(parseArguments('{"a":1}'), { a: 1 });
  assert.deepEqual(parseArguments({ b: 2 }), { b: 2 });
  assert.deepEqual(parseArguments('[1]'), {});
  assert.deepEqual(parseArguments('{broken'), {});
  assert.deepEqual(parseArguments(undefined), {});
});
