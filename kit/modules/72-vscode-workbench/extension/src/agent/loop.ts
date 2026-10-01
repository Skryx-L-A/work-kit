// Backend-independent agent loop for API workers and the orchestrator. Pure module.

export interface ToolSpec {
  name: string;
  description: string;
  /** JSON schema of the input object. */
  parameters: Record<string, unknown>;
}

export interface ToolCall {
  id: string;
  name: string;
  input: Record<string, unknown>;
}

export type ChatMessage =
  | { role: 'system'; content: string }
  | { role: 'user'; content: string }
  | { role: 'assistant'; content: string; toolCalls?: ToolCall[] }
  | { role: 'tool'; toolCallId: string; name: string; content: string };

export interface BackendReply {
  text: string;
  toolCalls: ToolCall[];
}

export interface ChatBackend {
  readonly label: string;
  send(messages: readonly ChatMessage[], tools: readonly ToolSpec[], signal: AbortSignal): Promise<BackendReply>;
}

export interface ToolOutcome {
  content: string;
  /** Ends the loop after this tool result (e.g. `finish`). */
  stop?: boolean;
}

export interface ToolHandler {
  spec: ToolSpec;
  run(input: Record<string, unknown>, signal: AbortSignal): Promise<ToolOutcome>;
}

export type LoopEvent =
  | { type: 'text'; text: string }
  | { type: 'tool-call'; call: ToolCall }
  | { type: 'tool-result'; call: ToolCall; content: string };

export interface LoopOptions {
  maxSteps: number;
  signal: AbortSignal;
  onEvent?: (event: LoopEvent) => void | Promise<void>;
}

export type StopReason = 'final' | 'tool-stop' | 'max-steps' | 'aborted';

export interface LoopResult {
  messages: ChatMessage[];
  finalText: string;
  steps: number;
  stoppedBy: StopReason;
}

const MAX_TOOL_OUTPUT = 60_000;

function truncate(text: string): string {
  return text.length > MAX_TOOL_OUTPUT
    ? `${text.slice(0, MAX_TOOL_OUTPUT)}\n[truncated: ${text.length - MAX_TOOL_OUTPUT} more characters]`
    : text;
}

/**
 * Runs model turns until the model answers without tool calls, a tool asks to stop, the step
 * limit is reached, or the signal aborts. Tool errors go back to the model as tool results.
 */
export async function runAgentLoop(
  backend: ChatBackend,
  initial: readonly ChatMessage[],
  handlers: readonly ToolHandler[],
  options: LoopOptions,
): Promise<LoopResult> {
  const messages: ChatMessage[] = [...initial];
  const byName = new Map(handlers.map((h) => [h.spec.name, h]));
  const specs = handlers.map((h) => h.spec);
  let finalText = '';
  for (let step = 1; step <= options.maxSteps; step++) {
    if (options.signal.aborted) {
      return { messages, finalText, steps: step - 1, stoppedBy: 'aborted' };
    }
    const reply = await backend.send(messages, specs, options.signal);
    if (reply.text) {
      finalText = reply.text;
      await options.onEvent?.({ type: 'text', text: reply.text });
    }
    messages.push({ role: 'assistant', content: reply.text, toolCalls: reply.toolCalls.length > 0 ? reply.toolCalls : undefined });
    if (reply.toolCalls.length === 0) {
      return { messages, finalText, steps: step, stoppedBy: 'final' };
    }
    let stop = false;
    for (const call of reply.toolCalls) {
      await options.onEvent?.({ type: 'tool-call', call });
      const handler = byName.get(call.name);
      let content: string;
      if (!handler) {
        content = `Error: unknown tool "${call.name}". Available: ${[...byName.keys()].join(', ')}`;
      } else {
        try {
          const outcome = await handler.run(call.input ?? {}, options.signal);
          content = outcome.content;
          stop = stop || outcome.stop === true;
        } catch (error) {
          content = `Error: ${(error as Error).message}`;
        }
      }
      content = truncate(content);
      messages.push({ role: 'tool', toolCallId: call.id, name: call.name, content });
      await options.onEvent?.({ type: 'tool-result', call, content });
    }
    if (stop) {
      return { messages, finalText, steps: step, stoppedBy: 'tool-stop' };
    }
  }
  return { messages, finalText, steps: options.maxSteps, stoppedBy: 'max-steps' };
}

/** Parses tool-call arguments that arrive as a JSON string; broken JSON becomes an empty object. */
export function parseArguments(raw: unknown): Record<string, unknown> {
  if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
    return raw as Record<string, unknown>;
  }
  if (typeof raw !== 'string' || raw.trim() === '') {
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}
