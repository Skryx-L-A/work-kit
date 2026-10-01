// Decisions about the workbench terminal, kept free of vscode so they can be tested.
import { execFile } from 'node:child_process';
import { shellQuote } from './format.ts';
import type { WorkerLayout } from './settings.ts';
import type { SessionState } from './state.ts';
import { baseSessionName, exact } from './tmux.ts';

export type TerminalPlan = 'show' | 'launch';

/** Is the tmux client (wb-code) still running under the terminal's shell? */
export type Liveness = 'alive' | 'dead' | 'unknown';

export interface ExistingTerminal {
  /** Created by this extension-host session — a restored terminal is not. */
  createdByUs: boolean;
  /** Its shell process has exited. */
  exited: boolean;
  liveness: Liveness;
  /**
   * tmux session this terminal was launched for. Undefined for a terminal whose
   * target this host does not know (a restored one).
   */
  attachedTo?: string;
}

/**
 * A terminal we launched is attached to tmux and its prompt is the orchestrator's
 * Claude chat — sending 'wb-code ...' there would submit the command as a chat
 * message, so such a terminal is only shown (review finding 6).
 *
 * But VSCode restores its own terminals after the openFolder reload: same name,
 * scrollback of the old session, fresh shell, wb-code long dead. Showing that
 * ghost leaves an empty prompt instead of the orchestrator. Only reuse a terminal
 * that we created AND whose tmux client is provably alive; anything else is
 * relaunched (a second attach is harmless — tmux is multi-client).
 *
 * `wanted` is the tmux session this start is FOR (SPEC-V2 B, part B of the
 * 2026-08-04 repair). A live terminal that hangs on a DIFFERENT session must not
 * be shown: that is how starting a second session in a folder silently dropped
 * alice back into the first one — the tab was alive, so it was revealed, and
 * the session he had just named never started.
 */
export function terminalPlan(existing?: ExistingTerminal, wanted?: string): TerminalPlan {
  if (!existing) {
    return 'launch';
  }
  if (wanted !== undefined && existing.attachedTo !== wanted) {
    return 'launch';
  }
  return existing.createdByUs && !existing.exited && existing.liveness === 'alive'
    ? 'show'
    : 'launch';
}

export interface LaunchOptions {
  /** Claude session id to resume (claude harness only, SPEC-V2 F). */
  sessionId?: string;
  /** Session name alice gave it; wb-code passes it on as `claude -n`. */
  name?: string;
  /** Missing for the folder's default session (SPEC-V2 B). */
  sessionKey?: string;
}

/** wb-code [dir] [--resume <id>] [--name <n>] [--key <k>] — SPEC-V2 B. */
export function orchestratorCommand(dir: string, options: LaunchOptions = {}): string {
  const parts = ['wb-code', shellQuote(dir)];
  if (options.sessionId) {
    parts.push('--resume', shellQuote(options.sessionId));
  }
  if (options.name) {
    parts.push('--name', shellQuote(options.name));
  }
  if (options.sessionKey) {
    parts.push('--key', shellQuote(options.sessionKey));
  }
  return parts.join(' ');
}

/**
 * Restoring the orchestrator tab after a window reload ATTACHES, nothing else:
 * plain `tmux attach-session`, never wb-code. wb-code would attach too (it is
 * idempotent), but only after deciding whether to start Claude — and a second
 * Claude instance in alice's session is the one thing that must never happen
 * here. An attach cannot do it.
 */
export function orchestratorAttachCommand(session: string): string {
  return `exec tmux attach-session -t ${shellQuote(exact(session))}`;
}

export interface RestoreState {
  /** A workspace folder is open — without one there is no session to restore. */
  hasFolder: boolean;
  /** The tmux session of this folder/session key is alive. */
  sessionAlive: boolean;
  /** The pending-launch path already started the terminals in this activation. */
  handledPending: boolean;
  layout: WorkerLayout;
}

export interface RestorePlan {
  orchestrator: boolean;
  workerTab: boolean;
}

/**
 * What to re-create after an activation (window reload — which installing a new
 * build requires). Nothing is restored for a dead session: a reload must not
 * resurrect a workbench alice has closed. And nothing is restored when the
 * launch path already ran in this activation, so no tab opens twice.
 */
export function restorePlan(state: RestoreState): RestorePlan {
  const orchestrator = state.hasFolder && state.sessionAlive && !state.handledPending;
  return { orchestrator, workerTab: orchestrator && state.layout === 'window' };
}

/** One session of the folder this window could attach to. */
export interface RestoreCandidate {
  /** undefined = the folder's default session (SPEC-V2 B). */
  sessionKey?: string;
  session: string;
}

/**
 * Which tmux sessions a fresh window may attach to, in the order they are probed
 * — the window's remembered session key first, then every other session of the
 * same folder, newest first.
 *
 * The remembered key alone is not enough (measured 2026-08-04). The key lives in
 * workspaceState, which survives every restart of VSCode and is only ever
 * overwritten by the next launch through this window. alice's window still
 * carried key 'e8d13f' from the evening before; its session
 * 'wb-AI-b310aa-e8d13f' had long ended, while the folder's default session
 * 'wb-AI' was running with six workers in it. The old code asked about the dead
 * session, got 'no', and restored nothing — in silence. Six workers stayed
 * invisible because of a key nobody had touched in twelve hours.
 *
 * So a dead key is not the end of the search: any live session of the same
 * folder is a better answer than an empty window, and the caller adopts the key
 * of whichever candidate answers.
 */
export function restoreCandidates(
  dir: string,
  storedKey: string | undefined,
  states: SessionState[],
  derive: (dir: string, sessionKey?: string) => string,
): RestoreCandidate[] {
  const ofFolder = states.filter((state) => state.dir === dir);
  const candidates: RestoreCandidate[] = [];
  const seen = new Set<string>();
  const add = (sessionKey: string | undefined, session: string): void => {
    if (seen.has(session)) {
      return;
    }
    seen.add(session);
    candidates.push({ sessionKey, session });
  };
  // The remembered key goes first even when no state file backs it — the derived
  // name is what wb-code would have used, so this stays the old behaviour.
  const stored = ofFolder.find((state) => state.sessionKey === storedKey);
  add(storedKey, stored?.tmuxSession ?? derive(dir, storedKey));
  for (const state of ofFolder) {
    add(state.sessionKey, state.tmuxSession ?? derive(dir, state.sessionKey));
  }
  return candidates;
}

/**
 * Command for the "Claude Workbench — Worker" terminal (SPEC-V2 C). It hands the
 * whole job to `wb-worker-tab`, which resolves the session, creates the `workers`
 * window and the grouped '<sess>-view' session, and attaches.
 *
 * Why a tool instead of the shell chain that used to stand here (2026-08-04): the
 * chain was ten `tmux` calls inside a TypeScript string. Nothing could execute it
 * in a test — the tests could only assert that the string contained the expected
 * fragments, never what those fragments DO on a real tmux server. Three of the
 * four faults of that night lived in exactly that blind spot: a view built on a
 * missing base (tmux does not fail there, it creates a stray session whose group
 * is the literal string '=wb-…'), a view built on a view ('-view-view-view'), and
 * a stored session name that had outlived its session. `wb-worker-tab` is
 * executable, so shell/tests/test-worker-tab.sh drives all three against a real
 * server on its own socket.
 *
 * The missing-tool case is spelled out rather than left to fail silently: a tab
 * that dies without a word is what made four running workers invisible.
 *
 * `window` (2026-08-04) is the worker-tab window to show — 'workers' (default,
 * identical command to before this parameter existed) or an overflow window
 * ('workers-2', 'workers-3', ...) once wb-grid has opened one. Only ever passed
 * through to `wb-worker-tab --window`, which is the one place that decides what
 * happens when the requested window does not actually exist.
 */
export function workerViewCommand(session: string, window: string = 'workers'): string {
  const s = shellQuote(baseSessionName(session));
  const windowFlag = window === 'workers' ? '' : ` --window ${shellQuote(window)}`;
  return [
    `command -v wb-worker-tab >/dev/null 2>&1 || ` +
      `{ echo "wb-worker-tab is not on PATH — the worker tab cannot attach."; exec "$SHELL"; }`,
    `exec wb-worker-tab ${s}${windowFlag}`,
  ].join('; ');
}

/**
 * What the tab's own shell is doing:
 *   attached — a tmux client / wb-code runs below it; the start arrived
 *   busy     — something else runs there (a slow profile, a long wb-code start)
 *   idle     — the bare prompt: nothing runs below the shell at all
 *   unknown  — no pid, or ps failed
 */
export type ShellState = 'attached' | 'busy' | 'idle' | 'unknown';

export function shellStateOf(processes: Process[], pid: number | undefined): ShellState {
  if (pid === undefined) {
    return 'unknown';
  }
  if (hasOrchestratorProcess(processes, pid)) {
    return 'attached';
  }
  return processes.some((p) => p.ppid === pid) ? 'busy' : 'idle';
}

/** What a start looks like once it should have arrived. */
export interface LaunchCheck {
  /** The tmux session this tab was started for exists. */
  sessionAlive: boolean;
  shell: ShellState;
  /** How often the command has been sent so far (1 after the first send). */
  attempt: number;
}

export type LaunchOutcome = 'ok' | 'retry' | 'report';

/** A start is re-sent once before alice is bothered with it. */
export const LAUNCH_ATTEMPTS = 2;

/**
 * Did the start actually arrive, and what follows if it did not (part A of the
 * 2026-08-04 repair).
 *
 * The measured failure: the orchestrator tab ran `wb-code … --resume …` and got a
 * '^C' before the shell had finished initialising (the profile activates a venv).
 * The typed line was discarded, the terminal sat at a bare prompt, the tmux
 * session kept running unseen, and nothing said a word.
 *
 * Of the two ways out named in the task, this is the second — the tab recognises
 * the bare prompt and offers the command again. The first (make the sent line
 * itself interrupt-proof) does not work: '^C' goes to the whole foreground
 * process group, so an interactive shell aborts the ENTIRE command list, `||`
 * branch and retry loop included. There is no line one can type into an
 * interactive shell that survives its own interruption. Checking afterwards does
 * survive it, because the check does not run in that shell.
 *
 * Re-sending is allowed ONLY at the bare prompt, and that restriction is the
 * point rather than caution. Text sent to a terminal whose foreground process is
 * not reading stdin waits in the tty buffer — and wb-code ends in
 * `exec tmux attach`, so tmux would read those characters afterwards and type
 * them into the orchestrator's Claude prompt. A retry against a busy shell would
 * therefore paste a shell command into alice's chat, which is exactly the
 * accident the "never send into a live workbench terminal" rule exists for.
 *
 * 'ok' needs BOTH conditions. The session alone proves nothing: another window
 * can keep it alive while THIS tab sits at a bare prompt, which is precisely the
 * state to be caught.
 */
export function launchOutcome(check: LaunchCheck, attempts: number = LAUNCH_ATTEMPTS): LaunchOutcome {
  if (check.sessionAlive && check.shell === 'attached') {
    return 'ok';
  }
  if (check.shell === 'idle' && check.attempt < attempts) {
    return 'retry';
  }
  return 'report';
}

/** Said out loud when a tab did not reach its session — never silence. */
export function launchFailureMessage(tab: string, session: string): string {
  return `${tab} is not attached to the tmux session "${session}". `
    + 'The start was repeated once and did not get through.';
}

export const RETRY_LAUNCH_LABEL = 'Start again';

/** Where a session start should happen. */
export type OpenAction = 'same-window' | 'new-window' | 'reload-window';

export interface OpenState {
  /** Folder currently open in this window, if any. */
  currentFolder?: string;
  /** Folder the session belongs to. */
  dir: string;
  /** Session key this window is showing (SPEC-V2 B); undefined = default session. */
  windowSessionKey?: string;
  /** Session key that is to be started. */
  targetSessionKey?: string;
  /** This window already has a running orchestrator session. */
  windowHasLiveSession: boolean;
}

/**
 * Where to start a session (part B of the 2026-08-04 repair): a second session in
 * a folder that already runs one gets its OWN window.
 *
 * Before this, starting a new session in the folder already open here ended in
 * `startOrchestratorTerminal`, which found the live orchestrator tab and merely
 * revealed it — alice named a new session and landed in the old one, with the
 * new state file written but nothing behind it. One window, one session is the
 * only arrangement in which the two tabs of a window can be checked at all: both
 * of them name exactly one tmux session.
 */
export function openPlan(state: OpenState): OpenAction {
  if (state.currentFolder !== state.dir) {
    return 'reload-window';
  }
  if (state.windowSessionKey === state.targetSessionKey) {
    return 'same-window';
  }
  return state.windowHasLiveSession ? 'new-window' : 'same-window';
}

/**
 * The part of a session name that identifies the FOLDER, without the per-session
 * suffixes wb-code appends ('wb-AI-b310aa-e8d13f' -> 'wb-AI'). Used to find a
 * live session of the same folder when the stored one is gone.
 *
 * The rule is executed inside `wb-worker-tab` (`folder_prefix`), not here — this
 * is the readable statement of it, and the test below pins the cases both
 * implementations have to agree on. If one is changed, the other has to follow.
 */
export function sessionPrefix(session: string): string {
  const parts = session.split('-');
  const kept: string[] = [];
  for (const part of parts) {
    if (kept.length >= 2 && /^[0-9a-f]{6}$/.test(part)) break;
    kept.push(part);
  }
  return kept.join('-');
}

export interface Process {
  pid: number;
  ppid: number;
  command: string;
}

/** Parses `ps -axo pid=,ppid=,command=`. */
export function parseProcesses(stdout: string): Process[] {
  const processes: Process[] = [];
  for (const line of stdout.split('\n')) {
    const match = /^\s*(\d+)\s+(\d+)\s+(.*)$/.exec(line);
    if (match) {
      processes.push({ pid: Number(match[1]), ppid: Number(match[2]), command: match[3] });
    }
  }
  return processes;
}

/** wb-code execs `tmux attach`, so the live orchestrator shows up as a tmux child. */
const ORCHESTRATOR_PROCESS = /(^|\/|\s)(tmux|wb-code|claude)(\s|$)/;

/**
 * Is this process ITSELF the attached client, rather than its parent?
 *
 * `orchestratorAttachCommand` starts with `exec`, so the tab's shell does not
 * spawn tmux as a child — it IS tmux afterwards, under the very same pid. Only
 * argv[0] may decide this: the descendant rule below may match anywhere in a
 * command line, but for the process at the pid itself that would call a plain
 * login shell 'attached' the moment the word 'claude' stood somewhere in its
 * arguments (see the test for '/bin/zsh -il claude').
 */
export function isOrchestratorProcess(command: string): boolean {
  const argv0 = command.trim().split(/\s+/)[0] ?? '';
  const name = argv0.slice(argv0.lastIndexOf('/') + 1);
  return name === 'tmux' || name === 'wb-code' || name === 'claude';
}

/**
 * Is the tab at `pid` sitting at its orchestrator — either as a child process or
 * because `exec` replaced the shell with it?
 *
 * Measured 2026-08-04, in alice's own session: the restore path execs
 * `tmux attach-session`, the descendant search found nothing under that pid, the
 * tab was judged 'idle', and verifyTab did what it does for a command that never
 * arrived — it typed the attach command a second time. By then the tab WAS the
 * tmux client, so the keystrokes went straight into the attached session's
 * active pane: the orchestrator's Claude prompt. A line of foreign text in a
 * Claude session is an instruction somebody may act on; the same path had
 * already told an orchestrator to close a pane earlier that night.
 */
export function hasOrchestratorProcess(processes: Process[], pid: number): boolean {
  const self = processes.find((process) => process.pid === pid);
  if (self && isOrchestratorProcess(self.command)) {
    return true;
  }
  return hasOrchestratorDescendant(processes, pid);
}

/** Does any descendant of `pid` look like our attached orchestrator? */
export function hasOrchestratorDescendant(processes: Process[], pid: number): boolean {
  const children = new Map<number, Process[]>();
  for (const process of processes) {
    const siblings = children.get(process.ppid);
    if (siblings) {
      siblings.push(process);
    } else {
      children.set(process.ppid, [process]);
    }
  }
  const queue = [...(children.get(pid) ?? [])];
  while (queue.length > 0) {
    const process = queue.shift()!;
    if (ORCHESTRATOR_PROCESS.test(process.command)) {
      return true;
    }
    queue.push(...(children.get(process.pid) ?? []));
  }
  return false;
}

/**
 * 'unknown' whenever the answer is not certain (no pid, ps failed) — the caller
 * then relaunches, because an empty shell prompt is the worse failure.
 */
export async function orchestratorLiveness(pid: number | undefined): Promise<Liveness> {
  if (pid === undefined) {
    return 'unknown';
  }
  let stdout: string;
  try {
    stdout = await ps();
  } catch {
    return 'unknown';
  }
  return hasOrchestratorProcess(parseProcesses(stdout), pid) ? 'alive' : 'dead';
}

/** Like orchestratorLiveness, but tells a bare prompt apart from a busy shell. */
export async function shellState(pid: number | undefined): Promise<ShellState> {
  if (pid === undefined) {
    return 'unknown';
  }
  try {
    return shellStateOf(parseProcesses(await ps()), pid);
  } catch {
    return 'unknown';
  }
}

function ps(): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile('ps', ['-axo', 'pid=,ppid=,command='], { timeout: 5000, maxBuffer: 8 << 20 },
      (error, stdout) => (error ? reject(error) : resolve(stdout)));
  });
}
