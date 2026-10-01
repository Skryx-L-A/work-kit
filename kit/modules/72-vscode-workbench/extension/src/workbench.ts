// The workbench controller: model resolution, worker runs, requests, orchestrator entry points.
import { execFile } from 'node:child_process';
import { chmod, mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import * as vscode from 'vscode';
import { chatCompletionsUrl, HttpBackend } from './agent/httpBackend.ts';
import { LmBackend, type LmBindings, type LmChatModel } from './agent/lmBackend.ts';
import { runAgentLoop, type ChatBackend, type ChatMessage, type LoopEvent } from './agent/loop.ts';
import { orchestratorTools, readIfExists, workerTools, type SpawnInput, type WorkbenchApi } from './agent/tools.ts';
import { Brain, findExecutable } from './brain.ts';
import { orchestratorPrompt, terminalLaunch, workerPrompt } from './commandLine.ts';
import { discoverProvider } from './discovery.ts';
import { newId, previewText, relativeTime, slug } from './format.ts';
import { orchestratorSystemPrompt, workerSystemPrompt, type PromptContext } from './prompts.ts';
import {
  dataStaysLocal,
  effectiveRegistry,
  findHarness,
  findModel,
  findProvider,
  modelsForRole,
  readRegistry,
  type Model,
  type Registry,
  type Role,
} from './registry.ts';
import { modelChoices, type ModelChoice, type ReadinessFacts } from './readiness.ts';
import { acceptRequest, readRequest, rejectRequest, requestState } from './requests.ts';
import { taskBody } from './results.ts';
import {
  appendLog,
  archiveRuns,
  createRun,
  expandHome,
  isOrphaned,
  lastActivity,
  listRuns,
  markRun,
  readMeta,
  readResult,
  renderTask,
  requestsDir,
  runFiles,
  settleFromResult,
  type RunMeta,
} from './runs.ts';
import { listSkills } from './skills.ts';
import { statusItems, type StatusItem } from './status.ts';
import { listTemplates, templateSpawn, type TaskTemplate } from './templates.ts';
import type { RunCard } from './viewsHtml.ts';

export const VSCODE_LM_PREFIX = 'vscode-lm:';
const SECRET_PREFIX = 'kitWorkbench.apiKey.';

export function lmBindings(): LmBindings {
  return {
    user: (parts) => vscode.LanguageModelChatMessage.User(parts as vscode.LanguageModelTextPart[]),
    assistant: (parts) => vscode.LanguageModelChatMessage.Assistant(parts as vscode.LanguageModelTextPart[]),
    textPart: (value) => new vscode.LanguageModelTextPart(value),
    toolCallPart: (callId, name, input) => new vscode.LanguageModelToolCallPart(callId, name, input),
    toolResultPart: (callId, content) => new vscode.LanguageModelToolResultPart(callId, content as vscode.LanguageModelTextPart[]),
    textOf: (part) => (part instanceof vscode.LanguageModelTextPart ? part.value : undefined),
    toolCallOf: (part) =>
      part instanceof vscode.LanguageModelToolCallPart
        ? { id: part.callId, name: part.name, input: (part.input ?? {}) as Record<string, unknown> }
        : undefined,
    cancellation: (signal) => {
      const source = new vscode.CancellationTokenSource();
      const onAbort = () => source.cancel();
      if (signal.aborted) {
        source.cancel();
      }
      signal.addEventListener('abort', onAbort);
      return {
        token: source.token,
        dispose: () => {
          signal.removeEventListener('abort', onAbort);
          source.dispose();
        },
      };
    },
    toolModeAuto: vscode.LanguageModelChatToolMode.Auto,
  };
}

export function lmModelId(model: { vendor: string; id: string }): string {
  return `${VSCODE_LM_PREFIX}${model.vendor}/${model.id}`;
}

function lmModelEntry(model: vscode.LanguageModelChat): Model {
  return {
    id: lmModelId(model),
    label: `${model.name} (${model.vendor}, VS Code)`,
    harness: 'vscode-lm',
    provider: 'vscode-lm',
    modelRef: model.id,
    roles: ['worker', 'orchestrator'],
    contextWindow: model.maxInputTokens,
    enabled: true,
    source: 'vscode-lm',
  };
}

interface ActiveRun {
  terminal?: vscode.Terminal;
  abort?: AbortController;
}

export class Workbench implements WorkbenchApi, vscode.Disposable {
  private readonly changed = new vscode.EventEmitter<void>();
  readonly onDidChange = this.changed.event;
  private readonly active = new Map<string, ActiveRun>();
  private readonly confirmedProviders = new Set<string>();
  private discovered: Model[] = [];
  private statusCache: { at: number; items: StatusItem[] } | undefined;
  /** Terminal orchestrator started by this window, target of "Send to Orchestrator". */
  orchestratorTerminal: vscode.Terminal | undefined;
  private timer: NodeJS.Timeout | undefined;
  private polling = false;
  private readonly disposables: vscode.Disposable[] = [];
  readonly output: vscode.OutputChannel;

  private readonly context: vscode.ExtensionContext;

  constructor(context: vscode.ExtensionContext) {
    this.context = context;
    this.output = vscode.window.createOutputChannel('Kit Workbench');
    this.disposables.push(
      this.output,
      this.changed,
      vscode.window.onDidCloseTerminal((t) => void this.onTerminalClosed(t)),
    );
  }

  // --- configuration ------------------------------------------------------------------------

  private config(): vscode.WorkspaceConfiguration {
    return vscode.workspace.getConfiguration('kitWorkbench');
  }

  get stateDir(): string {
    return expandHome(process.env.KIT_WB_STATE || this.config().get<string>('stateDir', '~/.local/share/work-kit/workbench'));
  }

  get registryPath(): string {
    return expandHome(this.config().get<string>('registryPath', '~/.config/work-kit/workbench/models.json'));
  }

  get skillsDir(): string {
    return expandHome(this.config().get<string>('skillsDir', '~/.agents/skills'));
  }

  get brain(): Brain {
    return new Brain(this.config().get<string>('brainCommand', 'brain'));
  }

  get templatesDir(): string {
    return expandHome(this.config().get<string>('templatesDir', '~/.config/work-kit/workbench/templates'));
  }

  get builtinTemplatesDir(): string {
    return join(this.context.extensionPath, 'resources', 'templates');
  }

  get quietMinutes(): number {
    return this.config().get<number>('quietMinutes', 15);
  }

  get binDir(): string {
    return join(this.context.extensionPath, 'resources', 'bin');
  }

  workspaceDir(): string {
    return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? expandHome('~');
  }

  // --- lifecycle ----------------------------------------------------------------------------

  async start(): Promise<void> {
    await mkdir(requestsDir(this.stateDir), { recursive: true });
    await mkdir(join(this.stateDir, 'runs'), { recursive: true });
    // vsix packaging does not keep the executable bit.
    await chmod(join(this.binDir, 'kit-wb'), 0o755).catch(() => undefined);
    // Runs whose VS Code window is gone cannot be resumed; other windows' runs stay.
    for (const run of await listRuns(this.stateDir)) {
      if (isOrphaned(run) && !(await settleFromResult(this.stateDir, run.id))) {
        await markRun(this.stateDir, run.id, 'failed', 'VS Code was closed while the run was active');
      }
    }
    this.timer = setInterval(() => void this.poll(), 2000);
    this.changed.fire();
  }

  dispose(): void {
    if (this.timer) {
      clearInterval(this.timer);
    }
    for (const run of this.active.values()) {
      run.abort?.abort();
    }
    for (const d of this.disposables) {
      d.dispose();
    }
  }

  /** Settles running runs from their result files and turns kit-wb requests into runs. */
  async poll(): Promise<void> {
    if (this.polling) {
      return;
    }
    this.polling = true;
    try {
      let changed = false;
      for (const id of this.active.keys()) {
        if ((await settleFromResult(this.stateDir, id)) && !this.active.get(id)?.abort) {
          this.active.delete(id);
          changed = true;
        }
      }
      changed = (await this.processRequests()) || changed;
      if (changed) {
        this.changed.fire();
      }
    } finally {
      this.polling = false;
    }
  }

  private async processRequests(): Promise<boolean> {
    const dir = requestsDir(this.stateDir);
    let ids: string[];
    try {
      ids = await readdir(dir);
    } catch {
      return false;
    }
    let any = false;
    for (const id of ids.sort()) {
      const reqDir = join(dir, id);
      if ((await requestState(reqDir)) !== 'pending') {
        continue;
      }
      try {
        // Several VS Code windows poll the same directory; mkdir is the atomic claim.
        await mkdir(join(reqDir, 'claim'));
      } catch {
        continue;
      }
      any = true;
      const request = await readRequest(reqDir);
      if (typeof request === 'string') {
        await rejectRequest(reqDir, request);
        continue;
      }
      try {
        const r = await this.spawn(request, 'request', request.cwd);
        await acceptRequest(reqDir, r.runId);
      } catch (error) {
        await rejectRequest(reqDir, (error as Error).message);
      }
    }
    return any;
  }

  // --- models -------------------------------------------------------------------------------

  async lmModels(): Promise<vscode.LanguageModelChat[]> {
    try {
      return await vscode.lm.selectChatModels({});
    } catch {
      return [];
    }
  }

  async registry(): Promise<Registry> {
    const file = await readRegistry(this.registryPath);
    const lm = (await this.lmModels()).map(lmModelEntry);
    return effectiveRegistry(file, [...lm, ...this.discovered]);
  }

  async discover(): Promise<string[]> {
    const registry = await this.registry();
    const lines: string[] = [];
    const found: Model[] = [];
    for (const provider of registry.providers.filter((p) => p.kind === 'local' && p.baseUrl)) {
      try {
        const models = await discoverProvider(provider);
        found.push(...models);
        lines.push(`${provider.label}: ${models.length} models`);
      } catch (error) {
        lines.push(`${provider.label}: not reachable (${(error as Error).message})`);
      }
    }
    this.discovered = found;
    this.changed.fire();
    return lines;
  }

  async modelsFor(role: Role): Promise<Model[]> {
    return modelsForRole(await this.registry(), role);
  }

  async describeModels(): Promise<string> {
    const registry = await this.registry();
    const models = modelsForRole(registry, 'worker');
    const lines = models.map((m) => {
      const provider = findProvider(registry, m.provider);
      const where = dataStaysLocal(m, provider) ? 'local' : 'leaves this machine';
      const runner = findHarness(registry, m.harness)?.runner;
      const extra = [m.goodFor ? `good for: ${m.goodFor}` : '', m.notFor ? `not for: ${m.notFor}` : ''].filter(Boolean).join('; ');
      return `- ${m.id}: ${m.label} [${runner}, ${where}]${extra ? ` ${extra}` : ''}`;
    });
    const def = this.config().get<string>('defaultWorkerModel', '');
    return `Worker models (default: ${def || 'the chat model, else the first VS Code model'}):\n${lines.join('\n')}`;
  }

  private async resolveModel(requested: string | undefined, fallback?: Model): Promise<{ registry: Registry; model: Model }> {
    const registry = await this.registry();
    const id = requested || this.config().get<string>('defaultWorkerModel', '') || '';
    if (id) {
      const model = findModel(registry, id)
        ?? registry.models.find((m) => m.enabled && (m.modelRef === id || m.label === id));
      if (!model) {
        throw new Error(`Unknown model "${id}". Use list_workers (or "Kit Workbench: List Models") for valid ids.`);
      }
      return { registry, model };
    }
    if (fallback) {
      return { registry, model: fallback };
    }
    const lm = registry.models.find((m) => m.source === 'vscode-lm');
    if (lm) {
      return { registry, model: lm };
    }
    throw new Error('No model given and no default: set kitWorkbench.defaultWorkerModel or name a model.');
  }

  async confirmCloud(registry: Registry, model: Model): Promise<void> {
    const provider = findProvider(registry, model.provider);
    if (dataStaysLocal(model, provider) || !this.config().get<boolean>('confirmCloudModels', true)) {
      return;
    }
    const key = provider?.id ?? model.provider;
    if (this.confirmedProviders.has(key)) {
      return;
    }
    const dataClasses = await this.dataClassesFile();
    const hasClasses = dataClasses !== undefined;
    const choice = await vscode.window.showWarningMessage(
      `Kit Workbench is about to send workspace content to ${provider?.label ?? model.provider}, which is not local. ` +
        'Send only data whose class allows this destination.',
      { modal: true },
      'Send',
      ...(hasClasses ? ['Open data classes'] : []),
    );
    if (choice === 'Open data classes' && dataClasses) {
      await vscode.window.showTextDocument(vscode.Uri.file(dataClasses));
    }
    if (choice !== 'Send') {
      throw new Error(`Not sent: the user did not allow ${provider?.label ?? model.provider} in this session.`);
    }
    this.confirmedProviders.add(key);
  }

  private async apiKey(providerId: string, envName: string | undefined): Promise<string | undefined> {
    if (envName && process.env[envName]) {
      return process.env[envName];
    }
    return this.context.secrets.get(SECRET_PREFIX + providerId);
  }

  async setApiKey(providerId: string, key: string): Promise<void> {
    await this.context.secrets.store(SECRET_PREFIX + providerId, key);
  }

  /** Chat backend for an API or VS Code model; `chatModel` is the Chat view's own model. */
  async backendFor(registry: Registry, model: Model, chatModel?: vscode.LanguageModelChat): Promise<ChatBackend> {
    const harness = findHarness(registry, model.harness);
    if (harness?.runner === 'vscode-lm') {
      const lm = chatModel && lmModelId(chatModel) === model.id
        ? chatModel
        : (await this.lmModels()).find((m) => lmModelId(m) === model.id);
      if (!lm) {
        throw new Error(`VS Code language model ${model.id} is not available (is its provider extension installed and signed in?).`);
      }
      return new LmBackend(lm as unknown as LmChatModel, lmBindings(), 'Kit Workbench runs your delegated task with this model.');
    }
    if (harness?.runner === 'api') {
      const provider = findProvider(registry, model.provider);
      if (!provider?.baseUrl || provider.api === 'none') {
        throw new Error(`Provider ${model.provider} has no OpenAI-compatible baseUrl.`);
      }
      const key = await this.apiKey(provider.id, provider.apiKeyEnv);
      if (!key && provider.kind === 'cloud') {
        throw new Error(`No API key for ${provider.label}: set ${provider.apiKeyEnv ?? 'one'} or run "Kit Workbench: Set Provider API Key".`);
      }
      return new HttpBackend({
        label: model.label,
        url: chatCompletionsUrl(provider.baseUrl, provider.api === 'ollama' ? 'ollama' : 'openai'),
        model: model.modelRef,
        apiKey: key,
      });
    }
    throw new Error(`Model ${model.id} runs in a terminal, not through an API.`);
  }

  /** Knowledge search switch: the task wins, then the (per-project) setting. */
  brainEnabled(task?: boolean, cwd?: string): boolean {
    if (task === false) {
      return false;
    }
    const scope = cwd ? vscode.Uri.file(cwd) : undefined;
    return vscode.workspace.getConfiguration('kitWorkbench', scope).get<boolean>('brainSearch', true);
  }

  async promptContext(cwd: string, brainEnabled = this.brainEnabled(undefined, cwd)): Promise<PromptContext> {
    const projectRules = join(cwd, 'AGENTS.md');
    const kitRules = expandHome(this.config().get<string>('rulesFile', '~/work/kit/modules/30-agent-setup/source/AGENTS.md'));
    let rules = await readIfExists(projectRules, 30_000);
    let rulesSource = projectRules;
    if (rules === undefined) {
      rules = await readIfExists(kitRules, 30_000);
      rulesSource = kitRules;
    }
    return {
      rules,
      rulesSource,
      skills: await listSkills(this.skillsDir),
      brainAvailable: (await this.brain.available()) !== undefined,
      brainEnabled,
      cwd,
    };
  }

  // --- runs ---------------------------------------------------------------------------------

  async spawn(input: SpawnInput, origin: string, cwdOverride?: string, chatModel?: vscode.LanguageModelChat): Promise<{ runId: string; model: string; resultFile: string }> {
    const fallback = chatModel ? lmModelEntry(chatModel) : undefined;
    const { registry, model } = await this.resolveModel(input.model, fallback);
    const harness = findHarness(registry, model.harness);
    if (!harness) {
      throw new Error(`Model ${model.id} names an unknown harness ${model.harness}.`);
    }
    if (harness.runner !== 'terminal') {
      await this.confirmCloud(registry, model);
    }
    const cwd = cwdOverride ? expandHome(cwdOverride) : this.workspaceDir();
    const id = newId();
    const files = runFiles(this.stateDir, id);
    const meta: RunMeta = {
      id,
      name: slug(input.name),
      role: 'worker',
      modelId: model.id,
      modelLabel: model.label,
      runner: harness.runner,
      cwd,
      paths: input.paths,
      done: input.done,
      status: 'running',
      createdAt: new Date().toISOString(),
      origin,
      owner: process.pid,
    };
    const brain = this.brainEnabled(input.brain, cwd);
    meta.brain = brain;
    const task = renderTask({ name: meta.name, task: input.task, paths: input.paths, done: input.done, cwd, resultFile: files.result, brain });
    await createRun(this.stateDir, meta, task);
    this.output.appendLine(`[${id}] ${meta.name}: started with ${model.label} (${harness.runner}, from ${origin})`);

    if (harness.runner === 'terminal') {
      const launch = terminalLaunch(registry, harness, model, {
        name: meta.name,
        cwd,
        prompt: workerPrompt(files.task, files.result),
        effort: model.defaultEffort,
        autonomy: this.config().get<boolean>('workerAutonomy', false),
        runDir: files.dir,
        taskFile: files.task,
        resultFile: files.result,
      });
      const terminal = vscode.window.createTerminal({
        name: `worker: ${meta.name}`,
        cwd,
        env: { ...launch.env, BROWSER: 'true', KIT_WB_RUN: id, KIT_WB_STATE: this.stateDir },
        iconPath: new vscode.ThemeIcon('person'),
      });
      if (this.config().get<boolean>('revealWorkers', true)) {
        terminal.show(true);
      }
      terminal.sendText(launch.commandLine, true);
      if (launch.sendPromptAfterStart) {
        const delay = this.config().get<number>('promptDelayMs', 2500);
        setTimeout(() => terminal.sendText(workerPrompt(files.task, files.result), true), delay);
      }
      this.active.set(id, { terminal });
    } else {
      const backend = await this.backendFor(registry, model, chatModel);
      const abort = new AbortController();
      this.active.set(id, { abort });
      if (this.config().get<boolean>('revealWorkers', true)) {
        this.output.show(true);
      }
      void this.runApiWorker(meta, backend, task, abort);
    }
    this.changed.fire();
    return { runId: id, model: model.id, resultFile: files.result };
  }

  private async runApiWorker(meta: RunMeta, backend: ChatBackend, task: string, abort: AbortController): Promise<void> {
    const files = runFiles(this.stateDir, meta.id);
    const log = (event: LoopEvent) => {
      if (event.type === 'text') {
        this.output.appendLine(`[${meta.id}] ${previewText(event.text, 300)}`);
        return appendLog(this.stateDir, meta.id, { type: 'text', text: event.text });
      }
      if (event.type === 'tool-call') {
        this.output.appendLine(`[${meta.id}] tool ${event.call.name}`);
        return appendLog(this.stateDir, meta.id, { type: 'tool-call', name: event.call.name, input: event.call.input });
      }
      return appendLog(this.stateDir, meta.id, { type: 'tool-result', name: event.call.name, content: previewText(event.content, 2000) });
    };
    try {
      const ctx = await this.promptContext(meta.cwd, meta.brain !== false);
      const messages: ChatMessage[] = [
        { role: 'system', content: workerSystemPrompt(ctx) },
        { role: 'user', content: task },
      ];
      const tools = workerTools({ cwd: meta.cwd, paths: meta.paths, resultFile: files.result, brain: meta.brain === false ? undefined : this.brain, skillsDir: this.skillsDir });
      const result = await runAgentLoop(backend, messages, tools, {
        maxSteps: this.config().get<number>('maxSteps', 40),
        signal: abort.signal,
        onEvent: log,
      });
      if (result.stoppedBy === 'aborted') {
        await markRun(this.stateDir, meta.id, 'stopped', 'stopped');
      } else if (!(await readResult(this.stateDir, meta.id))) {
        const reason = result.stoppedBy === 'max-steps' ? 'step limit reached' : 'the model ended without calling finish';
        await writeFile(files.result, `${result.finalText.trim()}\n\nFAILED: ${reason}\n`, 'utf8');
      }
    } catch (error) {
      if (abort.signal.aborted) {
        await markRun(this.stateDir, meta.id, 'stopped', 'stopped');
      } else {
        const message = (error as Error).message;
        this.output.appendLine(`[${meta.id}] error: ${message}`);
        await markRun(this.stateDir, meta.id, 'failed', previewText(message, 200));
      }
    } finally {
      await settleFromResult(this.stateDir, meta.id);
      this.active.delete(meta.id);
      const final = await readMeta(this.stateDir, meta.id);
      this.output.appendLine(`[${meta.id}] ${meta.name}: ${final?.status ?? 'unknown'}`);
      this.changed.fire();
    }
  }

  private async onTerminalClosed(terminal: vscode.Terminal): Promise<void> {
    if (terminal === this.orchestratorTerminal) {
      this.orchestratorTerminal = undefined;
    }
    for (const [id, run] of this.active) {
      if (run.terminal !== terminal) {
        continue;
      }
      this.active.delete(id);
      if (!(await settleFromResult(this.stateDir, id))) {
        await markRun(this.stateDir, id, 'failed', 'terminal closed without a result');
      }
      this.changed.fire();
    }
  }

  async stop(id: string): Promise<void> {
    const run = this.active.get(id);
    await markRun(this.stateDir, id, 'stopped', 'stopped by the user');
    run?.abort?.abort();
    run?.terminal?.dispose();
    this.active.delete(id);
    this.changed.fire();
  }

  terminalOf(id: string): vscode.Terminal | undefined {
    return this.active.get(id)?.terminal;
  }

  runs(): Promise<RunMeta[]> {
    return listRuns(this.stateDir);
  }

  async describeRuns(): Promise<string> {
    const runs = (await this.runs()).slice(0, 30);
    if (runs.length === 0) {
      return 'No worker runs yet.';
    }
    return 'Runs (newest first):\n' + runs
      .map((r) => `- ${r.id} ${r.name}: ${r.status}${r.reason ? ` (${r.reason})` : ''}, ${r.modelLabel}, started ${relativeTime(r.createdAt)}`)
      .join('\n');
  }

  async readRun(id: string): Promise<string> {
    const meta = await readMeta(this.stateDir, id);
    if (!meta) {
      return `No run with id ${id}.`;
    }
    const result = await readResult(this.stateDir, id);
    return [
      `Run ${id} (${meta.name}): ${meta.status}${meta.reason ? ` (${meta.reason})` : ''}`,
      `Model: ${meta.modelLabel}; paths: ${meta.paths.join(', ') || 'none given'}`,
      '',
      result?.trim() ? result : '(no result file yet)',
    ].join('\n');
  }

  // --- orchestrators ------------------------------------------------------------------------

  /** Runs one orchestrator turn with an API or VS Code model. */
  async orchestratorTurn(
    backend: ChatBackend,
    history: ChatMessage[],
    origin: string,
    signal: AbortSignal,
    onEvent: (event: LoopEvent) => void | Promise<void>,
    chatModel?: vscode.LanguageModelChat,
  ): Promise<ChatMessage[]> {
    const cwd = this.workspaceDir();
    const brainOn = this.brainEnabled(undefined, cwd);
    const ctx = await this.promptContext(cwd, brainOn);
    const api: WorkbenchApi = {
      spawn: (input, o) => this.spawn(input, o, undefined, chatModel),
      describeRuns: () => this.describeRuns(),
      describeModels: () => this.describeModels(),
      readRun: (id) => this.readRun(id),
    };
    const messages: ChatMessage[] = [{ role: 'system', content: orchestratorSystemPrompt(ctx) }, ...history];
    const result = await runAgentLoop(backend, messages, orchestratorTools(api, brainOn ? this.brain : undefined, this.skillsDir, origin), {
      maxSteps: this.config().get<number>('maxSteps', 40),
      signal,
      onEvent,
    });
    return result.messages.slice(1);
  }

  /** Writes the orchestrator guide for terminal orchestrators and returns its path. */
  async orchestratorGuide(): Promise<string> {
    const source = join(this.context.extensionPath, 'resources', 'orchestrator.md');
    const target = join(this.stateDir, 'ORCHESTRATOR.md');
    const text = (await readFile(source, 'utf8'))
      .replaceAll('{{KIT_WB}}', join(this.binDir, 'kit-wb'))
      .replaceAll('{{MODELS}}', await this.describeModels());
    await writeFile(target, text, 'utf8');
    return target;
  }

  async startTerminalOrchestrator(model: Model): Promise<vscode.Terminal> {
    const registry = await this.registry();
    const harness = findHarness(registry, model.harness);
    if (!harness || harness.runner !== 'terminal') {
      throw new Error(`${model.label} does not run in a terminal; use the orchestrator panel or @workbench.`);
    }
    const guide = await this.orchestratorGuide();
    const cwd = this.workspaceDir();
    const launch = terminalLaunch(registry, harness, model, {
      name: 'orchestrator',
      cwd,
      prompt: orchestratorPrompt(guide),
      effort: model.defaultEffort,
      autonomy: false,
    });
    const terminal = vscode.window.createTerminal({
      name: `orchestrator: ${harness.label}`,
      cwd,
      env: { ...launch.env, BROWSER: 'true', KIT_WB_STATE: this.stateDir, PATH: `${this.binDir}:${process.env.PATH ?? ''}` },
      iconPath: new vscode.ThemeIcon('organization'),
    });
    terminal.show();
    terminal.sendText(launch.commandLine, true);
    if (launch.sendPromptAfterStart) {
      setTimeout(() => terminal.sendText(orchestratorPrompt(guide), true), this.config().get<number>('promptDelayMs', 2500));
    }
    this.orchestratorTerminal = terminal;
    return terminal;
  }

  /** The user's edited data classes (installed by 40-data-guard), else the kit's copy. */
  async dataClassesFile(): Promise<string | undefined> {
    for (const file of [expandHome('~/.config/work-kit/data-classes.md'), expandHome('~/work/kit/modules/40-data-guard/data-classes.md')]) {
      if ((await readIfExists(file, 1)) !== undefined) {
        return file;
      }
    }
    return undefined;
  }

  // --- model picker, templates, overview, status ------------------------------------------

  async readinessFacts(registry: Registry): Promise<ReadinessFacts> {
    const found = new Set<string>();
    for (const cmd of new Set(registry.harnesses.filter((h) => h.runner === 'terminal' && h.command).map((h) => h.command!))) {
      if (await findExecutable(cmd)) {
        found.add(cmd);
      }
    }
    const keys = new Set<string>();
    for (const p of registry.providers.filter((p) => p.kind === 'cloud')) {
      if (await this.apiKey(p.id, p.apiKeyEnv)) {
        keys.add(p.id);
      }
    }
    return {
      commandFound: (c) => found.has(c),
      hasKey: (id) => keys.has(id),
      lmIds: new Set(registry.models.filter((m) => m.source === 'vscode-lm').map((m) => m.id)),
    };
  }

  /** Models for a role with runner, locality and readiness; ready ones first. */
  async modelChoices(role: Role): Promise<ModelChoice[]> {
    const registry = await this.registry();
    return modelChoices(registry, modelsForRole(registry, role), await this.readinessFacts(registry));
  }

  templates(): Promise<TaskTemplate[]> {
    return listTemplates(this.builtinTemplatesDir, this.templatesDir);
  }

  async spawnFromTemplate(
    name: string,
    values: Record<string, string>,
    overrides: { model?: string; name?: string } = {},
    origin = 'template',
  ): Promise<{ runId: string; model: string; resultFile: string }> {
    const template = (await this.templates()).find((t) => t.name === name);
    if (!template) {
      throw new Error(`No task template named "${name}".`);
    }
    const input = templateSpawn(template, values, overrides.name);
    return this.spawn({ ...input, model: overrides.model || input.model }, origin);
  }

  /** Starts a finished run's task again, with the same paths and done criterion, on another model. */
  async rerun(id: string, modelId?: string): Promise<{ runId: string; model: string; resultFile: string }> {
    const meta = await readMeta(this.stateDir, id);
    if (!meta) {
      throw new Error(`No run with id ${id}.`);
    }
    const task = taskBody(await readFile(runFiles(this.stateDir, id).task, 'utf8'));
    return this.spawn(
      { name: meta.name, task, model: modelId || meta.modelId, paths: meta.paths, done: meta.done, brain: meta.brain },
      'rerun',
      meta.cwd,
    );
  }

  async archive(only?: readonly string[]): Promise<string[]> {
    const moved = await archiveRuns(this.stateDir, 0, only);
    if (moved.length > 0) {
      this.changed.fire();
    }
    return moved;
  }

  async runCards(limit = 60): Promise<RunCard[]> {
    const runs = (await this.runs()).slice(0, limit);
    return Promise.all(runs.map(async (meta) => ({
      meta,
      result: await readResult(this.stateDir, meta.id),
      lastActivity: await lastActivity(this.stateDir, meta.id),
    })));
  }

  /** Brain, skills, rules, data guard, models: cached for 30 s unless `fresh`. */
  async status(fresh = false): Promise<StatusItem[]> {
    if (!fresh && this.statusCache && Date.now() - this.statusCache.at < 30_000) {
      return this.statusCache.items;
    }
    const cwd = this.workspaceDir();
    const brainBinary = await this.brainBinary();
    const brainEnabled = this.brainEnabled(undefined, cwd);
    const ctx = await this.promptContext(cwd, brainEnabled);
    const guard = await findExecutable('data-guard');
    let guardStatus: string | undefined;
    if (guard) {
      guardStatus = await new Promise<string>((resolve) => {
        execFile(guard, ['status'], { cwd, timeout: 10_000 }, (error, stdout) => resolve(error && !stdout ? `data-guard status failed: ${error.message}` : String(stdout)));
      });
    }
    const registry = await this.registry();
    const choices = modelChoices(registry, modelsForRole(registry, 'worker'), await this.readinessFacts(registry));
    const items = statusItems({
      brainBinary,
      brainEnabled,
      brainStatus: brainBinary && brainEnabled ? await this.brain.status() : undefined,
      skillsDir: this.skillsDir,
      skillCount: ctx.skills.length,
      rulesSource: ctx.rules ? ctx.rulesSource : undefined,
      rulesIsProject: ctx.rulesSource === join(cwd, 'AGENTS.md'),
      dataGuardBinary: guard,
      dataGuardStatus: guardStatus,
      dataClassesFile: await this.dataClassesFile(),
      confirmCloud: this.config().get<boolean>('confirmCloudModels', true),
      registryFile: this.registryPath,
      registryExists: (await readIfExists(this.registryPath, 1)) !== undefined,
      modelCounts: {
        ready: choices.filter((c) => c.readiness === 'ready').length,
        total: choices.length,
        lm: choices.filter((c) => c.model.source === 'vscode-lm').length,
      },
      kitWbOnPath: await findExecutable('kit-wb'),
      workerAutonomy: this.config().get<boolean>('workerAutonomy', false),
    });
    this.statusCache = { at: Date.now(), items };
    return items;
  }

  async brainBinary(): Promise<string | undefined> {
    return findExecutable(this.config().get<string>('brainCommand', 'brain'));
  }
}
