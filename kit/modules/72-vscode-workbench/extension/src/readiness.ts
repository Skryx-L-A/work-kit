// Can a model start right now? Checked in the order a spawn would hit the problem. Pure module.
import { dataStaysLocal, findHarness, findProvider, type Model, type Registry } from './registry.ts';

export type Readiness = 'ready' | 'cli-missing' | 'no-key' | 'unavailable' | 'disabled';

export interface ReadinessFacts {
  /** Terminal harness command found on PATH (or as an absolute path). */
  commandFound: (command: string) => boolean;
  /** An API key exists for the provider (environment variable or SecretStorage). */
  hasKey: (providerId: string) => boolean;
  /** Ids of the VS Code language models that are available now. */
  lmIds: ReadonlySet<string>;
}

export const READINESS_LABEL: Record<Readiness, string> = {
  ready: 'ready',
  'cli-missing': 'CLI not installed',
  'no-key': 'no API key',
  unavailable: 'not available',
  disabled: 'disabled',
};

export function modelReadiness(registry: Registry, model: Model, facts: ReadinessFacts): Readiness {
  if (!model.enabled) {
    return 'disabled';
  }
  const harness = findHarness(registry, model.harness);
  if (!harness) {
    return 'unavailable';
  }
  if (harness.runner === 'terminal') {
    return harness.command && facts.commandFound(harness.command) ? 'ready' : 'cli-missing';
  }
  if (harness.runner === 'vscode-lm') {
    return facts.lmIds.has(model.id) ? 'ready' : 'unavailable';
  }
  const provider = findProvider(registry, model.provider);
  if (!provider?.baseUrl || provider.api === 'none') {
    return 'unavailable';
  }
  if (provider.kind === 'cloud' && !facts.hasKey(provider.id)) {
    return 'no-key';
  }
  return 'ready';
}

export interface ModelChoice {
  model: Model;
  runner: string;
  local: boolean;
  readiness: Readiness;
}

/** Models with their runner, data locality and readiness; ready ones first, order kept otherwise. */
export function modelChoices(registry: Registry, models: readonly Model[], facts: ReadinessFacts): ModelChoice[] {
  const choices = models.map((model) => ({
    model,
    runner: findHarness(registry, model.harness)?.runner ?? '',
    local: dataStaysLocal(model, findProvider(registry, model.provider)),
    readiness: modelReadiness(registry, model, facts),
  }));
  return [...choices.filter((c) => c.readiness === 'ready'), ...choices.filter((c) => c.readiness !== 'ready')];
}
