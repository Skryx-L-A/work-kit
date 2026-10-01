// On-demand discovery of models served by LOCAL providers. Pure module.
import type { Model, Provider } from './registry.ts';

export function modelsUrl(provider: Provider): string | undefined {
  if (!provider.baseUrl) {
    return undefined;
  }
  const base = provider.baseUrl.replace(/\/+$/, '');
  if (provider.api === 'ollama') {
    return `${base.replace(/\/v1$/, '')}/api/tags`;
  }
  return `${base}/models`;
}

export function parseModelList(provider: Provider, body: unknown): string[] {
  const b = body as { models?: { name?: string; model?: string }[]; data?: { id?: string }[] };
  if (provider.api === 'ollama' && Array.isArray(b?.models)) {
    return b.models.map((m) => m.name ?? m.model ?? '').filter(Boolean);
  }
  if (Array.isArray(b?.data)) {
    return b.data.map((m) => m.id ?? '').filter(Boolean);
  }
  return [];
}

export function discoveredModel(provider: Provider, ref: string): Model {
  return {
    id: `${provider.id}:${ref}`,
    label: `${ref} (${provider.label})`,
    harness: 'api',
    provider: provider.id,
    modelRef: ref,
    roles: ['worker', 'orchestrator'],
    enabled: true,
    source: 'discovered',
  };
}

export async function discoverProvider(provider: Provider, fetchImpl: typeof fetch = fetch): Promise<Model[]> {
  if (provider.kind !== 'local') {
    throw new Error(`${provider.label} is not local; add its models to the registry by hand`);
  }
  const url = modelsUrl(provider);
  if (!url) {
    return [];
  }
  const response = await fetchImpl(url, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) {
    throw new Error(`${provider.label}: HTTP ${response.status}`);
  }
  return parseModelList(provider, await response.json()).map((ref) => discoveredModel(provider, ref));
}
