// Kit Workbench entry point: commands, workers view, chat participant, LM tools, brain MCP server.
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, relative } from 'node:path';
import * as vscode from 'vscode';
import { LmBackend, type LmChatModel } from './agent/lmBackend.ts';
import type { ChatMessage } from './agent/loop.ts';
import { spawnInputFrom } from './agent/tools.ts';
import { readSkill } from './skills.ts';
import { relativeTime, selectionReference } from './format.ts';
import { OrchestratorPanel } from './panel.ts';
import { READINESS_LABEL } from './readiness.ts';
import type { StatusItem } from './status.ts';
import { variablesOf } from './templates.ts';
import { OverviewPanel, ResultPanel } from './views.ts';
import { runFiles, type RunMeta } from './runs.ts';
import { lmBindings, lmModelId, Workbench } from './workbench.ts';

const STATUS_ICON: Record<RunMeta['status'], vscode.ThemeIcon> = {
  running: new vscode.ThemeIcon('sync~spin'),
  done: new vscode.ThemeIcon('pass', new vscode.ThemeColor('testing.iconPassed')),
  failed: new vscode.ThemeIcon('error', new vscode.ThemeColor('testing.iconFailed')),
  stopped: new vscode.ThemeIcon('circle-slash'),
};

class RunItem extends vscode.TreeItem {
  readonly run: RunMeta;

  constructor(run: RunMeta) {
    super(run.name, vscode.TreeItemCollapsibleState.None);
    this.run = run;
    this.id = run.id;
    this.description = `${run.status} · ${run.modelLabel} · ${relativeTime(run.createdAt)}`;
    this.tooltip = new vscode.MarkdownString(
      [
        `**${run.name}** (${run.id})`,
        `Status: ${run.status}${run.reason ? ` (${run.reason})` : ''}`,
        `Model: ${run.modelLabel} (${run.runner})`,
        `Paths: ${run.paths.join(', ') || 'none given'}`,
        `Done when: ${run.done || 'not given'}`,
      ].join('\n\n'),
    );
    this.iconPath = STATUS_ICON[run.status];
    this.contextValue = `run-${run.status}`;
    this.command = { command: 'kitWorkbench.showWorker', title: 'Show Worker', arguments: [this] };
  }
}

class WorkersView implements vscode.TreeDataProvider<RunItem> {
  private readonly changed = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.changed.event;

  private readonly workbench: Workbench;

  constructor(workbench: Workbench) {
    this.workbench = workbench;
    workbench.onDidChange(() => this.changed.fire());
  }

  refresh(): void {
    this.changed.fire();
  }

  getTreeItem(item: RunItem): vscode.TreeItem {
    return item;
  }

  async getChildren(): Promise<RunItem[]> {
    return (await this.workbench.runs()).slice(0, 100).map((r) => new RunItem(r));
  }
}

async function pickRun(workbench: Workbench, arg: unknown, filter?: (r: RunMeta) => boolean): Promise<RunMeta | undefined> {
  if (arg instanceof RunItem) {
    return arg.run;
  }
  if (typeof arg === 'string') {
    return (await workbench.runs()).find((r) => r.id === arg);
  }
  const runs = (await workbench.runs()).filter(filter ?? (() => true));
  const pick = await vscode.window.showQuickPick(
    runs.map((r) => ({ label: r.name, description: `${r.status} · ${r.modelLabel}`, detail: r.id, run: r })),
    { placeHolder: 'Select a run' },
  );
  return pick?.run;
}

async function pickModel(
  workbench: Workbench,
  role: 'worker' | 'orchestrator',
  terminalOnly = false,
  placeHolder = role === 'worker' ? 'Model for the worker' : 'Model for the orchestrator',
) {
  const choices = (await workbench.modelChoices(role)).filter((c) => !terminalOnly || c.runner === 'terminal');
  const def = vscode.workspace.getConfiguration('kitWorkbench').get<string>('defaultWorkerModel', '');
  const pick = await vscode.window.showQuickPick(
    choices.map((c) => ({
      label: `${c.readiness === 'ready' ? '$(check)' : '$(warning)'} ${c.model.label}`,
      description: [c.model.id, c.runner, c.local ? 'local' : 'leaves this machine', c.readiness === 'ready' ? '' : READINESS_LABEL[c.readiness], c.model.id === def ? 'default' : '']
        .filter(Boolean).join(' · '),
      detail: [c.model.goodFor && `good for: ${c.model.goodFor}`, c.model.notFor && `not for: ${c.model.notFor}`].filter(Boolean).join('; ') || undefined,
      model: c.model,
    })),
    { placeHolder, matchOnDescription: true, matchOnDetail: true },
  );
  return pick?.model;
}

const LEVEL_ICON: Record<StatusItem['level'], vscode.ThemeIcon> = {
  ok: new vscode.ThemeIcon('pass', new vscode.ThemeColor('testing.iconPassed')),
  off: new vscode.ThemeIcon('circle-slash'),
  warn: new vscode.ThemeIcon('warning', new vscode.ThemeColor('editorWarning.foreground')),
  missing: new vscode.ThemeIcon('circle-large-outline'),
};

class StatusView implements vscode.TreeDataProvider<StatusItem> {
  private readonly changed = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.changed.event;
  private readonly workbench: Workbench;
  private fresh = false;

  constructor(workbench: Workbench) {
    this.workbench = workbench;
  }

  refresh(): void {
    this.fresh = true;
    this.changed.fire();
  }

  getTreeItem(item: StatusItem): vscode.TreeItem {
    const t = new vscode.TreeItem(item.label, vscode.TreeItemCollapsibleState.None);
    t.description = item.detail;
    t.iconPath = LEVEL_ICON[item.level];
    t.tooltip = [item.detail, ...(item.more ?? [])].join('\n');
    t.contextValue = `status-${item.id}`;
    if (item.action) {
      t.command = { command: item.action, title: item.label };
    }
    return t;
  }

  async getChildren(): Promise<StatusItem[]> {
    const fresh = this.fresh;
    this.fresh = false;
    return this.workbench.status(fresh);
  }
}

function toolResult(text: string): vscode.LanguageModelToolResult {
  return new vscode.LanguageModelToolResult([new vscode.LanguageModelTextPart(text)]);
}

function registerLmTools(context: vscode.ExtensionContext, workbench: Workbench): void {
  if (!vscode.lm?.registerTool) {
    return;
  }
  const tool = <T>(name: string, invoke: (input: T) => Promise<string>, confirm?: (input: T) => vscode.PreparedToolInvocation) => {
    context.subscriptions.push(
      vscode.lm.registerTool<T>(name, {
        async invoke(options) {
          try {
            return toolResult(await invoke(options.input));
          } catch (error) {
            return toolResult(`Error: ${(error as Error).message}`);
          }
        },
        prepareInvocation: confirm ? (options) => confirm(options.input) : undefined,
      }),
    );
  };
  tool<Record<string, unknown>>(
    'kit_spawn_worker',
    async (input) => {
      const r = await workbench.spawn(spawnInputFrom(input), 'tool');
      return `Started run ${r.runId} with ${r.model}. Result file: ${r.resultFile}`;
    },
    (input) => ({
      invocationMessage: `Starting worker ${String(input.name ?? '')}`,
      confirmationMessages: {
        title: 'Start a Kit Workbench worker?',
        message: new vscode.MarkdownString(
          `Worker **${String(input.name ?? 'worker')}** with model \`${String(input.model ?? 'default')}\`\n\n` +
            `Paths: ${Array.isArray(input.paths) ? input.paths.join(', ') : 'none given'}`,
        ),
      },
    }),
  );
  tool('kit_list_workers', async () => `${await workbench.describeRuns()}\n\n${await workbench.describeModels()}`);
  tool<{ runId: string }>('kit_read_result', (input) => workbench.readRun(String(input.runId ?? '')));
  tool<{ query: string; k?: number }>('kit_brain_search', (input) => workbench.brain.search(String(input.query ?? ''), Number(input.k ?? 5) || 5));
  tool<{ name: string }>('kit_read_skill', async (input) => (await readSkill(workbench.skillsDir, String(input.name ?? ''))) ?? 'No such skill.');
}

function registerBrainMcp(context: vscode.ExtensionContext, workbench: Workbench): void {
  const lm = vscode.lm as typeof vscode.lm & { registerMcpServerDefinitionProvider?: typeof vscode.lm.registerMcpServerDefinitionProvider };
  if (!lm?.registerMcpServerDefinitionProvider || !vscode.McpStdioServerDefinition) {
    return;
  }
  context.subscriptions.push(
    lm.registerMcpServerDefinitionProvider('kitWorkbench.brain', {
      async provideMcpServerDefinitions() {
        const bin = await workbench.brainBinary();
        return bin ? [new vscode.McpStdioServerDefinition('Kit brain', bin, ['mcp'])] : [];
      },
    }),
  );
}

/** Rebuilds the loop history from the Chat view's history (text only). */
function chatHistory(context: vscode.ChatContext): ChatMessage[] {
  const out: ChatMessage[] = [];
  for (const turn of context.history) {
    if (turn instanceof vscode.ChatRequestTurn) {
      out.push({ role: 'user', content: turn.prompt });
    } else if (turn instanceof vscode.ChatResponseTurn) {
      const text = turn.response
        .map((part) => (part instanceof vscode.ChatResponseMarkdownPart ? part.value.value : ''))
        .join('');
      if (text) {
        out.push({ role: 'assistant', content: text });
      }
    }
  }
  return out;
}

function registerChatParticipant(context: vscode.ExtensionContext, workbench: Workbench): void {
  if (!vscode.chat?.createChatParticipant) {
    return;
  }
  const participant = vscode.chat.createChatParticipant('kitWorkbench.orchestrator', async (request, chatContext, stream, token) => {
    const abort = new AbortController();
    const sub = token.onCancellationRequested(() => abort.abort());
    try {
      const registry = await workbench.registry();
      const entry = registry.models.find((m) => m.id === lmModelId(request.model));
      if (entry) {
        await workbench.confirmCloud(registry, entry);
      }
      const backend = new LmBackend(request.model as unknown as LmChatModel, lmBindings(), 'Kit Workbench orchestrator');
      const history = [...chatHistory(chatContext), { role: 'user' as const, content: request.prompt }];
      await workbench.orchestratorTurn(backend, history, 'chat', abort.signal, (event) => {
        if (event.type === 'text') {
          stream.markdown(event.text + '\n\n');
        } else if (event.type === 'tool-call') {
          stream.progress(`${event.call.name}…`);
        }
      }, request.model);
    } catch (error) {
      stream.markdown(`Error: ${(error as Error).message}`);
    } finally {
      sub.dispose();
    }
    return {};
  });
  participant.iconPath = new vscode.ThemeIcon('organization');
  context.subscriptions.push(participant);
}

async function spawnWorkerCommand(workbench: Workbench): Promise<void> {
  const task = await vscode.window.showInputBox({ prompt: 'Task for the worker', placeHolder: 'What should the worker do?', ignoreFocusOut: true });
  if (!task) {
    return;
  }
  const model = await pickModel(workbench, 'worker');
  if (!model) {
    return;
  }
  const name = await vscode.window.showInputBox({ prompt: 'Worker name', value: task.split(/\s+/).slice(0, 3).join(' '), ignoreFocusOut: true });
  if (name === undefined) {
    return;
  }
  const paths = await vscode.window.showInputBox({ prompt: 'Exclusive paths (comma separated, relative to the workspace; empty = none given)', ignoreFocusOut: true });
  if (paths === undefined) {
    return;
  }
  const done = await vscode.window.showInputBox({ prompt: 'Done criterion (checkable)', ignoreFocusOut: true });
  if (done === undefined) {
    return;
  }
  const r = await workbench.spawn(spawnInputFrom({ name, task, model: model.id, paths, done }), 'user');
  vscode.window.showInformationMessage(`Worker started: ${r.runId}`);
}

async function spawnFromTemplateCommand(workbench: Workbench, arg: unknown): Promise<string | undefined> {
  // Tests and keybindings may pass { template, values, model, name } to skip the dialogs.
  const given = (arg && typeof arg === 'object' ? arg : {}) as { template?: string; values?: Record<string, string>; model?: string; name?: string };
  const templates = await workbench.templates();
  let template = templates.find((t) => t.name === given.template);
  if (!template) {
    const pick = await vscode.window.showQuickPick(
      templates.map((t) => ({ label: t.name, description: t.source === 'user' ? 'yours' : 'built-in', detail: t.description, template: t })),
      { placeHolder: `Task template (add your own to ${workbench.templatesDir})`, matchOnDetail: true },
    );
    template = pick?.template;
  }
  if (!template) {
    return undefined;
  }
  const values: Record<string, string> = { ...(given.values ?? {}) };
  for (const v of variablesOf(template)) {
    if (values[v] !== undefined) {
      continue;
    }
    const value = await vscode.window.showInputBox({ prompt: `${template.name}: ${v}`, ignoreFocusOut: true });
    if (value === undefined) {
      return undefined;
    }
    values[v] = value;
  }
  let model = given.model;
  if (!model && !given.template) {
    // The template's model is the preselected default; the picker lets the human change it.
    const picked = await pickModel(workbench, 'worker', false, template.model ? `Model (template default: ${template.model}; Escape keeps it)` : 'Model for the worker');
    model = picked?.id ?? template.model;
    if (!model && !template.model) {
      return undefined;
    }
  }
  const r = await workbench.spawnFromTemplate(template.name, values, { model, name: given.name });
  vscode.window.showInformationMessage(`Worker started from template ${template.name}: ${r.runId}`);
  return r.runId;
}

/**
 * Sends a reference to this window's terminal orchestrator, else text into the orchestrator
 * panel's input. A terminal gets one line only (`path:lines `): a newline would submit the
 * prompt, and a CLI agent reads the file itself. Nothing is submitted; the human sends it.
 */
function sendToOrchestrator(workbench: Workbench, terminalText: string, panelText = terminalText): 'terminal' | 'panel' {
  const terminal = workbench.orchestratorTerminal;
  if (terminal && terminal.exitStatus === undefined) {
    terminal.show(false);
    terminal.sendText(terminalText, false);
    return 'terminal';
  }
  OrchestratorPanel.show(workbench).insert(panelText);
  return 'panel';
}

function workspaceRelative(workbench: Workbench, file: string): string {
  const rel = relative(workbench.workspaceDir(), file);
  return rel && !rel.startsWith('..') ? rel : file;
}

export async function activate(context: vscode.ExtensionContext): Promise<{ workbench: Workbench }> {
  const workbench = new Workbench(context);
  context.subscriptions.push(workbench);
  const view = new WorkersView(workbench);
  context.subscriptions.push(vscode.window.registerTreeDataProvider('kitWorkbench.workers', view));
  const statusView = new StatusView(workbench);
  context.subscriptions.push(vscode.window.registerTreeDataProvider('kitWorkbench.status', statusView));

  // Status bar: running workers at a glance, click opens the overview.
  const bar = vscode.window.createStatusBarItem('kitWorkbench.workers', vscode.StatusBarAlignment.Left, 50);
  bar.name = 'Kit Workbench workers';
  bar.command = 'kitWorkbench.openOverview';
  const updateBar = async () => {
    const runs = await workbench.runs();
    const running = runs.filter((r) => r.status === 'running').length;
    const failed = runs.filter((r) => r.status === 'failed').length;
    bar.text = `$(organization) ${running}${failed > 0 ? ` $(error) ${failed}` : ''}`;
    bar.tooltip = `Kit Workbench: ${running} running, ${failed} failed. Click for the worker overview.`;
    bar.show();
  };
  context.subscriptions.push(bar, workbench.onDidChange(() => void updateBar()));

  const command = (id: string, fn: (...args: unknown[]) => unknown) =>
    context.subscriptions.push(
      vscode.commands.registerCommand(id, async (...args: unknown[]) => {
        try {
          return await fn(...args);
        } catch (error) {
          vscode.window.showErrorMessage(`Kit Workbench: ${(error as Error).message}`);
          return undefined;
        }
      }),
    );

  command('kitWorkbench.spawnWorker', () => spawnWorkerCommand(workbench));
  command('kitWorkbench.startOrchestratorTerminal', async () => {
    const model = await pickModel(workbench, 'orchestrator', true);
    if (model) {
      await workbench.startTerminalOrchestrator(model);
    }
  });
  command('kitWorkbench.openOrchestratorPanel', () => OrchestratorPanel.show(workbench));
  command('kitWorkbench.refresh', async () => {
    await workbench.poll();
    view.refresh();
  });
  command('kitWorkbench.openResult', async (arg) => {
    const run = await pickRun(workbench, arg);
    if (run) {
      const file = runFiles(workbench.stateDir, run.id).result;
      try {
        await vscode.window.showTextDocument(vscode.Uri.file(file), { preview: true });
      } catch {
        vscode.window.showInformationMessage(`${run.name} has no result yet.`);
      }
    }
  });
  command('kitWorkbench.openTask', async (arg) => {
    const run = await pickRun(workbench, arg);
    if (run) {
      await vscode.window.showTextDocument(vscode.Uri.file(runFiles(workbench.stateDir, run.id).task), { preview: true });
    }
  });
  command('kitWorkbench.showWorker', async (arg) => {
    const run = await pickRun(workbench, arg);
    if (!run) {
      return;
    }
    const terminal = workbench.terminalOf(run.id);
    if (terminal) {
      terminal.show();
    } else if (run.status === 'running') {
      workbench.output.show(true);
    } else {
      await ResultPanel.show(workbench, run.id);
    }
  });
  command('kitWorkbench.stopWorker', async (arg) => {
    const run = await pickRun(workbench, arg, (r) => r.status === 'running');
    if (run) {
      await workbench.stop(run.id);
    }
  });
  command('kitWorkbench.listModels', async () => {
    const text = await workbench.describeModels();
    const doc = await vscode.workspace.openTextDocument({ content: text, language: 'markdown' });
    await vscode.window.showTextDocument(doc, { preview: true });
    return text;
  });
  command('kitWorkbench.discoverModels', async () => {
    const lines = await workbench.discover();
    vscode.window.showInformationMessage(lines.join(' · ') || 'No local providers configured.');
    return lines;
  });
  command('kitWorkbench.openRegistry', async () => {
    const file = workbench.registryPath;
    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(file));
    } catch {
      await mkdir(dirname(file), { recursive: true });
      await writeFile(file, JSON.stringify({ version: 1, providers: [], harnesses: [], models: [] }, null, 2) + '\n', 'utf8');
    }
    await vscode.window.showTextDocument(vscode.Uri.file(file));
  });
  command('kitWorkbench.setApiKey', async () => {
    const registry = await workbench.registry();
    const pick = await vscode.window.showQuickPick(
      registry.providers.filter((p) => p.api !== 'none').map((p) => ({ label: p.label, description: p.id, provider: p })),
      { placeHolder: 'Provider' },
    );
    if (!pick) {
      return;
    }
    const key = await vscode.window.showInputBox({ prompt: `API key for ${pick.label} (stored in VS Code SecretStorage)`, password: true, ignoreFocusOut: true });
    if (key) {
      await workbench.setApiKey(pick.provider.id, key.trim());
      vscode.window.showInformationMessage(`API key for ${pick.label} saved.`);
    }
  });
  command('kitWorkbench.brainSearch', async () => {
    const query = await vscode.window.showInputBox({ prompt: 'Search the brain' });
    if (!query) {
      return;
    }
    const doc = await vscode.workspace.openTextDocument({ content: await workbench.brain.search(query, 10), language: 'markdown' });
    await vscode.window.showTextDocument(doc, { preview: true });
  });

  command('kitWorkbench.openOverview', async () => OverviewPanel.show(workbench).render());
  command('kitWorkbench.viewResult', async (arg) => {
    const run = await pickRun(workbench, arg);
    return run ? (await ResultPanel.show(workbench, run.id)).html : undefined;
  });
  command('kitWorkbench.rerunWorker', async (arg, modelArg) => {
    const run = await pickRun(workbench, arg, (r) => r.status !== 'running');
    if (!run) {
      return undefined;
    }
    const modelId = typeof modelArg === 'string' ? modelArg : (await pickModel(workbench, 'worker', false, `Run "${run.name}" again with (was: ${run.modelLabel})`))?.id;
    if (!modelId) {
      return undefined;
    }
    const r = await workbench.rerun(run.id, modelId);
    vscode.window.showInformationMessage(`Worker started again: ${r.runId}`);
    return r.runId;
  });
  command('kitWorkbench.spawnFromTemplate', (arg) => spawnFromTemplateCommand(workbench, arg));
  command('kitWorkbench.openTemplatesFolder', async () => {
    const dir = workbench.templatesDir;
    await mkdir(dir, { recursive: true });
    const example = `${dir}/example.md`;
    if ((await workbench.templates()).every((t) => t.source !== 'user')) {
      await writeFile(example, [
        '---', 'name: example', 'description: Copy this file to add your own task template', 'paths: {{folder}}/',
        'done: {{folder}}/NOTES.md exists and answers the question', '---',
        'Answer {{question}} and write the answer to `{{folder}}/NOTES.md`.', '',
      ].join('\n'), { flag: 'wx' }).catch(() => undefined);
    }
    await vscode.window.showTextDocument(vscode.Uri.file(example)).then(undefined, () => vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(dir)));
  });
  command('kitWorkbench.setDefaultWorkerModel', async (arg) => {
    const id = typeof arg === 'string' ? arg : (await pickModel(workbench, 'worker', false, 'Default model for new workers'))?.id;
    if (id) {
      await vscode.workspace.getConfiguration('kitWorkbench').update('defaultWorkerModel', id, vscode.ConfigurationTarget.Global);
      vscode.window.showInformationMessage(`Default worker model: ${id}`);
    }
    return id;
  });
  command('kitWorkbench.archiveRuns', async (arg) => {
    const finished = (await workbench.runs()).filter((r) => r.status !== 'running');
    if (finished.length === 0) {
      vscode.window.showInformationMessage('No finished runs to archive.');
      return [];
    }
    if (arg !== 'confirmed') {
      const ok = await vscode.window.showInformationMessage(
        `Move ${finished.length} finished runs to ${workbench.stateDir}/archive? Nothing is deleted.`, 'Archive');
      if (ok !== 'Archive') {
        return [];
      }
    }
    return workbench.archive();
  });
  command('kitWorkbench.archiveRun', async (arg) => {
    const run = await pickRun(workbench, arg, (r) => r.status !== 'running');
    return run ? workbench.archive([run.id]) : [];
  });
  command('kitWorkbench.refreshStatus', () => statusView.refresh());
  command('kitWorkbench.sendSelectionToOrchestrator', () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.selection.isEmpty) {
      vscode.window.showWarningMessage('Select text in an editor first.');
      return undefined;
    }
    const sel = editor.selection;
    const file = workspaceRelative(workbench, editor.document.uri.fsPath);
    const reference = selectionReference(file, sel.start.line + 1, sel.end.line + 1, editor.document.getText(sel));
    return sendToOrchestrator(workbench, `${reference.split('\n')[0]} `, reference);
  });
  command('kitWorkbench.sendFileToOrchestrator', (arg) => {
    const uri = arg instanceof vscode.Uri ? arg : vscode.window.activeTextEditor?.document.uri;
    if (!uri) {
      vscode.window.showWarningMessage('No file selected.');
      return undefined;
    }
    return sendToOrchestrator(workbench, `${workspaceRelative(workbench, uri.fsPath)} `);
  });
  context.subscriptions.push(vscode.workspace.onDidChangeConfiguration((e) => {
    if (e.affectsConfiguration('kitWorkbench')) {
      statusView.refresh();
    }
  }));

  registerChatParticipant(context, workbench);
  registerLmTools(context, workbench);
  registerBrainMcp(context, workbench);
  await workbench.start();
  await updateBar();
  return { workbench };
}

export function deactivate(): void {
  // Disposables clean up through context.subscriptions.
}
