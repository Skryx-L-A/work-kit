// Model registry: providers, harnesses, models.
//
// Same file shape as the terminal workbench registry ({version, providers, harnesses, models}),
// so a registry can be copied between the two; unknown fields are ignored. Pure module without a
// vscode import. A broken or missing file yields an empty registry instead of throwing, and every
// entry is validated on its own, so one broken model never hides the others.
import { readFile } from 'node:fs/promises';

export type ProviderKind = 'cloud' | 'local' | 'subscription' | 'vscode';
/** How the extension talks to a provider directly (API workers and discovery). */
export type ProviderApi = 'openai' | 'ollama' | 'none';
export type Runner = 'terminal' | 'api' | 'vscode-lm';
export type Role = 'worker' | 'orchestrator';

export interface Provider {
  id: string;
  label: string;
  kind: ProviderKind;
  baseUrl?: string;
  api?: ProviderApi;
  apiKeyEnv?: string;
  /** Explicit override of the data-locality default (`kind === 'local'`). */
  dataStaysLocal?: boolean;
  builtin?: boolean;
}

export interface Harness {
  id: string;
  label: string;
  runner: Runner;
  command?: string;
  args?: string[];
  /** Arguments that pass the initial prompt; `{prompt}` is replaced. Absent: typed after start. */
  promptArgs?: string[];
  env?: Record<string, string>;
  effortArgs?: string[];
  effortMap?: Record<string, string>;
  autonomyArgs?: string[];
  notes?: string;
  builtin?: boolean;
}

export interface Model {
  id: string;
  label: string;
  harness: string;
  provider: string;
  modelRef: string;
  roles: Role[];
  efforts?: string[];
  defaultEffort?: string;
  contextWindow?: number;
  goodFor?: string;
  notFor?: string;
  enabled: boolean;
  dataStaysLocal?: boolean;
  source: 'builtin' | 'file' | 'vscode-lm' | 'discovered';
}

export interface Registry {
  version: number;
  providers: Provider[];
  harnesses: Harness[];
  models: Model[];
}

export const EMPTY_REGISTRY: Registry = { version: 1, providers: [], harnesses: [], models: [] };

export const ROLES: readonly Role[] = ['worker', 'orchestrator'];
const PROVIDER_KINDS: readonly ProviderKind[] = ['cloud', 'local', 'subscription', 'vscode'];
const PROVIDER_APIS: readonly ProviderApi[] = ['openai', 'ollama', 'none'];
const RUNNERS: readonly Runner[] = ['terminal', 'api', 'vscode-lm'];

// ---------------------------------------------------------------------------------------------
// Built-ins. Ported from the terminal workbench registry, without personal paths or accounts.

const B = { builtin: true } as const;

export const BUILTIN_PROVIDERS: readonly Provider[] = [
  { id: 'vscode-lm', label: 'VS Code language models (e.g. GitHub Copilot)', kind: 'vscode', api: 'none', ...B },
  { id: 'claude-subscription', label: 'Claude Code (login)', kind: 'subscription', api: 'none', ...B },
  { id: 'chatgpt', label: 'OpenAI Codex CLI (login)', kind: 'subscription', api: 'none', ...B },
  { id: 'github-copilot', label: 'GitHub Copilot CLI (login)', kind: 'subscription', api: 'none', ...B },
  { id: 'gemini-cli', label: 'Gemini CLI (login)', kind: 'subscription', api: 'none', ...B },
  { id: 'opencode', label: 'opencode (login or configured provider)', kind: 'subscription', api: 'none', ...B },
  { id: 'ollama', label: 'Ollama (local)', kind: 'local', baseUrl: 'http://127.0.0.1:11434', api: 'ollama', ...B },
  { id: 'llamacpp', label: 'llama.cpp server (local)', kind: 'local', baseUrl: 'http://127.0.0.1:8080/v1', api: 'openai', ...B },
  { id: 'mlx', label: 'MLX server (local)', kind: 'local', baseUrl: 'http://127.0.0.1:8080/v1', api: 'openai', ...B },
  { id: 'openai', label: 'OpenAI API', kind: 'cloud', baseUrl: 'https://api.openai.com/v1', api: 'openai', apiKeyEnv: 'OPENAI_API_KEY', ...B },
  { id: 'google', label: 'Google Gemini API', kind: 'cloud', baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai', api: 'openai', apiKeyEnv: 'GEMINI_API_KEY', ...B },
  { id: 'anthropic-api', label: 'Anthropic API', kind: 'cloud', baseUrl: 'https://api.anthropic.com/v1', api: 'openai', apiKeyEnv: 'ANTHROPIC_API_KEY', ...B },
  { id: 'openrouter', label: 'OpenRouter', kind: 'cloud', baseUrl: 'https://openrouter.ai/api/v1', api: 'openai', apiKeyEnv: 'OPENROUTER_API_KEY', ...B },
  { id: 'deepseek', label: 'DeepSeek', kind: 'cloud', baseUrl: 'https://api.deepseek.com/v1', api: 'openai', apiKeyEnv: 'DEEPSEEK_API_KEY', ...B },
  { id: 'groq', label: 'Groq', kind: 'cloud', baseUrl: 'https://api.groq.com/openai/v1', api: 'openai', apiKeyEnv: 'GROQ_API_KEY', ...B },
  { id: 'mistral', label: 'Mistral', kind: 'cloud', baseUrl: 'https://api.mistral.ai/v1', api: 'openai', apiKeyEnv: 'MISTRAL_API_KEY', ...B },
  { id: 'xai', label: 'xAI', kind: 'cloud', baseUrl: 'https://api.x.ai/v1', api: 'openai', apiKeyEnv: 'XAI_API_KEY', ...B },
];

const NO_BROWSER = { BROWSER: 'true' };

export const BUILTIN_HARNESSES: readonly Harness[] = [
  { id: 'vscode-lm', label: 'VS Code language model (in the extension)', runner: 'vscode-lm', ...B },
  { id: 'api', label: 'OpenAI-compatible API (in the extension)', runner: 'api', ...B },
  {
    id: 'claude', label: 'Claude Code', runner: 'terminal', command: 'claude', args: ['--model', '{model}'],
    promptArgs: ['{prompt}'], effortArgs: ['--effort', '{effort}'], autonomyArgs: ['--dangerously-skip-permissions'], ...B,
  },
  {
    id: 'codex', label: 'Codex CLI', runner: 'terminal', command: 'codex', args: ['--model', '{model}'],
    promptArgs: ['{prompt}'], effortArgs: ['-c', 'model_reasoning_effort={effort}'],
    autonomyArgs: ['--dangerously-bypass-approvals-and-sandbox'], ...B,
  },
  {
    id: 'gemini', label: 'Gemini CLI', runner: 'terminal', command: 'gemini', args: ['-m', '{model}'],
    promptArgs: ['-i', '{prompt}'], autonomyArgs: ['--yolo'], env: NO_BROWSER, ...B,
  },
  {
    id: 'copilot', label: 'GitHub Copilot CLI', runner: 'terminal', command: 'copilot', args: [],
    promptArgs: ['-i', '{prompt}'], autonomyArgs: ['--allow-all'],
    env: { COPILOT_MODEL: '{model}', COPILOT_AUTO_UPDATE: 'false', ...NO_BROWSER }, ...B,
  },
  {
    id: 'opencode', label: 'opencode', runner: 'terminal', command: 'opencode', args: ['--model', '{model}'],
    promptArgs: ['--prompt', '{prompt}'], ...B,
  },
  {
    id: 'aider', label: 'Aider', runner: 'terminal', command: 'aider',
    args: ['--model', '{model}', '--no-show-release-notes', '--no-browser'],
    promptArgs: ['--message', '{prompt}'], effortArgs: ['--reasoning-effort', '{effort}'], autonomyArgs: ['--yes-always'],
    env: { OLLAMA_API_BASE: '{baseUrl:ollama}', ...NO_BROWSER }, notes: '--message runs one request and exits.', ...B,
  },
  {
    id: 'qwen', label: 'Qwen Code', runner: 'terminal', command: 'qwen', args: ['-m', '{model}'],
    promptArgs: ['-i', '{prompt}'], autonomyArgs: ['--approval-mode', 'yolo'], env: NO_BROWSER, ...B,
  },
  {
    id: 'goose', label: 'Goose (Ollama)', runner: 'terminal', command: 'goose', args: ['session'],
    env: { GOOSE_PROVIDER: 'ollama', GOOSE_MODEL: '{model}', OLLAMA_HOST: '{baseUrl:ollama}', GOOSE_TELEMETRY_OFF: '1', ...NO_BROWSER }, ...B,
  },
  { id: 'crush', label: 'Crush', runner: 'terminal', command: 'crush', args: [], autonomyArgs: ['--yolo'], env: { CRUSH_DISABLE_METRICS: '1', ...NO_BROWSER }, ...B },
  { id: 'kimi', label: 'Kimi CLI', runner: 'terminal', command: 'kimi', args: ['-m', '{model}'], autonomyArgs: ['--yolo'], env: NO_BROWSER, ...B },
  {
    id: 'gptme', label: 'gptme', runner: 'terminal', command: 'gptme', args: ['--name', '{name}', '-m', '{model}'],
    promptArgs: ['{prompt}'], autonomyArgs: ['-y'], env: NO_BROWSER, ...B,
  },
  {
    id: 'pi', label: 'pi (Ollama)', runner: 'terminal', command: 'pi', args: ['--provider', 'ollama', '--model', '{model}'],
    effortArgs: ['--thinking', '{effort}'], env: { OLLAMA_HOST: '{baseUrl:ollama}' }, ...B,
  },
  {
    id: 'openhands', label: 'OpenHands CLI (Ollama)', runner: 'terminal', command: 'openhands', args: ['--override-with-envs'],
    autonomyArgs: ['--always-approve'],
    env: { LLM_MODEL: 'openai/{model}', LLM_BASE_URL: '{baseUrl:ollama}/v1', LLM_API_KEY: 'local', ...NO_BROWSER }, ...B,
  },
];

const HARNESS_DEFAULT_PROVIDER: Record<string, string> = {
  claude: 'claude-subscription',
  codex: 'chatgpt',
  gemini: 'gemini-cli',
  copilot: 'github-copilot',
  opencode: 'opencode',
  aider: 'openai',
  qwen: 'ollama',
  goose: 'ollama',
  crush: 'opencode',
  kimi: 'opencode',
  gptme: 'openai',
  pi: 'ollama',
  openhands: 'ollama',
};

function builtinModel(id: string, label: string, harness: string, modelRef: string, provider?: string): Model {
  return {
    id, label, harness, modelRef,
    provider: provider ?? HARNESS_DEFAULT_PROVIDER[harness] ?? 'opencode',
    roles: ['worker', 'orchestrator'],
    enabled: true,
    source: 'builtin',
  };
}

/** One "use the CLI's own configured model" entry per terminal harness, plus the Claude aliases. */
export const BUILTIN_MODELS: readonly Model[] = [
  builtinModel('claude-sonnet', 'Claude Sonnet (Claude Code)', 'claude', 'sonnet'),
  builtinModel('claude-opus', 'Claude Opus (Claude Code)', 'claude', 'opus'),
  builtinModel('claude-haiku', 'Claude Haiku (Claude Code)', 'claude', 'haiku'),
  ...BUILTIN_HARNESSES.filter((h) => h.runner === 'terminal').map((h) =>
    builtinModel(`${h.id}-default`, `${h.label} (its configured model)`, h.id, ''),
  ),
];

// ---------------------------------------------------------------------------------------------
// Validation

function asString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;
}

function asStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  return value.filter((v): v is string => typeof v === 'string');
}

function asStringRecord(value: unknown): Record<string, string> | undefined {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return undefined;
  }
  const out: Record<string, string> = {};
  for (const [key, v] of Object.entries(value as Record<string, unknown>)) {
    if (typeof v === 'string') {
      out[key] = v;
    }
  }
  return Object.keys(out).length > 0 ? out : undefined;
}

function asEnum<T extends string>(value: unknown, allowed: readonly T[]): T | undefined {
  return typeof value === 'string' && (allowed as readonly string[]).includes(value) ? (value as T) : undefined;
}

function asPositiveNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : undefined;
}

function isObject(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}

export function validateProvider(raw: unknown): Provider | undefined {
  if (!isObject(raw)) {
    return undefined;
  }
  const id = asString(raw.id);
  const label = asString(raw.label) ?? id;
  const kind = asEnum(raw.kind, PROVIDER_KINDS);
  if (!id || !label || !kind) {
    return undefined;
  }
  const baseUrl = asString(raw.baseUrl);
  // The terminal workbench registry has no `api` field; infer it from the base URL.
  const api = asEnum(raw.api, PROVIDER_APIS)
    ?? (!baseUrl ? 'none' : /:11434\/?$/.test(baseUrl) ? 'ollama' : 'openai');
  return {
    id,
    label,
    kind,
    baseUrl,
    api,
    apiKeyEnv: asString(raw.apiKeyEnv),
    dataStaysLocal: typeof raw.dataStaysLocal === 'boolean' ? raw.dataStaysLocal : undefined,
  };
}

export function validateHarness(raw: unknown): Harness | undefined {
  if (!isObject(raw)) {
    return undefined;
  }
  const id = asString(raw.id);
  const label = asString(raw.label) ?? id;
  const runner = asEnum(raw.runner, RUNNERS) ?? 'terminal';
  const command = asString(raw.command);
  if (!id || !label || (runner === 'terminal' && !command)) {
    return undefined;
  }
  // Terminal workbench spelling: effort {style, args, map}, autonomy {args}.
  const effort = isObject(raw.effort) ? raw.effort : undefined;
  const autonomy = isObject(raw.autonomy) ? raw.autonomy : undefined;
  const effortArgs = asStringArray(raw.effortArgs)
    ?? (effort && effort.style !== 'none' ? asStringArray(effort.args) : undefined);
  return {
    id,
    label,
    runner,
    command,
    args: asStringArray(raw.args) ?? [],
    promptArgs: asStringArray(raw.promptArgs),
    env: asStringRecord(raw.env),
    effortArgs: effortArgs && effortArgs.length > 0 ? effortArgs : undefined,
    effortMap: asStringRecord(raw.effortMap) ?? (effort ? asStringRecord(effort.map) : undefined),
    autonomyArgs: asStringArray(raw.autonomyArgs) ?? (autonomy ? asStringArray(autonomy.args) : undefined),
    notes: asString(raw.notes),
  };
}

export function validateModel(raw: unknown): Model | undefined {
  if (!isObject(raw)) {
    return undefined;
  }
  const id = asString(raw.id);
  const harness = asString(raw.harness);
  const provider = asString(raw.provider);
  if (!id || !harness || !provider) {
    return undefined;
  }
  const roles = (asStringArray(raw.roles) ?? []).filter((r): r is Role => (ROLES as readonly string[]).includes(r));
  return {
    id,
    label: asString(raw.label) ?? id,
    harness,
    provider,
    modelRef: typeof raw.modelRef === 'string' ? raw.modelRef.trim() : id,
    roles: roles.length > 0 ? roles : ['worker'],
    efforts: asStringArray(raw.efforts),
    defaultEffort: asString(raw.defaultEffort),
    contextWindow: asPositiveNumber(raw.contextWindow),
    goodFor: asString(raw.goodFor),
    notFor: asString(raw.notFor),
    enabled: raw.enabled !== false,
    dataStaysLocal: typeof raw.dataStaysLocal === 'boolean' ? raw.dataStaysLocal : undefined,
    source: 'file',
  };
}

function validateAll<T>(raw: unknown, validate: (entry: unknown) => T | undefined): T[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw.map(validate).filter((v): v is T => v !== undefined);
}

export function parseRegistry(raw: string | undefined): Registry {
  if (!raw) {
    return EMPTY_REGISTRY;
  }
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch {
    return EMPTY_REGISTRY;
  }
  if (!isObject(data)) {
    return EMPTY_REGISTRY;
  }
  return {
    version: typeof data.version === 'number' ? data.version : 1,
    providers: validateAll(data.providers, validateProvider),
    harnesses: validateAll(data.harnesses, validateHarness),
    models: validateAll(data.models, validateModel),
  };
}

export async function readRegistry(file: string): Promise<Registry> {
  try {
    return parseRegistry(await readFile(file, 'utf8'));
  } catch {
    return EMPTY_REGISTRY;
  }
}

// ---------------------------------------------------------------------------------------------
// Merging: file entries win over built-ins with the same id.

function mergeById<T extends { id: string }>(builtins: readonly T[], entries: readonly T[]): T[] {
  const byId = new Map<string, T>();
  for (const b of builtins) {
    byId.set(b.id, b);
  }
  for (const e of entries) {
    byId.set(e.id, e);
  }
  return [...byId.values()];
}

/** The registry the extension works with: built-ins, file entries, and run-time models. */
export function effectiveRegistry(file: Registry, extraModels: readonly Model[] = []): Registry {
  return {
    version: file.version,
    providers: mergeById(BUILTIN_PROVIDERS, file.providers),
    harnesses: mergeById(BUILTIN_HARNESSES, file.harnesses),
    models: mergeById([...BUILTIN_MODELS, ...extraModels], file.models),
  };
}

export function findProvider(registry: Registry, id: string): Provider | undefined {
  return registry.providers.find((p) => p.id === id);
}

export function findHarness(registry: Registry, id: string): Harness | undefined {
  return registry.harnesses.find((h) => h.id === id);
}

export function findModel(registry: Registry, id: string): Model | undefined {
  return registry.models.find((m) => m.id === id);
}

/** Enabled models for a role whose harness exists. */
export function modelsForRole(registry: Registry, role: Role): Model[] {
  return registry.models.filter((m) => m.enabled && m.roles.includes(role) && findHarness(registry, m.harness));
}

export function runnerOf(registry: Registry, model: Model): Runner | undefined {
  return findHarness(registry, model.harness)?.runner;
}

/** Data locality: the model entry wins, then the provider override, then `kind === 'local'`. */
export function dataStaysLocal(model: Model, provider: Provider | undefined): boolean {
  if (model.dataStaysLocal !== undefined) {
    return model.dataStaysLocal;
  }
  if (!provider) {
    return false;
  }
  return provider.dataStaysLocal ?? provider.kind === 'local';
}

// ---------------------------------------------------------------------------------------------
// Placeholders

export const FIXED_PLACEHOLDERS = ['model', 'effort', 'workdir', 'name', 'prompt', 'runDir', 'taskFile', 'resultFile'] as const;
export type PlaceholderValues = Partial<Record<(typeof FIXED_PLACEHOLDERS)[number], string>>;

const PLACEHOLDER_RE = /\{([^}]*)\}/g;

export function isKnownPlaceholder(token: string): boolean {
  return (FIXED_PLACEHOLDERS as readonly string[]).includes(token) || /^baseUrl:[A-Za-z0-9_-]+$/.test(token);
}

export function unknownPlaceholders(text: string): string[] {
  return [...text.matchAll(PLACEHOLDER_RE)].map((m) => m[1]).filter((t) => !isKnownPlaceholder(t));
}

/** Replaces known placeholders; unknown ones stay as written so the mistake is visible. */
export function fillPlaceholders(text: string, values: PlaceholderValues, registry?: Registry): string {
  return text.replace(PLACEHOLDER_RE, (whole, token: string) => {
    if (token.startsWith('baseUrl:')) {
      const provider = registry ? findProvider(registry, token.slice('baseUrl:'.length)) : undefined;
      return provider?.baseUrl ?? whole;
    }
    if ((FIXED_PLACEHOLDERS as readonly string[]).includes(token)) {
      return values[token as keyof PlaceholderValues] ?? '';
    }
    return whole;
  });
}

function extractTokens(text: string): string[] {
  return [...text.matchAll(PLACEHOLDER_RE)].map((m) => m[1]).filter(isKnownPlaceholder);
}

/** True when `text` has placeholders and every fixed one resolves to an empty value. */
export function allPlaceholdersEmpty(text: string, values: PlaceholderValues): boolean {
  const tokens = extractTokens(text);
  return tokens.length > 0 && tokens.every((t) => !t.startsWith('baseUrl:') && !values[t as keyof PlaceholderValues]);
}

/**
 * Fills an argument template. An argument whose placeholders all resolve to an empty value is
 * dropped together with a preceding option flag (`--model {model}` with no model disappears),
 * so "use the CLI's configured model" needs no separate template.
 */
export function fillArgs(template: readonly string[], values: PlaceholderValues, registry?: Registry): string[] {
  const out: string[] = [];
  template.forEach((arg, i) => {
    if (allPlaceholdersEmpty(arg, values)) {
      const prev = template[i - 1];
      if (prev !== undefined && prev.startsWith('-') && extractTokens(prev).length === 0 && out[out.length - 1] === prev) {
        out.pop();
      }
      return;
    }
    out.push(fillPlaceholders(arg, values, registry));
  });
  return out;
}
