// Webview panels: the worker overview (grid of run cards) and the result view of one run.
import { readFile } from 'node:fs/promises';
import * as vscode from 'vscode';
import { readIfExists } from './agent/tools.ts';
import { runFiles } from './runs.ts';
import { logPreview, renderOverview, renderResultView, type CardAction } from './viewsHtml.ts';
import type { Workbench } from './workbench.ts';

type FromWebview = { type: 'action'; action: CardAction; runId: string } | { type: 'command'; command: string };

const OVERVIEW_COMMANDS: Record<string, string> = {
  spawn: 'kitWorkbench.spawnWorker',
  template: 'kitWorkbench.spawnFromTemplate',
  orchestrator: 'kitWorkbench.openOrchestratorPanel',
  refresh: 'kitWorkbench.refresh',
  archive: 'kitWorkbench.archiveRuns',
};

export const CARD_COMMANDS: Record<CardAction, string> = {
  show: 'kitWorkbench.showWorker',
  result: 'kitWorkbench.openResult',
  task: 'kitWorkbench.openTask',
  stop: 'kitWorkbench.stopWorker',
  rerun: 'kitWorkbench.rerunWorker',
  archive: 'kitWorkbench.archiveRun',
};

function nonce(): string {
  return [...Array(24)].map(() => Math.floor(Math.random() * 36).toString(36)).join('');
}

function onMessage(message: FromWebview): void {
  if (message.type === 'command' && OVERVIEW_COMMANDS[message.command]) {
    void vscode.commands.executeCommand(OVERVIEW_COMMANDS[message.command]);
  } else if (message.type === 'action' && CARD_COMMANDS[message.action] && typeof message.runId === 'string') {
    void vscode.commands.executeCommand(CARD_COMMANDS[message.action], message.runId);
  }
}

export class OverviewPanel {
  static current: OverviewPanel | undefined;

  static show(workbench: Workbench): OverviewPanel {
    if (OverviewPanel.current) {
      OverviewPanel.current.panel.reveal();
      void OverviewPanel.current.render();
      return OverviewPanel.current;
    }
    const panel = vscode.window.createWebviewPanel('kitWorkbench.overview', 'Workers', vscode.ViewColumn.Active, {
      enableScripts: true,
      retainContextWhenHidden: false,
    });
    OverviewPanel.current = new OverviewPanel(panel, workbench);
    return OverviewPanel.current;
  }

  readonly panel: vscode.WebviewPanel;
  private readonly workbench: Workbench;
  private pending: NodeJS.Timeout | undefined;
  private readonly timer: NodeJS.Timeout;
  /** Last rendered HTML, for tests and to skip identical re-renders. */
  html = '';

  private constructor(panel: vscode.WebviewPanel, workbench: Workbench) {
    this.panel = panel;
    this.workbench = workbench;
    const sub = workbench.onDidChange(() => this.schedule());
    // Relative times and the "quiet" flag change without file events.
    this.timer = setInterval(() => this.schedule(), 30_000);
    panel.onDidDispose(() => {
      sub.dispose();
      clearInterval(this.timer);
      if (this.pending) {
        clearTimeout(this.pending);
      }
      OverviewPanel.current = undefined;
    });
    panel.onDidChangeViewState(() => panel.visible && this.schedule());
    panel.webview.onDidReceiveMessage(onMessage);
    void this.render();
  }

  private schedule(): void {
    if (this.pending) {
      return;
    }
    this.pending = setTimeout(() => {
      this.pending = undefined;
      void this.render();
    }, 300);
  }

  async render(): Promise<string> {
    const [cards, status, templates] = await Promise.all([this.workbench.runCards(), this.workbench.status(), this.workbench.templates()]);
    const html = renderOverview(
      { cards, status, quietMinutes: this.workbench.quietMinutes, templates: templates.length },
      nonce(),
      this.panel.webview.cspSource,
    );
    // The nonce differs every time; compare without it.
    if (html.replace(/nonce-?[a-z0-9"=]*/g, '') !== this.html.replace(/nonce-?[a-z0-9"=]*/g, '')) {
      this.html = html;
      this.panel.webview.html = html;
    }
    return this.html;
  }
}

export class ResultPanel {
  static readonly open = new Map<string, ResultPanel>();

  static async show(workbench: Workbench, runId: string): Promise<ResultPanel> {
    const existing = ResultPanel.open.get(runId);
    if (existing) {
      existing.panel.reveal();
      await existing.render();
      return existing;
    }
    const panel = vscode.window.createWebviewPanel('kitWorkbench.result', 'Result', vscode.ViewColumn.Active, { enableScripts: true });
    const view = new ResultPanel(panel, workbench, runId);
    ResultPanel.open.set(runId, view);
    await view.render();
    return view;
  }

  readonly panel: vscode.WebviewPanel;
  private readonly workbench: Workbench;
  private readonly runId: string;
  html = '';

  private constructor(panel: vscode.WebviewPanel, workbench: Workbench, runId: string) {
    this.panel = panel;
    this.workbench = workbench;
    this.runId = runId;
    const sub = workbench.onDidChange(() => void this.render());
    panel.onDidDispose(() => {
      sub.dispose();
      ResultPanel.open.delete(runId);
    });
    panel.webview.onDidReceiveMessage(onMessage);
  }

  async render(): Promise<string> {
    const meta = (await this.workbench.runs()).find((r) => r.id === this.runId);
    if (!meta) {
      this.panel.webview.html = '<!DOCTYPE html><html><body><p>This run was archived or removed.</p></body></html>';
      return '';
    }
    const files = runFiles(this.workbench.stateDir, meta.id);
    const log = await readIfExists(files.log, 2_000_000);
    const html = renderResultView(
      {
        meta,
        result: await readIfExists(files.result),
        task: await readFile(files.task, 'utf8').catch(() => undefined),
        log: log ? logPreview(log) : undefined,
      },
      nonce(),
      this.panel.webview.cspSource,
    );
    this.panel.title = `Result: ${meta.name}`;
    if (html.replace(/nonce-?[a-z0-9"=]*/g, '') !== this.html.replace(/nonce-?[a-z0-9"=]*/g, '')) {
      this.html = html;
      this.panel.webview.html = html;
    }
    return this.html;
  }
}
