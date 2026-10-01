// Orchestrator panel: a small chat webview for API and VS Code models, no Copilot Chat needed.
import * as vscode from 'vscode';
import type { ChatMessage } from './agent/loop.ts';
import { escapeHtml } from './format.ts';
import type { Workbench } from './workbench.ts';

type FromWebview = { type: 'send'; text: string; model: string } | { type: 'stop' } | { type: 'reset' } | { type: 'ready' };

export class OrchestratorPanel {
  private static current: OrchestratorPanel | undefined;
  private history: ChatMessage[] = [];
  private abort: AbortController | undefined;
  private ready = false;
  /** Text waiting for the input box ("Send to Orchestrator" before the webview loaded). */
  private readonly inserts: string[] = [];

  static show(workbench: Workbench): OrchestratorPanel {
    if (OrchestratorPanel.current) {
      OrchestratorPanel.current.panel.reveal();
      return OrchestratorPanel.current;
    }
    const panel = vscode.window.createWebviewPanel('kitWorkbench.orchestrator', 'Orchestrator', vscode.ViewColumn.Active, {
      enableScripts: true,
      retainContextWhenHidden: true,
    });
    OrchestratorPanel.current = new OrchestratorPanel(panel, workbench);
    return OrchestratorPanel.current;
  }

  /** Appends text to the input box without sending it; the human reviews and sends. */
  insert(text: string): void {
    this.inserts.push(text);
    this.flush();
  }

  private flush(): void {
    while (this.ready && this.inserts.length > 0) {
      void this.panel.webview.postMessage({ kind: 'insert', text: this.inserts.shift() });
    }
  }

  private readonly panel: vscode.WebviewPanel;
  private readonly workbench: Workbench;

  private constructor(panel: vscode.WebviewPanel, workbench: Workbench) {
    this.panel = panel;
    this.workbench = workbench;
    panel.onDidDispose(() => {
      this.abort?.abort();
      OrchestratorPanel.current = undefined;
    });
    panel.webview.onDidReceiveMessage((m: FromWebview) => void this.onMessage(m));
    void this.render();
  }

  private post(kind: 'user' | 'assistant' | 'tool' | 'error' | 'status', text: string): void {
    void this.panel.webview.postMessage({ kind, text });
  }

  private async render(): Promise<void> {
    const models = (await this.workbench.modelsFor('orchestrator'))
      .filter((m) => m.harness === 'vscode-lm' || m.harness === 'api' || m.source === 'vscode-lm');
    const registry = await this.workbench.registry();
    const apiModels = models.filter((m) => registry.harnesses.find((h) => h.id === m.harness)?.runner !== 'terminal');
    const options = apiModels.map((m) => `<option value="${escapeHtml(m.id)}">${escapeHtml(m.label)}</option>`).join('');
    const nonce = [...Array(16)].map(() => Math.floor(Math.random() * 36).toString(36)).join('');
    this.panel.webview.html = `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); margin: 0; padding: 12px; }
  #log { display: flex; flex-direction: column; gap: 8px; margin-bottom: 12px; }
  .m { white-space: pre-wrap; padding: 8px 10px; border-radius: 4px; line-height: 1.45; }
  .user { background: var(--vscode-editor-inactiveSelectionBackground); }
  .assistant { border-left: 2px solid var(--vscode-focusBorder); }
  .tool, .status { color: var(--vscode-descriptionForeground); font-size: 0.9em; }
  .error { color: var(--vscode-errorForeground); }
  form { display: flex; flex-direction: column; gap: 6px; }
  textarea { font: inherit; min-height: 70px; color: var(--vscode-input-foreground); background: var(--vscode-input-background); border: 1px solid var(--vscode-input-border, transparent); padding: 6px; }
  .row { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; }
  select, button { font: inherit; }
  button { color: var(--vscode-button-foreground); background: var(--vscode-button-background); border: 0; padding: 4px 12px; cursor: pointer; }
  button.secondary { color: var(--vscode-button-secondaryForeground); background: var(--vscode-button-secondaryBackground); }
</style></head>
<body>
<div id="log">${apiModels.length === 0 ? '<div class="m error">No API or VS Code language model available. Install a chat model provider (e.g. GitHub Copilot), add an API model to the registry, or run "Kit Workbench: Discover Local Models".</div>' : ''}</div>
<form id="f">
  <textarea id="t" placeholder="Describe the goal. The orchestrator plans and delegates to workers."></textarea>
  <div class="row">
    <select id="model">${options}</select>
    <button type="submit">Send</button>
    <button type="button" class="secondary" id="stop">Stop</button>
    <button type="button" class="secondary" id="reset">New conversation</button>
  </div>
</form>
<script nonce="${nonce}">
  const vscode = acquireVsCodeApi();
  const log = document.getElementById('log');
  const t = document.getElementById('t');
  function add(kind, text) { const d = document.createElement('div'); d.className = 'm ' + kind; d.textContent = text; log.appendChild(d); d.scrollIntoView(); }
  document.getElementById('f').addEventListener('submit', (e) => { e.preventDefault(); const text = t.value.trim(); if (!text) return; vscode.postMessage({ type: 'send', text, model: document.getElementById('model').value }); t.value = ''; });
  document.getElementById('stop').addEventListener('click', () => vscode.postMessage({ type: 'stop' }));
  document.getElementById('reset').addEventListener('click', () => { log.textContent = ''; vscode.postMessage({ type: 'reset' }); });
  window.addEventListener('message', (e) => {
    if (e.data.kind === 'insert') { t.value = t.value ? t.value.replace(/\s*$/, '\n') + e.data.text : e.data.text; t.focus(); return; }
    add(e.data.kind, e.data.text);
  });
  vscode.postMessage({ type: 'ready' });
</script>
</body></html>`;
  }

  private async onMessage(message: FromWebview): Promise<void> {
    if (message.type === 'ready') {
      this.ready = true;
      this.flush();
      return;
    }
    if (message.type === 'stop') {
      this.abort?.abort();
      return;
    }
    if (message.type === 'reset') {
      this.abort?.abort();
      this.history = [];
      return;
    }
    if (this.abort) {
      this.post('status', 'Still working on the previous message; press Stop first.');
      return;
    }
    this.post('user', message.text);
    this.abort = new AbortController();
    try {
      const registry = await this.workbench.registry();
      const model = registry.models.find((m) => m.id === message.model);
      if (!model) {
        throw new Error('Choose a model first.');
      }
      await this.workbench.confirmCloud(registry, model);
      const backend = await this.workbench.backendFor(registry, model);
      this.history.push({ role: 'user', content: message.text });
      this.history = await this.workbench.orchestratorTurn(backend, this.history, 'panel', this.abort.signal, (event) => {
        if (event.type === 'text') {
          this.post('assistant', event.text);
        } else if (event.type === 'tool-call') {
          this.post('tool', `${event.call.name} ${JSON.stringify(event.call.input).slice(0, 300)}`);
        }
      });
    } catch (error) {
      this.post('error', (error as Error).message);
    } finally {
      this.abort = undefined;
    }
  }
}
