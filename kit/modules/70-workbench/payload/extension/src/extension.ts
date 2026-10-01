import { basename, relative } from 'node:path';
import * as vscode from 'vscode';
import { HomePanel, type OpenTarget } from './homeView.ts';
import {
  isMachine,
  host2RemoteUri,
  type Machine,
  MACHINE_LABEL,
  MACHINE_STATE_KEY,
  MACHINES,
} from './machine.ts';
import {
  type CommandSink,
  type CommandTarget,
  commandsDir,
  drainCommands,
  ensureCommandsDir,
} from './commandFile.ts';
import { decidePending, type PendingAction } from './pending.ts';
import { listRemoteDirs } from './remoteState.ts';
import { nextSessionKey } from './sessionKey.ts';
import {
  DEFAULT_SETTINGS,
  expandHome,
  readSettings,
  type Settings,
  workbenchDir,
  type WorkerLayout,
} from './settings.ts';
import { extensionActor } from './settingsLog.ts';
import { SettingsPanel } from './settingsView.ts';
import { nextSessionName, readAllStates, readState, sessionDisplayName } from './state.ts';
import {
  type LaunchOptions,
  launchFailureMessage,
  launchOutcome,
  openPlan,
  orchestratorAttachCommand,
  orchestratorCommand,
  orchestratorLiveness,
  type RestoreCandidate,
  restoreCandidates,
  restorePlan,
  RETRY_LAUNCH_LABEL,
  shellState,
  type ShellState,
  terminalPlan,
  workerViewCommand,
} from './terminal.ts';
import { confirmMessage, DELETE_LABEL, runDelete } from './sessionDelete.ts';
import {
  clearOrphanMarkers,
  ORPHAN_GRACE_SECONDS,
  orphanWatchCommand,
  shouldArmOrphanWatch,
  spawnOrphanWatcher,
  writeOrphanMarker,
} from './sessionClose.ts';
import {
  findOrchestratorPane,
  focusPane,
  hasSession,
  killViewSession,
  listWorkerTabWindows,
  sendText,
  sessionName,
  sessionStatus,
  viewSessionName,
} from './tmux.ts';
import { resolveUriAction } from './uriHandler.ts';
import { appendUriReceipt } from './uriReceiptLog.ts';
import {
  type ExistingWorkerTab,
  hintMessage,
  OPEN_TAB_LABEL,
  overflowWorkerTerminalName,
  planReopen,
  regrid,
  type ReopenThrottle,
  resolveWorkerTabState,
  shouldHintWorkerTab,
  syncLayout,
  syncOverflowWorkerTabs,
  workerTabAction,
} from './workerTab.ts';
import { WorkersProvider } from './workersView.ts';

const PENDING_KEY = 'claudeWorkbench.pendingAction';
/** Which session of the open folder this window is showing (SPEC-V2 B). */
const SESSION_KEY_STATE = 'claudeWorkbench.sessionKey';
const TERMINAL_NAME = 'Agent Workbench';
const WORKER_TERMINAL_NAME = 'Agent Workbench — Worker';

/**
 * The terminals this extension host created. A terminal VSCode restored from a
 * previous window session is not in here — it only looks like ours.
 */
const ownTerminals = new Set<vscode.Terminal>();

/**
 * Which tmux session each of our terminals was launched for. Without this the
 * extension could only ask "is this tab alive", never "is it alive on the RIGHT
 * session" — and a live tab on the wrong session is exactly how a newly named
 * session silently turned into the old one (part B, 2026-08-04).
 */
const terminalSessions = new WeakMap<vscode.Terminal, string>();

/**
 * Terminals for OVERFLOW worker tabs (workers-2, workers-3, ... — 2026-08-04,
 * once wb-grid opens more than one worker-tab window). Keyed by tmux window
 * name. The PRIMARY tab keeps its own single terminal found by name
 * (WORKER_TERMINAL_NAME below) — see syncOverflowWorkerTabs's doc comment in
 * workerTab.ts for why the two are governed differently.
 */
const overflowTerminals = new Map<string, vscode.Terminal>();

/**
 * Self-heal throttle state (2026-08-04, planReopen in workerTab.ts): one burst
 * for the primary tab, one per overflow window name — a person closing
 * 'workers-2' repeatedly must not spend the budget 'workers-3' still has.
 */
let primaryReopenThrottle: ReopenThrottle | undefined;
const overflowReopenThrottle = new Map<string, ReopenThrottle>();

/** Last known layout and when the missing-tab hint was last shown. */
let workerLayout: WorkerLayout = DEFAULT_SETTINGS.workerLayout;
let lastTabHintAt: number | undefined;

/** Log of what the extension did — the only trace a dropped command leaves. */
let output: vscode.OutputChannel | undefined;

/**
 * What `deactivate()` needs to know, kept at module level because it gets no
 * ExtensionContext of its own: which tmux session this window shows, and whether
 * closing the window may take it down (see sessionClose.ts for the measurement
 * that separates a close from a reload).
 */
let armedSession: string | undefined;
let armedFolder: string | undefined;
let armedSessionKey: string | undefined;
let closeSessionOnWindowClose = DEFAULT_SETTINGS.closeSessionOnWindowClose;

/** Remembers which session this window would take down when it closes. */
function armSession(session: string, folder: string | undefined, sessionKey: string | undefined): void {
  armedSession = session;
  armedFolder = folder;
  armedSessionKey = sessionKey;
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  // FIRST, before anything may throw or await: disarm the watcher a previous
  // extension host of THIS window started. A reload deactivates the extension
  // exactly like a close does, and the marker is the only thing telling the two
  // apart — measured gap between the two activations: 547-592 ms, far inside the
  // watcher's grace period (sessionClose.ts).
  const startupFolder = vscode.workspace.workspaceFolders?.[0]?.uri.path;
  const startupKey = context.workspaceState.get<string>(SESSION_KEY_STATE);
  const disarmed = clearOrphanMarkers(startupFolder, startupKey);

  const workers = new WorkersProvider(context.workspaceState.get<string>(SESSION_KEY_STATE));
  const settings = await readSettings();
  closeSessionOnWindowClose = settings.closeSessionOnWindowClose;
  if (disarmed.length > 0) {
    log(`Fenster ist zurückgekommen — Verwaist-Marke entfernt für: ${disarmed.join(', ')}.`);
  }
  workers.setPollSeconds(settings.workerPollSeconds);
  workerLayout = settings.workerLayout;
  // Settings take effect immediately, without restarting the extension and
  // without waiting for the next session start — a layout switch moves the panes
  // and opens or closes the worker tab right away (SPEC-V2 C).
  // Every settings write of this window is traceable in the change log with the
  // window it came from — the shell side logs its writes the same way.
  SettingsPanel.actor = extensionActor(
    context.workspaceState.get<string>(SESSION_KEY_STATE),
    vscode.workspace.workspaceFolders?.[0]?.uri.path,
  );
  SettingsPanel.onLogError = log;
  SettingsPanel.onChanged = (changed: Settings) => {
    workers.setPollSeconds(changed.workerPollSeconds);
    closeSessionOnWindowClose = changed.closeSessionOnWindowClose;
    void applyWorkerLayout(context, changed.workerLayout);
  };
  // Every refresh of the sidebar also answers: can alice SEE these workers?
  // Only LIVE ones count — a stale entry of a finished worker is nothing to
  // chase a tab for.
  //
  // Self-heal runs FIRST and is awaited before the hint check (2026-08-04):
  // applyWorkerTabAutoHeal puts a missing tab straight back without asking, so
  // by the time checkWorkerTabVisible looks, a tab it just healed already
  // reads as 'live' and the hint stays quiet. The hint only fires for what
  // self-heal could not fix itself — a real missing tool, or the reopen
  // throttle having kicked in — which is exactly the fallback it was built
  // for, not a second notification for the same event.
  workers.onWorkers = (list) => {
    void (async () => {
      await applyWorkerTabAutoHeal(context);
      void checkWorkerTabVisible(context, list.filter((w) => w.status === 'running').length);
    })();
  };
  context.subscriptions.push(
    workers,
    vscode.window.onDidCloseTerminal((terminal) => forgetTerminal(terminal)),
    vscode.window.registerTreeDataProvider('claude-workbench.workers', workers),
    vscode.commands.registerCommand('claude-workbench.start', () => openHome(context)),
    vscode.commands.registerCommand('claude-workbench.newSession', () => newSession(context)),
    vscode.commands.registerCommand('claude-workbench.settings', () => SettingsPanel.show(context)),
    vscode.commands.registerCommand('claude-workbench.openWorkerTab', () => openWorkerTab(context)),
    vscode.commands.registerCommand('claude-workbench.refreshWorkers', () => workers.refresh()),
    vscode.commands.registerCommand('claude-workbench.focusWorker', focusWorker),
    vscode.commands.registerCommand(
      'claude-workbench.sendPathToOrchestrator',
      (uri?: vscode.Uri) => sendPath(context, uri),
    ),
    vscode.commands.registerCommand(
      'claude-workbench.sendSelectionToOrchestrator',
      () => sendSelection(context),
    ),
    // vscode://agent-workbench.claude-workbench/<worker-tab|reload> — reaches a window
    // that is neither visible nor clickable (2026-08-04, wb-window). Every
    // path resolution goes through resolveUriAction; see uriHandler.ts for
    // why that function accepts nothing beyond those two fixed strings.
    vscode.window.registerUriHandler({ handleUri: handleWorkbenchUri }),
  );

  // Reachable from outside BEFORE anything else can fail: a dropped command file
  // is the orchestrator's only way into this running window.
  await startCommandWatcher(context, workers);
  // …and a layout switch in ANY window must reach this one (settings.json is global).
  startSettingsWatcher(context, workers);

  // Design C: this extension is extensionKind "ui", so it runs in the LOCAL
  // (Mac) extension host even inside a Remote-SSH (host2) window. globalState is
  // therefore the SAME store before and after the openFolder reload for both
  // machines, so the launch handover is a single globalState action for all —
  // no file-based handover on host2 is needed. Match on uri.path so a remote
  // workspace folder (vscode-remote://…/home/alice/…) matches the host2 path
  // stored in the pending action (on POSIX .path == .fsPath for local folders).
  const folder = vscode.workspace.workspaceFolders?.[0]?.uri.path;
  const pending = context.globalState.get<PendingAction>(PENDING_KEY);
  let handledPending = false;
  switch (decidePending(pending, folder, Date.now())) {
    case 'consume':
      await context.globalState.update(PENDING_KEY, undefined);
      await context.workspaceState.update(SESSION_KEY_STATE, pending!.sessionKey);
      workers.setSessionKey(pending!.sessionKey);
      SettingsPanel.actor = extensionActor(pending!.sessionKey, folder);
      await startOrchestratorTerminal(folder!, {
        sessionId: pending!.sessionId,
        name: pending!.name,
        sessionKey: pending!.sessionKey,
      });
      workers.refresh();
      handledPending = true;
      break;
    case 'expire':
      await context.globalState.update(PENDING_KEY, undefined);
      vscode.window.showWarningMessage(
        `The session in "${pending!.dir}" did not start — please try again.`,
      );
      break;
    case 'keep':
      // belongs to another window of this profile — do not touch it
      break;
  }
  await restoreTerminals(context, folder, handledPending, settings.workerLayout, workers);
  // Kit (F43): no start page by itself in a window without a folder; the command
  // "Agent Workbench: Open start page" and the activity bar open it when the user asks.
}

/**
 * After a window reload — which installing a new build requires — the window
 * must not sit there without its terminals. If this window has a folder whose
 * tmux session is still alive, the tabs are re-created: the orchestrator tab
 * ATTACHES to the running session (never wb-code, so no second Claude can
 * start), and with workerLayout "window" the worker tab comes back with it.
 * A dead session restores nothing.
 *
 * Every run says what it decided and on which grounds, even — especially — the
 * run that restores nothing (2026-08-04). This path used to return without a
 * word whenever one of its three conditions was false, so a window that came up
 * empty in front of six running workers left no trace at all of WHY, and
 * finding out cost half an hour of log reading. The line below names all three
 * values and every session it probed; it is meant to stay.
 */
async function restoreTerminals(
  context: vscode.ExtensionContext,
  folder: string | undefined,
  handledPending: boolean,
  layout: WorkerLayout,
  workers: WorkersProvider,
): Promise<void> {
  const storedKey = context.workspaceState.get<string>(SESSION_KEY_STATE);
  const candidates = folder
    ? restoreCandidates(folder, storedKey, await readAllStates(), sessionName)
    : [];
  const probed: string[] = [];
  let live: RestoreCandidate | undefined;
  for (const candidate of candidates) {
    const status = await sessionStatus(candidate.session);
    probed.push(`${candidate.session}=${status}`);
    if (status === 'alive') {
      live = candidate;
      break;
    }
  }
  const plan = restorePlan({
    hasFolder: folder !== undefined,
    sessionAlive: live !== undefined,
    handledPending,
    layout,
  });
  log(
    `Terminal-Wiederherstellung: hasFolder=${folder !== undefined} (${folder ?? '-'}), ` +
      `sessionAlive=${live !== undefined}, handledPending=${handledPending}, ` +
      `Schlüssel=${storedKey ?? '(Standard)'}, geprüft: ${probed.join(' ') || '(keine)'}.`,
  );
  if (!plan.orchestrator) {
    log('Keine Terminals wiederhergestellt — siehe die Werte in der Zeile darüber.');
    return;
  }
  // The window follows the session it actually found: a key whose session has
  // ended must not keep pointing the worker sidebar and the settings log at a
  // session that is gone.
  if (live!.sessionKey !== storedKey) {
    await context.workspaceState.update(SESSION_KEY_STATE, live!.sessionKey);
    workers.setSessionKey(live!.sessionKey);
    SettingsPanel.actor = extensionActor(live!.sessionKey, folder);
    log(
      `Session-Schlüssel gewechselt: ${storedKey ?? '(Standard)'} lebt nicht mehr, ` +
        `dieses Fenster übernimmt ${live!.sessionKey ?? '(Standard)'}.`,
    );
  }
  armSession(live!.session, folder, live!.sessionKey);
  await attachOrchestratorTerminal(live!.session);
  if (plan.workerTab) {
    await showWorkerTerminal(folder!, live!.sessionKey);
  }
  log(
    `Terminals wiederhergestellt (tmux-Session ${live!.session}` +
      `${plan.workerTab ? ', inkl. Worker-Tab' : ''}).`,
  );
}

/** Re-attaches the orchestrator tab; a ghost terminal from the reload is replaced. */
async function attachOrchestratorTerminal(session: string): Promise<void> {
  const existing = vscode.window.terminals.find((t) => t.name === TERMINAL_NAME);
  const createdByUs = existing !== undefined && ownTerminals.has(existing);
  const plan = terminalPlan(
    existing && {
      createdByUs,
      exited: existing.exitStatus !== undefined,
      liveness: createdByUs ? await orchestratorLiveness(await existing.processId) : 'unknown',
      attachedTo: existing ? terminalSessions.get(existing) : undefined,
    },
    session,
  );
  if (plan === 'show') {
    existing!.show(true);
    return;
  }
  // A terminal VSCode restored across the reload carries the name but a dead
  // shell — it must go, otherwise two tabs claim to be the orchestrator.
  existing?.dispose();
  const cwd = vscode.workspace.workspaceFolders?.[0]?.uri;
  const terminal = vscode.window.createTerminal({
    name: TERMINAL_NAME,
    cwd,
    location: vscode.TerminalLocation.Panel,
  });
  ownTerminals.add(terminal);
  terminalSessions.set(terminal, session);
  terminal.sendText(orchestratorAttachCommand(session));
  terminal.show(true);
  void verifyTab(terminal, TERMINAL_NAME, session, orchestratorAttachCommand(session));
}

/** How long a start gets to arrive before it is re-sent. */
const VERIFY_TIMEOUT_MS = 25000;
const VERIFY_POLL_MS = 1000;

/**
 * Did this tab really end up at its session — and if not, say so (part A).
 *
 * The measured failure it exists for: a '^C' reached the orchestrator tab before
 * the shell had finished running the profile, the typed `wb-code …` line was
 * discarded, and the tab sat at a bare prompt while the tmux session ran on
 * unseen. Nothing noticed, so alice saw only the worker tab and had to work
 * out for himself what had happened.
 *
 * The command is re-sent ONCE (`launchOutcome`), because the overwhelmingly
 * likely cause is a swallowed line and both commands are idempotent — wb-code
 * attaches to an existing session instead of starting a second Claude, and an
 * attach is an attach. If the second attempt does not arrive either, the tab
 * stays as it is and a warning with a retry button appears. Never a third silent
 * attempt: at that point something is wrong that typing again will not fix.
 *
 * Remote (host2) windows are exempt. The extension host runs on the Mac
 * (extensionKind "ui") while that tmux server runs on host2, so `hasSession`
 * would answer about the wrong machine — and a wrong "not there" would re-send
 * commands into a healthy session.
 */
async function verifyTab(
  terminal: vscode.Terminal,
  label: string,
  session: string,
  command: string,
  requireSession = true,
): Promise<void> {
  if (isRemoteWindow()) {
    return;
  }
  const pid = await terminal.processId;
  for (let attempt = 1; ; attempt++) {
    const check = await waitForTab(pid, requireSession ? session : undefined);
    const outcome = launchOutcome({ ...check, attempt });
    if (outcome === 'ok') {
      log(`${label}: haengt an ${session}.`);
      return;
    }
    if (terminal.exitStatus !== undefined || !ownTerminals.has(terminal)) {
      return; // the tab is gone — nothing left to fix
    }
    if (outcome === 'retry') {
      log(`${label}: kam nicht an ${session} an — Befehl wird einmal wiederholt.`);
      terminal.sendText(command);
      continue;
    }
    log(`${label}: haengt nach zwei Versuchen nicht an ${session}.`);
    const choice = await vscode.window.showWarningMessage(
      launchFailureMessage(label, session),
      RETRY_LAUNCH_LABEL,
    );
    if (choice === RETRY_LAUNCH_LABEL && terminal.exitStatus === undefined) {
      terminal.sendText(command);
    }
    return;
  }
}

/**
 * Polls until the tab is provably attached, or the deadline passes.
 *
 * `session` undefined means: do not judge WHICH session it landed on, only that
 * it landed. That is the worker tab's case — `wb-worker-tab` may deliberately
 * attach to another session of the same folder when the stored name has died,
 * and calling that healthy tab broken would be a false alarm about the one
 * fallback that exists to prevent the original failure.
 */
async function waitForTab(
  pid: number | undefined,
  session: string | undefined,
): Promise<{ sessionAlive: boolean; shell: ShellState }> {
  const deadline = Date.now() + VERIFY_TIMEOUT_MS;
  let last: { sessionAlive: boolean; shell: ShellState } = { sessionAlive: false, shell: 'unknown' };
  for (;;) {
    last = {
      sessionAlive: session === undefined ? true : await hasSession(session),
      shell: await shellState(pid),
    };
    if (last.sessionAlive && last.shell === 'attached') {
      return last;
    }
    if (Date.now() >= deadline) {
      return last;
    }
    await delay(VERIFY_POLL_MS);
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** A Remote-SSH window: its tmux server is on the other machine, not here. */
function isRemoteWindow(): boolean {
  return vscode.workspace.workspaceFolders?.[0]?.uri.scheme === 'vscode-remote';
}

/**
 * The drop directory (~/.claude/workbench/commands/) is watched AND polled: the
 * watcher reacts instantly, the poll guarantees delivery even where file
 * watching outside the workspace is unreliable.
 */
const COMMAND_POLL_MS = 3000;

async function startCommandWatcher(
  context: vscode.ExtensionContext,
  workers: WorkersProvider,
): Promise<void> {
  const dir = commandsDir();
  await ensureCommandsDir(dir);
  const sink: CommandSink = {
    run: async (command) => {
      switch (command) {
        case 'open-worker-tab':
          await vscode.commands.executeCommand('claude-workbench.openWorkerTab');
          break;
        case 'focus-orchestrator':
          vscode.window.terminals.find((t) => t.name === TERMINAL_NAME)?.show(true);
          break;
        case 'refresh-workers':
          workers.refresh();
          break;
      }
    },
    log,
  };
  // The drop directory is global and every window polls it, so a command may
  // name the window it is meant for (folder + optional sessionKey).
  const drain = () => void drainCommands(dir, sink, { window: windowTarget(context) });
  const watcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(vscode.Uri.file(dir), '*'),
  );
  const timer = setInterval(drain, COMMAND_POLL_MS);
  context.subscriptions.push(
    watcher,
    watcher.onDidCreate(drain),
    watcher.onDidChange(drain),
    { dispose: () => clearInterval(timer) },
  );
  log(`Kommando-Verzeichnis wird beobachtet: ${dir}`);
  drain();
}

/** Identity of this window for addressed command files (SPEC-V2 B). */
function windowTarget(context: vscode.ExtensionContext): CommandTarget {
  return {
    dir: vscode.workspace.workspaceFolders?.[0]?.uri.path,
    sessionKey: context.workspaceState.get<string>(SESSION_KEY_STATE),
  };
}

/**
 * settings.json is shared by every window, so a layout switch made ANYWHERE has
 * to reach this window too: re-read the file, and apply a changed layout exactly
 * as if this window had made the change (own session re-tiled, tab opened or
 * closed, visibility hint as usual). Watched and polled, like the command
 * directory — an unnoticed layout switch is what made four workers invisible.
 */
function startSettingsWatcher(context: vscode.ExtensionContext, workers: WorkersProvider): void {
  const check = async () => {
    const current = await readSettings();
    workers.setPollSeconds(current.workerPollSeconds);
    closeSessionOnWindowClose = current.closeSessionOnWindowClose;
    const { apply } = syncLayout(workerLayout, current.workerLayout);
    if (apply) {
      log(`Layout-Wechsel aus einem anderen Fenster übernommen: ${current.workerLayout}`);
      await applyWorkerLayout(context, current.workerLayout);
    }
  };
  const run = () => void check();
  const watcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(vscode.Uri.file(workbenchDir()), 'settings.json'),
  );
  const timer = setInterval(run, SETTINGS_POLL_MS);
  context.subscriptions.push(
    watcher,
    watcher.onDidCreate(run),
    watcher.onDidChange(run),
    { dispose: () => clearInterval(timer) },
  );
}

const SETTINGS_POLL_MS = 5000;

function log(message: string): void {
  output ??= vscode.window.createOutputChannel('Agent Workbench');
  output.appendLine(`[${new Date().toISOString()}] ${message}`);
}

/**
 * Fires for BOTH a closing and a reloading window — VS Code has no
 * onWillCloseWindow, and the measurement in sessionClose.ts shows deactivate()
 * looks identical in the two cases. So nothing is killed here. The window leaves
 * behind "verwaist seit <zeit>" and a detached watcher that waits out the grace
 * period; a reload comes back within about half a second and removes the marker
 * long before the watcher looks at it.
 *
 * Everything below is synchronous on purpose: deactivate() runs on a shutdown
 * budget, and a write that never lands would leave the session orphaned with
 * nothing left to clean it up.
 */
export function deactivate(): void {
  if (!shouldArmOrphanWatch({
    enabled: closeSessionOnWindowClose,
    session: armedSession,
    remote: isRemoteWindow(),
  })) {
    return;
  }
  const token = `${process.pid}-${Date.now()}`;
  try {
    writeOrphanMarker({
      session: armedSession!,
      folder: armedFolder ?? '',
      sessionKey: armedSessionKey,
      token,
      at: Date.now(),
    });
    spawnOrphanWatcher(orphanWatchCommand(armedSession!, token, ORPHAN_GRACE_SECONDS));
  } catch {
    // A window that is already going away cannot report anything — and a failed
    // cleanup must never become a failed shutdown. wb-session-sweep stays the
    // backstop for exactly this case.
  }
}

function currentMachine(context: vscode.ExtensionContext): Machine {
  const stored = context.globalState.get(MACHINE_STATE_KEY);
  return isMachine(stored) ? stored : 'mac';
}

/** Native QuickPick at start-up; the choice is persisted and pre-selected. */
async function chooseMachine(context: vscode.ExtensionContext): Promise<void> {
  // Kit: one machine, nothing to choose.
  if (MACHINES.length < 2) {
    return;
  }
  const current = currentMachine(context);
  const items = MACHINES.map((machine) => ({
    label: MACHINE_LABEL[machine],
    description: machine === current ? 'last chosen' : undefined,
    machine,
  }));
  const pick = await vscode.window.showQuickPick(items, {
    title: 'Agent Workbench — choose a machine',
    placeHolder: `Current: ${MACHINE_LABEL[current]}`,
  });
  if (pick) {
    await context.globalState.update(MACHINE_STATE_KEY, pick.machine);
  }
}

async function openHome(context: vscode.ExtensionContext): Promise<void> {
  await chooseMachine(context);
  await HomePanel.show(context, {
    open: (dir, target, machine) => openSession(context, dir, target, machine),
    pickNew: (machine) => pickNewFolder(context, machine),
    newInFolder: (dir, machine) => startFurtherSession(context, dir, machine),
    remove: (dir, sessionKey, name) => deleteSession(dir, sessionKey, name),
    openSettings: () => SettingsPanel.show(context),
  });
}

/**
 * "Weitere Session" on a folder of the start page (SPEC-V2 B): the folder is
 * already decided by the button, so only the name is asked — pre-filled with the
 * next free one ('AI', 'AI2', 'AI3', …).
 */
async function startFurtherSession(
  context: vscode.ExtensionContext,
  dir: string,
  machine: Machine,
): Promise<void> {
  const name = await askSessionName(dir, await suggestedSessionName(dir, machine === 'host2'));
  if (name === undefined) {
    return;
  }
  const sessionKey = await nextSessionKey(dir, machine === 'host2');
  await openSession(context, dir, { name, sessionKey }, machine);
}

/**
 * Removes a session after ONE explicit, modal confirmation. The deletion itself
 * is `wb-session-delete`'s job — including which paths belong to the session,
 * the snapshot, and the guard that keeps kbase and project files out of it.
 */
async function deleteSession(
  dir: string,
  sessionKey: string | undefined,
  name: string,
): Promise<boolean> {
  const choice = await vscode.window.showWarningMessage(
    confirmMessage(name, dir),
    { modal: true },
    DELETE_LABEL,
  );
  if (choice !== DELETE_LABEL) {
    return false;
  }
  const result = await runDelete(dir, sessionKey);
  log(`wb-session-delete (${name}): ${result.ok ? 'ok' : 'fehlgeschlagen'}\n${result.output}`);
  if (result.ok) {
    vscode.window.setStatusBarMessage(`Session "${name}" deleted (backed up in ~/.local/trash-snapshots/).`, 6000);
    return true;
  }
  // A refusal carries its reason (a window still attached, a worker still
  // running) — showing it is the whole value of not deleting silently.
  vscode.window.showErrorMessage(
    `Session "${name}" was NOT deleted: ${result.output || 'unknown error'}`,
  );
  return false;
}

/** Palette command "Neue Session": uses the currently selected machine. */
async function newSession(context: vscode.ExtensionContext): Promise<void> {
  await pickNewFolder(context, currentMachine(context));
}

/**
 * Folder picker for a new session: local dialog on Mac, remote QuickPick on
 * Host2. Afterwards alice names the session (SPEC-V2 D); a folder that
 * already has a session gets a key for the new one, the first one stays the
 * folder's default session.
 */
async function pickNewFolder(context: vscode.ExtensionContext, machine: Machine): Promise<void> {
  const dir = machine === 'host2' ? await pickRemoteFolder() : await pickLocalFolder();
  if (!dir) {
    return;
  }
  const name = await askSessionName(dir, await suggestedSessionName(dir, machine === 'host2'));
  if (name === undefined) {
    return; // dialog cancelled — no session, no state file
  }
  const sessionKey = await nextSessionKey(dir, machine === 'host2');
  await openSession(context, dir, { name, sessionKey }, machine);
}

/**
 * Name proposed for the next session of a folder: 'AI', then 'AI2', 'AI3', …
 * (SPEC-V2 B, part B of the 2026-08-04 repair — the rule and its reasoning live
 * in `nextSessionName`). Remote folders fall back to the plain folder name: the
 * names over there would have to come across SSH, and a slightly worse
 * suggestion is not worth a round trip that can hang.
 */
async function suggestedSessionName(dir: string, remote: boolean): Promise<string> {
  if (remote) {
    return basename(dir);
  }
  const states = await readAllStates();
  const names = states
    .filter((state) => state.dir === dir)
    .map((state) => sessionDisplayName(state));
  return nextSessionName(dir, names);
}

/** Empty input means "no name" — the Startseite then shows basename(dir). */
async function askSessionName(dir: string, suggestion: string): Promise<string | undefined> {
  const name = await vscode.window.showInputBox({
    title: 'New session — name',
    prompt: 'Name of this session (shown on the start page and in the agent)',
    value: suggestion,
    placeHolder: suggestion,
  });
  return name === undefined ? undefined : name.trim();
}

async function pickLocalFolder(): Promise<string | undefined> {
  const settings = await readSettings();
  const picked = await vscode.window.showOpenDialog({
    canSelectFolders: true,
    canSelectFiles: false,
    canSelectMany: false,
    defaultUri: vscode.Uri.file(expandHome(settings.newSessionDefaultDir)),
    openLabel: 'Start the session here',
    title: 'New session — choose a project folder',
  });
  return picked?.[0]?.fsPath;
}

/** No native dialog on the Mac would reach host2, so offer its ~/AI folders over SSH. */
async function pickRemoteFolder(): Promise<string | undefined> {
  let dirs: string[];
  try {
    dirs = await listRemoteDirs();
  } catch (error) {
    vscode.window.showWarningMessage(`The second machine cannot be reached over SSH: ${error}`);
    return undefined;
  }
  const custom = { label: 'Enter a path …', dir: undefined as string | undefined };
  const items = [
    ...dirs.map((dir) => ({ label: basename(dir), description: dir, dir })),
    custom,
  ];
  const pick = await vscode.window.showQuickPick(items, {
    title: 'New session on the second machine — choose a project folder',
    placeHolder: 'folders on the second machine',
  });
  if (!pick) {
    return undefined;
  }
  if (pick.dir) {
    return pick.dir;
  }
  return vscode.window.showInputBox({
    title: 'Path on the second machine',
    prompt: 'Absolute path on the second machine',
    value: '/home/alice/AI/',
  });
}

/**
 * Opens the folder in this window. That reloads the window (and, for a UI
 * extension, re-activates it in the same local host), so the terminal launch is
 * handed to the next activation via globalState. On Host2 the folder is opened
 * fully remote (vscode-remote://ssh-remote+host2<path>): the window becomes a
 * remote window, but the extension stays on the Mac (extensionKind "ui"), so the
 * same globalState handover works. `dir` is the absolute path ON the target
 * machine (host2 path for host2), which is exactly what the remote workspace
 * folder's uri.path reports after the reload.
 */
async function openSession(
  context: vscode.ExtensionContext,
  dir: string,
  target: OpenTarget,
  machine: Machine,
): Promise<void> {
  const current = vscode.workspace.workspaceFolders?.[0]?.uri.path;
  const windowSessionKey = context.workspaceState.get<string>(SESSION_KEY_STATE);
  const plan = openPlan({
    currentFolder: current,
    dir,
    windowSessionKey,
    targetSessionKey: target.sessionKey,
    windowHasLiveSession: await windowSessionAlive(dir, windowSessionKey),
  });
  if (plan === 'same-window') {
    await context.workspaceState.update(SESSION_KEY_STATE, target.sessionKey);
    await startOrchestratorTerminal(dir, target);
    return;
  }
  const action: PendingAction = {
    dir,
    sessionId: target.sessionId,
    name: target.name,
    sessionKey: target.sessionKey,
    machine,
    createdAt: Date.now(),
  };
  await context.globalState.update(PENDING_KEY, action);
  const folderUri = machine === 'host2'
    ? vscode.Uri.from(host2RemoteUri(dir))
    : vscode.Uri.file(dir);
  // A further session of the folder this window already shows gets its OWN
  // window (part B): one window, one session, so both of its tabs name exactly
  // one tmux session and can be checked against it. The new window picks the
  // pending action up on activation; this one is not re-activated and therefore
  // does not race for it.
  await vscode.commands.executeCommand('vscode.openFolder', folderUri, plan === 'new-window');
}

/** Does the session this window is showing still run? */
async function windowSessionAlive(dir: string, sessionKey?: string): Promise<boolean> {
  if (isRemoteWindow()) {
    // The host2 tmux server is not this machine's — asking here would answer
    // about the wrong one. A remote window opens a further session in a new
    // window regardless, which is the safe direction.
    return true;
  }
  const state = await readState(dir, sessionKey);
  return hasSession(state?.tmuxSession ?? sessionName(dir, sessionKey));
}

/**
 * A live workbench terminal is attached to the tmux session — its prompt belongs
 * to the orchestrator, so typing 'wb-code ...' into it would land in the Claude
 * chat; it is only shown. A terminal VSCode restored across the openFolder reload
 * carries the same name but a dead wb-code, so it is disposed and relaunched.
 */
async function startOrchestratorTerminal(dir: string, options: LaunchOptions = {}): Promise<void> {
  const settings = await readSettings();
  // Which tmux session this start is FOR. The state file wins; the computed name
  // is the fallback for a session that has never run (SPEC V1.1, same rule as
  // wb-code), and it is what the verification below checks against.
  const state = await readState(dir, options.sessionKey);
  const session = state?.tmuxSession ?? sessionName(dir, options.sessionKey);
  // From here on this window has a session to answer for when it closes.
  armSession(session, vscode.workspace.workspaceFolders?.[0]?.uri.path ?? dir, options.sessionKey);
  const existing = vscode.window.terminals.find((t) => t.name === TERMINAL_NAME);
  const createdByUs = existing !== undefined && ownTerminals.has(existing);
  const plan = terminalPlan(
    existing && {
      createdByUs,
      exited: existing.exitStatus !== undefined,
      liveness: createdByUs ? await orchestratorLiveness(await existing.processId) : 'unknown',
      attachedTo: existing ? terminalSessions.get(existing) : undefined,
    },
    session,
  );
  if (plan === 'show') {
    existing!.show(true);
    await maximizePanel(settings.terminalStartMaximized);
    return;
  }
  existing?.dispose();
  // Use the workspace folder Uri as cwd so a remote (host2) window opens the
  // terminal on host2; fall back to the plain path for the same-folder case.
  const cwd = vscode.workspace.workspaceFolders?.[0]?.uri ?? dir;
  const terminal = vscode.window.createTerminal({
    name: TERMINAL_NAME,
    cwd,
    location: vscode.TerminalLocation.Panel,
  });
  ownTerminals.add(terminal);
  terminalSessions.set(terminal, session);
  const command = orchestratorCommand(dir, options);
  terminal.sendText(command);
  terminal.show(true);
  await maximizePanel(settings.terminalStartMaximized);
  if (settings.workerLayout === 'window') {
    await showWorkerTerminal(dir, options.sessionKey);
  }
  void verifyTab(terminal, TERMINAL_NAME, session, command);
}

/**
 * Second terminal for workerLayout 'window' (SPEC-V2 C): all workers live in the
 * 'workers' window of the same tmux session, and this terminal attaches to a
 * grouped session so it can show that window while the orchestrator terminal
 * stays on its own. An existing worker terminal of this extension host is only
 * revealed — re-attaching would drop its current window.
 */
async function showWorkerTerminal(dir: string, sessionKey?: string): Promise<void> {
  const state = await readState(dir, sessionKey);
  const session = state?.tmuxSession ?? sessionName(dir, sessionKey);
  const existing = vscode.window.terminals.find((t) => t.name === WORKER_TERMINAL_NAME);
  // Only reveal a worker tab that hangs on THIS session. A live tab of the
  // previous session shows the wrong workers, which is worse than a new tab —
  // re-attaching an existing one would merely drop its current window.
  if (
    existing && ownTerminals.has(existing) && existing.exitStatus === undefined
    && terminalSessions.get(existing) === session
  ) {
    existing.show(false);
    return;
  }
  existing?.dispose();
  const cwd = vscode.workspace.workspaceFolders?.[0]?.uri ?? dir;
  const terminal = vscode.window.createTerminal({
    name: WORKER_TERMINAL_NAME,
    cwd,
    location: vscode.TerminalLocation.Panel,
  });
  ownTerminals.add(terminal);
  terminalSessions.set(terminal, session);
  const command = workerViewCommand(session);
  terminal.sendText(command);
  // Checked: did this tab attach at all. NOT checked: to which session — see
  // waitForTab. A tab sitting at a bare prompt (or in wb-worker-tab's
  // "no session for this folder" shell) is still caught, and that is the failure
  // that matters: four workers ran unseen because nobody noticed an empty tab.
  void verifyTab(terminal, WORKER_TERMINAL_NAME, viewSessionName(session), command, false);
}

/** ownTerminals/terminalSessions/overflowTerminals all forget a terminal the same way. */
function forgetTerminal(terminal: vscode.Terminal): void {
  ownTerminals.delete(terminal);
  for (const [windowName, existing] of overflowTerminals) {
    if (existing === terminal) {
      overflowTerminals.delete(windowName);
      break;
    }
  }
}

/**
 * Self-heals BOTH worker tabs — the primary ('workers') and any overflow
 * window (workers-2, ... — SPEC-V2 C, 2026-08-04) — against tmux's actual
 * state, and is the poll-driven replacement for a dialog nobody is there to
 * answer: "the tab is gone while I'm not there" cannot wait for alice to
 * click a button, it has to happen on its own (task of 2026-08-04, part 1).
 *
 * The two tabs are combined into one function because they share the same
 * session lookup and the same `tmuxWindows` read — splitting them would mean
 * two independent tmux round-trips every poll tick for no benefit, since
 * neither needs the other's result.
 *
 * PRIMARY: reopened whenever workerTabAction says 'open' (tab missing or a
 * ghost) AND the session is actually alive — a dead session must not spawn a
 * tab pointing at nothing, that is what the "workerTabAction only ever
 * returns 'open' while layout is 'window'" contract from the layout-switch
 * path already relies on, extended here with the liveness check the switch
 * path gets for free from `hasSession` never having been asked. No dialog,
 * `show(true)` so the tab becomes visible without stealing focus — alice
 * may be mid-edit when this fires unattended.
 *
 * OVERFLOW: unchanged from the original logic (opens a terminal for a window
 * that newly exists, closes one whose window is gone — see
 * syncOverflowWorkerTabs's own doc comment for why a poll, not an event, is
 * the only thing that can drive this correctly) except that opening now also
 * goes through planReopen, closing the gap the original had: before this
 * task, a closed overflow tab whose tmux window still existed came right
 * back on the very next poll tick, forever — nothing ever throttled it.
 *
 * Both sides go through the SAME planReopen budget-and-window logic (see its
 * doc comment in workerTab.ts for why three attempts inside one minute is the
 * cutoff), but with separate throttle state per tab: closing 'workers-2'
 * repeatedly must not spend the budget the primary tab or 'workers-3' still
 * have.
 *
 * Remote (host2) windows are skipped for the same reason verifyTab/
 * windowSessionAlive skip them: the extension host is always local (extensionKind
 * "ui"), so `tmux list-windows` / `has-session` here would ask the Mac's
 * server about a session that actually lives on host2.
 */
async function applyWorkerTabAutoHeal(context: vscode.ExtensionContext): Promise<void> {
  const dir = vscode.workspace.workspaceFolders?.[0]?.uri.path;
  if (!dir) {
    return;
  }
  const sessionKey = context.workspaceState.get<string>(SESSION_KEY_STATE);
  const state = await readState(dir, sessionKey);
  const session = state?.tmuxSession ?? sessionName(dir, sessionKey);
  const remote = isRemoteWindow();
  // The session this window's worker tab must be attached to, and whether it
  // still exists — remote (host2) windows cannot answer the second half locally
  // (that tmux server is not this machine's), so both are withheld there, same
  // exemption as everywhere else in this file that touches tmux directly.
  const wanted = remote ? undefined : session;
  const wantedAlive = !remote && await hasSession(session);
  const active = workerLayout === 'window' && !remote;
  const sessionAlive = active && wantedAlive;
  // `ok: false` (2026-09-03, Audit "tmux-Aufrufe ohne Frist") means tmux could
  // not be asked at all -- NOT that there are zero overflow windows.
  // `syncOverflowWorkerTabs` below would otherwise read an empty list as
  // "wb-grid folded every overflow window away" and close every open overflow
  // terminal on a single hiccup, exactly the false-empty class of bug that
  // once erased every guard marker at once in freigaben.ts (`alleTmuxPanes`).
  // Skipped, not defaulted to empty: the next sidebar refresh asks again.
  const { windows: tmuxWindows, ok: windowsOk } = sessionAlive
    ? await listWorkerTabWindows(session)
    : { windows: [] as string[], ok: true };
  const now = Date.now();
  const tabState = resolveWorkerTabState(existingWorkerTab(), wanted, wantedAlive);

  if (sessionAlive && workerTabAction(workerLayout, tabState) === 'open') {
    const reopen = planReopen(primaryReopenThrottle, now);
    primaryReopenThrottle = reopen.next;
    if (reopen.reopen) {
      await showWorkerTerminal(dir, sessionKey);
      workerTerminal()?.show(true);
    }
  }

  if (sessionAlive && !windowsOk) {
    log(`applyWorkerTabAutoHeal: tmux list-windows fehlgeschlagen -- Ueberlauf-Tabs von '${session}' bleiben unangetastet.`);
    return;
  }

  const plan = syncOverflowWorkerTabs(workerLayout, tmuxWindows, [...overflowTerminals.keys()]);
  for (const windowName of plan.toClose) {
    overflowTerminals.get(windowName)?.dispose();
    overflowTerminals.delete(windowName);
    // The window itself is gone (wb-grid folded it back) — whatever throttle
    // history it had is moot, and a LATER window reusing the same name (worker
    // count rising again) must start with a clean budget, not the old one.
    overflowReopenThrottle.delete(windowName);
  }
  for (const windowName of plan.toOpen) {
    const reopen = planReopen(overflowReopenThrottle.get(windowName), now);
    overflowReopenThrottle.set(windowName, reopen.next);
    if (reopen.reopen) {
      await openOverflowWorkerTerminal(dir, session, windowName);
    }
  }
}

/** Mirrors showWorkerTerminal for one overflow window; always a fresh terminal — nothing to reveal yet. */
async function openOverflowWorkerTerminal(dir: string, session: string, windowName: string): Promise<void> {
  const name = overflowWorkerTerminalName(WORKER_TERMINAL_NAME, windowName);
  const cwd = vscode.workspace.workspaceFolders?.[0]?.uri ?? dir;
  const terminal = vscode.window.createTerminal({ name, cwd, location: vscode.TerminalLocation.Panel });
  ownTerminals.add(terminal);
  terminalSessions.set(terminal, session);
  overflowTerminals.set(windowName, terminal);
  const command = workerViewCommand(session, windowName);
  terminal.sendText(command);
  void verifyTab(terminal, name, viewSessionName(session), command, false);
}

/**
 * Palette command: opens the worker tab for the session of this window — needed
 * after switching workerLayout to 'window' while a session is already running.
 */
async function openWorkerTab(context: vscode.ExtensionContext): Promise<void> {
  const dir = vscode.workspace.workspaceFolders?.[0]?.uri.path;
  if (!dir) {
    vscode.window.showWarningMessage('No project folder is open.');
    return;
  }
  await showWorkerTerminal(dir, context.workspaceState.get<string>(SESSION_KEY_STATE));
  vscode.window.terminals.find((t) => t.name === WORKER_TERMINAL_NAME)?.show(true);
}

/**
 * Routes a claude-workbench URI (vscode://agent-workbench.claude-workbench/…, 2026-08-04,
 * wb-window) to the one of two fixed commands it may mean — resolveUriAction
 * in uriHandler.ts is the actual gate; by the time 'unknown' reaches here
 * there is nothing left to do but log it, on purpose (see that file for why
 * the enum leaves no room for a third branch that DOES something).
 *
 * Both known actions go through vscode.commands.executeCommand rather than
 * calling their implementations directly, so a URI takes exactly the same
 * path the command palette or a keybinding would take — no separate, less
 * exercised route for the one entry point reachable from outside VS Code.
 *
 * The appendUriReceipt call below is the only place this window admits it
 * handled the URI at all (2026-08-04, uriReceiptLog.ts) — without it there
 * was no way from outside to tell whether wb-window's `code --open-url` ever
 * reached a window, or which one, when several are open on the same
 * profile. Fired for every action including 'unknown', and NOT awaited: the
 * command dispatch below must never wait on a filesystem write.
 */
function handleWorkbenchUri(uri: vscode.Uri): void {
  const action = resolveUriAction(uri.path);
  void appendUriReceipt(action, vscode.workspace.workspaceFolders?.[0]?.uri.fsPath);
  switch (action) {
    case 'worker-tab':
      log(`URI-Handler: '${uri.path}' -> claude-workbench.openWorkerTab.`);
      void vscode.commands.executeCommand('claude-workbench.openWorkerTab');
      break;
    case 'reload':
      log(`URI-Handler: '${uri.path}' -> Fenster-Reload.`);
      void vscode.commands.executeCommand('workbench.action.reloadWindow');
      break;
    case 'unknown':
      log(`URI-Handler: unbekannter Pfad '${uri.path}' verworfen — kein Kommando ausgeführt.`);
      break;
  }
}

function workerTerminal(): vscode.Terminal | undefined {
  return vscode.window.terminals.find((t) => t.name === WORKER_TERMINAL_NAME);
}

/**
 * What extension.ts knows about the worker terminal, gathered for
 * resolveWorkerTabState (workerTab.ts) to judge — session identity included,
 * via `attachedTo`. Returns undefined when there is no terminal with that
 * name at all.
 */
function existingWorkerTab(): ExistingWorkerTab | undefined {
  const terminal = workerTerminal();
  if (!terminal) {
    return undefined;
  }
  return {
    createdByUs: ownTerminals.has(terminal),
    exited: terminal.exitStatus !== undefined,
    attachedTo: terminalSessions.get(terminal),
  };
}

/**
 * Applies a layout switch to the RUNNING session (SPEC-V2 C). wb-grid moves the
 * panes for the new setting — it never kills a worker — and only then does the
 * tab follow: opened for "window", closed for "split" AFTER the panes are back,
 * so no tab is ever left pointing at a `workers` window that no longer exists.
 */
async function applyWorkerLayout(
  context: vscode.ExtensionContext,
  layout: WorkerLayout,
): Promise<void> {
  const previous = workerLayout;
  workerLayout = layout;
  const dir = vscode.workspace.workspaceFolders?.[0]?.uri.path;
  if (!dir || layout === previous) {
    return;
  }
  const sessionKey = context.workspaceState.get<string>(SESSION_KEY_STATE);
  const state = await readState(dir, sessionKey);
  const session = state?.tmuxSession ?? sessionName(dir, sessionKey);
  const remote = isRemoteWindow();
  const wanted = remote ? undefined : session;
  const wantedAlive = !remote && await hasSession(session);
  const orchestrator = await findOrchestratorPane(session);
  if (orchestrator.status === 'ok') {
    await regrid(orchestrator.paneId);
  }
  switch (workerTabAction(layout, resolveWorkerTabState(existingWorkerTab(), wanted, wantedAlive))) {
    case 'open':
      await showWorkerTerminal(dir, sessionKey);
      workerTerminal()?.show(true);
      vscode.window.setStatusBarMessage(
        'Workers are now in the tab "Agent Workbench — Worker".', 6000,
      );
      break;
    case 'close':
      workerTerminal()?.dispose();
      // The grouped session only existed for that tab; its windows belong to the
      // orchestrator session and survive.
      await killViewSession(session);
      lastTabHintAt = undefined;
      // A deliberate layout switch away is not a close loop — the next time
      // layout comes back to 'window' the self-heal budget must start clean,
      // not carry a burst count left over from before the switch.
      primaryReopenThrottle = undefined;
      break;
    case 'none':
      break;
  }
  // The overflow tabs (workers-2, ...) follow the same switch: wb-grid already
  // moved/folded their windows via the regrid above, so the tmux state this
  // reads is already the post-switch one, not a race against it.
  await applyWorkerTabAutoHeal(context);
}

/**
 * The visibility guarantee: with layout "window" the workers live in their own
 * tmux window. If this VSCode window has no tab showing it, alice sees an
 * empty grid and would assume nothing is running — so say it, with the button
 * that fixes it. Rate-limited, so it stays a hint and does not nag.
 */
async function checkWorkerTabVisible(
  context: vscode.ExtensionContext,
  workerCount: number,
): Promise<void> {
  const now = Date.now();
  const dir = vscode.workspace.workspaceFolders?.[0]?.uri.path;
  const remote = isRemoteWindow();
  let wanted: string | undefined;
  let wantedAlive = false;
  if (dir && !remote) {
    const sessionKey = context.workspaceState.get<string>(SESSION_KEY_STATE);
    const state = await readState(dir, sessionKey);
    wanted = state?.tmuxSession ?? sessionName(dir, sessionKey);
    wantedAlive = await hasSession(wanted);
  }
  const tabState = resolveWorkerTabState(existingWorkerTab(), wanted, wantedAlive);
  if (!shouldHintWorkerTab(workerLayout, tabState, workerCount, lastTabHintAt, now)) {
    return;
  }
  lastTabHintAt = now;
  const choice = await vscode.window.showWarningMessage(
    hintMessage(workerCount),
    OPEN_TAB_LABEL,
  );
  if (choice === OPEN_TAB_LABEL) {
    await vscode.commands.executeCommand('claude-workbench.openWorkerTab');
  }
}

/**
 * The orchestrator starts full-height; the editor takes room back only when
 * alice un-maximizes the panel himself. Can be turned off in the settings
 * (terminalStartMaximized).
 *
 * 'workbench.panel.opensMaximized: always' does not fire for a panel that is
 * already open, and toggleMaximizedPanel alone would shrink an already maximized
 * panel. On a HIDDEN panel that command is not a toggle: VSCode shows the panel
 * and maximizes it only if it is not maximized yet (workbench source, 1.9x).
 * Closing first therefore makes the sequence idempotent.
 */
async function maximizePanel(enabled: boolean): Promise<void> {
  if (!enabled) {
    return;
  }
  try {
    await vscode.commands.executeCommand('workbench.action.closePanel');
    await vscode.commands.executeCommand('workbench.action.toggleMaximizedPanel');
  } catch {
    // layout nicety only — never fail the session start over it
  }
}

async function focusWorker(paneId: string): Promise<void> {
  try {
    await focusPane(paneId);
    const terminal = vscode.window.terminals.find((t) => t.name === TERMINAL_NAME);
    terminal?.show(true);
  } catch {
    vscode.window.showWarningMessage(`Pane ${paneId} could not be focused.`);
  }
}

async function sendPath(context: vscode.ExtensionContext, uri?: vscode.Uri): Promise<void> {
  const target = uri ?? vscode.window.activeTextEditor?.document.uri;
  if (!target) {
    vscode.window.showWarningMessage('No file selected.');
    return;
  }
  await sendToOrchestrator(context, relativeToWorkspace(target.fsPath) + ' ');
}

async function sendSelection(context: vscode.ExtensionContext): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selection.isEmpty) {
    vscode.window.showWarningMessage('Nothing is selected in the editor.');
    return;
  }
  const path = relativeToWorkspace(editor.document.uri.fsPath);
  const line = editor.selection.start.line + 1;
  const text = editor.document.getText(editor.selection);
  await sendToOrchestrator(context, `${path}:${line}\n${text}\n`);
}

/** Types the text into the orchestrator pane of THIS window's session. */
async function sendToOrchestrator(context: vscode.ExtensionContext, text: string): Promise<void> {
  const dir = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!dir) {
    vscode.window.showWarningMessage('No project folder is open.');
    return;
  }
  // The state file's tmuxSession is the truth; the computed name is only a
  // fallback for a project that has never been started (SPEC V1.1).
  const sessionKey = context.workspaceState.get<string>(SESSION_KEY_STATE);
  const state = await readState(dir, sessionKey);
  const session = state?.tmuxSession ?? sessionName(dir, sessionKey);
  const orchestrator = await findOrchestratorPane(session);
  if (orchestrator.status === 'missing') {
    vscode.window.showWarningMessage(
      `No orchestrator pane found in tmux session "${session}".`,
    );
    return;
  }
  if (orchestrator.status === 'dead') {
    vscode.window.showWarningMessage(
      `The orchestrator pane in "${session}" is dead — restart it with wb-revive.`,
    );
    return;
  }
  try {
    await sendText(orchestrator.paneId, text);
    vscode.window.setStatusBarMessage('Sent to the orchestrator — add your instruction and send it.', 4000);
  } catch (error) {
    vscode.window.showErrorMessage(`Sending to the orchestrator failed: ${error}`);
  }
}

function relativeToWorkspace(fsPath: string): string {
  const root = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!root) {
    return fsPath;
  }
  const rel = relative(root, fsPath);
  return rel.startsWith('..') ? fsPath : rel;
}
