// VS Code Language Model API backend (vscode.lm, e.g. GitHub Copilot models).
//
// The vscode namespace is injected (LmBindings) so the translation between the loop's messages
// and the LM API's parts is unit-testable without a VS Code host.
import type { BackendReply, ChatBackend, ChatMessage, ToolCall, ToolSpec } from './loop.ts';

export interface LmCancellation {
  token: unknown;
  dispose(): void;
}

export interface LmChatModel {
  id: string;
  name: string;
  vendor: string;
  family: string;
  maxInputTokens?: number;
  sendRequest(messages: unknown[], options: Record<string, unknown>, token?: unknown): Thenable<{ stream: AsyncIterable<unknown> }>;
}

export interface LmBindings {
  user(parts: unknown[]): unknown;
  assistant(parts: unknown[]): unknown;
  textPart(value: string): unknown;
  toolCallPart(callId: string, name: string, input: object): unknown;
  toolResultPart(callId: string, content: unknown[]): unknown;
  /** Returns the text of a response part, or undefined. */
  textOf(part: unknown): string | undefined;
  /** Returns the tool call of a response part, or undefined. */
  toolCallOf(part: unknown): ToolCall | undefined;
  cancellation(signal: AbortSignal): LmCancellation;
  toolModeAuto: unknown;
}

/**
 * The LM API has no system role: the system text becomes the first user message. Consecutive
 * tool results are grouped into one user message, as the API expects after an assistant turn.
 */
export function toLmMessages(messages: readonly ChatMessage[], lm: LmBindings): unknown[] {
  const out: unknown[] = [];
  let pendingResults: unknown[] = [];
  const flush = () => {
    if (pendingResults.length > 0) {
      out.push(lm.user(pendingResults));
      pendingResults = [];
    }
  };
  for (const m of messages) {
    if (m.role === 'tool') {
      pendingResults.push(lm.toolResultPart(m.toolCallId, [lm.textPart(m.content)]));
      continue;
    }
    flush();
    if (m.role === 'assistant') {
      const parts: unknown[] = [];
      if (m.content) {
        parts.push(lm.textPart(m.content));
      }
      for (const c of m.toolCalls ?? []) {
        parts.push(lm.toolCallPart(c.id, c.name, c.input));
      }
      out.push(lm.assistant(parts));
    } else {
      out.push(lm.user([lm.textPart(m.content)]));
    }
  }
  flush();
  return out;
}

export class LmBackend implements ChatBackend {
  readonly label: string;

  private readonly model: LmChatModel;
  private readonly lm: LmBindings;
  private readonly justification: string;

  constructor(model: LmChatModel, lm: LmBindings, justification: string) {
    this.model = model;
    this.lm = lm;
    this.justification = justification;
    this.label = `${model.name} (${model.vendor})`;
  }

  async send(messages: readonly ChatMessage[], tools: readonly ToolSpec[], signal: AbortSignal): Promise<BackendReply> {
    const cancellation = this.lm.cancellation(signal);
    try {
      const options: Record<string, unknown> = { justification: this.justification };
      if (tools.length > 0) {
        options.tools = tools.map((t) => ({ name: t.name, description: t.description, inputSchema: t.parameters }));
        options.toolMode = this.lm.toolModeAuto;
      }
      const response = await this.model.sendRequest(toLmMessages(messages, this.lm), options, cancellation.token);
      let text = '';
      const toolCalls: ToolCall[] = [];
      for await (const part of response.stream) {
        const t = this.lm.textOf(part);
        if (t !== undefined) {
          text += t;
          continue;
        }
        const call = this.lm.toolCallOf(part);
        if (call) {
          toolCalls.push(call);
        }
      }
      return { text, toolCalls };
    } finally {
      cancellation.dispose();
    }
  }
}
