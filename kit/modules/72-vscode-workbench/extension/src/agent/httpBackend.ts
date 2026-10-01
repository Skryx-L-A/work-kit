// OpenAI-compatible /chat/completions backend (Ollama, llama.cpp, MLX, OpenAI, Gemini, OpenRouter,
// DeepSeek, Groq, Mistral, xAI, Anthropic's compatibility endpoint). Pure module.
import { parseArguments, type BackendReply, type ChatBackend, type ChatMessage, type ToolCall, type ToolSpec } from './loop.ts';

export interface HttpBackendOptions {
  label: string;
  /** Full chat completions URL, see chatCompletionsUrl(). */
  url: string;
  model: string;
  apiKey?: string;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
}

/** Ollama's native base URL has no /v1; its OpenAI-compatible API lives under /v1. */
export function chatCompletionsUrl(baseUrl: string, api: 'openai' | 'ollama'): string {
  const base = baseUrl.replace(/\/+$/, '');
  if (api === 'ollama' && !/\/v1$/.test(base)) {
    return `${base}/v1/chat/completions`;
  }
  return `${base}/chat/completions`;
}

export function toOpenAiMessages(messages: readonly ChatMessage[]): Record<string, unknown>[] {
  return messages.map((m) => {
    switch (m.role) {
      case 'assistant':
        return {
          role: 'assistant',
          content: m.content || null,
          ...(m.toolCalls && m.toolCalls.length > 0
            ? {
                tool_calls: m.toolCalls.map((c) => ({
                  id: c.id,
                  type: 'function',
                  function: { name: c.name, arguments: JSON.stringify(c.input) },
                })),
              }
            : {}),
        };
      case 'tool':
        return { role: 'tool', tool_call_id: m.toolCallId, content: m.content };
      default:
        return { role: m.role, content: m.content };
    }
  });
}

export function toOpenAiTools(tools: readonly ToolSpec[]): Record<string, unknown>[] {
  return tools.map((t) => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.parameters } }));
}

export function parseCompletion(body: unknown): BackendReply {
  const choice = (body as { choices?: { message?: Record<string, unknown> }[] })?.choices?.[0];
  const message = choice?.message ?? {};
  const text = typeof message.content === 'string' ? message.content : '';
  const rawCalls = Array.isArray(message.tool_calls) ? message.tool_calls : [];
  const toolCalls: ToolCall[] = rawCalls.map((c: Record<string, unknown>, i: number) => {
    const fn = (c.function ?? {}) as Record<string, unknown>;
    return {
      id: typeof c.id === 'string' && c.id ? c.id : `call_${i}`,
      name: String(fn.name ?? ''),
      input: parseArguments(fn.arguments),
    };
  });
  return { text, toolCalls };
}

export class HttpBackend implements ChatBackend {
  readonly label: string;
  private readonly fetchImpl: typeof fetch;

  private readonly options: HttpBackendOptions;

  constructor(options: HttpBackendOptions) {
    this.options = options;
    this.label = options.label;
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async send(messages: readonly ChatMessage[], tools: readonly ToolSpec[], signal: AbortSignal): Promise<BackendReply> {
    const timeout = AbortSignal.timeout(this.options.timeoutMs ?? 600_000);
    const headers: Record<string, string> = { 'content-type': 'application/json' };
    if (this.options.apiKey) {
      headers.authorization = `Bearer ${this.options.apiKey}`;
    }
    const response = await this.fetchImpl(this.options.url, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: this.options.model,
        messages: toOpenAiMessages(messages),
        ...(tools.length > 0 ? { tools: toOpenAiTools(tools), tool_choice: 'auto' } : {}),
        stream: false,
      }),
      signal: AbortSignal.any([signal, timeout]),
    });
    const text = await response.text();
    if (!response.ok) {
      // Never echo request headers; the body of an error response carries no key.
      throw new Error(`${this.label}: HTTP ${response.status} ${text.slice(0, 300)}`);
    }
    let body: unknown;
    try {
      body = JSON.parse(text);
    } catch {
      throw new Error(`${this.label}: response is not JSON`);
    }
    return parseCompletion(body);
  }
}
