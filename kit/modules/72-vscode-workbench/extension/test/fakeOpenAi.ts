// Minimal OpenAI-compatible server on 127.0.0.1 with an ephemeral port, for tests.
import { createServer, type IncomingMessage, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

export interface SeenRequest {
  method: string;
  url: string;
  headers: IncomingMessage['headers'];
  body: Record<string, unknown>;
}

export interface FakeServer {
  url: string;
  seen: SeenRequest[];
  close(): Promise<void>;
}

/** `reply` returns [status, body] for each chat request; GET /v1/models and /api/tags list `models`. */
export async function startFakeOpenAi(
  reply: (body: Record<string, unknown>, index: number) => [number, unknown],
  models: string[] = [],
): Promise<FakeServer> {
  const seen: SeenRequest[] = [];
  const server: Server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (c: Buffer) => chunks.push(c));
    req.on('end', () => {
      const text = Buffer.concat(chunks).toString('utf8');
      const body = text ? JSON.parse(text) : {};
      seen.push({ method: req.method ?? '', url: req.url ?? '', headers: req.headers, body });
      let status = 404;
      let out: unknown = { error: 'not found' };
      if (req.method === 'GET' && req.url?.endsWith('/models')) {
        [status, out] = [200, { data: models.map((id) => ({ id })) }];
      } else if (req.method === 'GET' && req.url === '/api/tags') {
        [status, out] = [200, { models: models.map((name) => ({ name })) }];
      } else if (req.method === 'POST' && req.url?.endsWith('/chat/completions')) {
        [status, out] = reply(body, seen.filter((s) => s.method === 'POST').length - 1);
      }
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(typeof out === 'string' ? out : JSON.stringify(out));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = (server.address() as AddressInfo).port;
  return {
    url: `http://127.0.0.1:${port}`,
    seen,
    close: () => new Promise((resolve) => server.close(() => resolve())),
  };
}

export function completion(content: string | null, toolCalls?: { id: string; name: string; args: unknown }[]) {
  return {
    choices: [{
      message: {
        role: 'assistant',
        content,
        ...(toolCalls ? { tool_calls: toolCalls.map((c) => ({ id: c.id, type: 'function', function: { name: c.name, arguments: JSON.stringify(c.args) } })) } : {}),
      },
    }],
  };
}
