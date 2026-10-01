// Worker tab (SPEC-V2 C) — the rules around the second terminal tab.
//
// The failure this guards against, seen for real on 2026-07-25: settings said
// workerLayout "window", four workers were running in the tmux window `workers`,
// and the session had no worker tab (it was started before the feature existed).
// alice saw NO workers at all and had to assume none were running. Silence is
// the worst possible outcome here, so the extension either shows the tab or says
// out loud that it is missing.
import { execFile } from 'node:child_process';
import type { WorkerLayout } from './settings.ts';

export type WorkerTabAction = 'open' | 'close' | 'none';

/**
 * State of the worker tab in this window:
 *   none  — no terminal with that name
 *   ghost — a terminal that shows nothing useful: VSCode restored it across a
 *           reload (right name, dead shell), a foreign window created it, its
 *           shell has exited, or it is attached to a session that is not the
 *           one this window currently wants (wrong session, or the wanted
 *           session no longer exists). As useless as no tab at all.
 *   live  — a terminal this extension host created, whose shell still runs,
 *           attached to the session this window currently wants.
 */
export type WorkerTabState = 'none' | 'ghost' | 'live';

/**
 * What the layout demands of the tab: "window" needs a LIVE one (a ghost is
 * replaced), "split" must not leave any behind — after wb-grid pulls the panes
 * back, the `workers` window is gone and a leftover tab would point at nothing.
 */
export function workerTabAction(layout: WorkerLayout, tab: WorkerTabState): WorkerTabAction {
  if (layout === 'window') {
    return tab === 'live' ? 'none' : 'open';
  }
  return tab === 'none' ? 'none' : 'close';
}

/** What extension.ts knows about the worker terminal, before session identity is judged. */
export interface ExistingWorkerTab {
  /** Created by this extension host — a tab VSCode restored across a reload is not. */
  createdByUs: boolean;
  /** Its shell process has exited. */
  exited: boolean;
  /** tmux session this terminal was launched for (terminalSessions), if known. */
  attachedTo?: string;
}

/**
 * Resolves the worker tab's WorkerTabState — the counterpart to
 * `terminalPlan` (terminal.ts) for the orchestrator tab, closing the gap named
 * in the task of 2026-08-04 that added this: `workerTabState()` used to judge
 * a tab "live" from `createdByUs`/`exited` alone, never asking whether it was
 * attached to the RIGHT session. A tab left over from a session that
 * `wb-session-delete` removed, or from a session key that changed under this
 * window, still passed both those checks — it looked exactly like a healthy
 * tab, so the self-heal loop (`workerTabAction`) never replaced it and
 * alice was looking at a tab pointing at nothing real. "A stored name
 * outlives what it named" is the same failure family as the six 2026-08-04
 * structure bugs the shell-side `wb-doctor` exists for — this is that lesson
 * applied to the extension side.
 *
 * `wanted` is the tmux session this window currently expects the tab to be
 * on; `wantedAlive` is whether that session currently exists. Passing
 * `wanted: undefined` (a remote/host2 window, where the tmux server is not
 * this machine's and session liveness cannot be answered locally — the same
 * exemption `verifyTab`/`windowSessionAlive`/`applyWorkerTabAutoHeal` already
 * apply) falls back to judging the tab by `createdByUs`/`exited` alone, the
 * pre-2026-08-04 behaviour, since there is nothing to compare `attachedTo`
 * against.
 *
 * Deliberately NOT session-aware in the other direction: `workerTabAction`/
 * `shouldHintWorkerTab` keep taking the abstract 'live'/'ghost'/'none' state
 * and never a session name (see the dedicated test for that in
 * workerTab.test.ts) — this is the one place session identity is judged, so
 * every consumer of WorkerTabState gets it for free without re-deriving it.
 */
export function resolveWorkerTabState(
  existing: ExistingWorkerTab | undefined,
  wanted: string | undefined,
  wantedAlive: boolean,
): WorkerTabState {
  if (!existing) {
    return 'none';
  }
  if (!existing.createdByUs || existing.exited) {
    return 'ghost';
  }
  if (wanted !== undefined && (existing.attachedTo !== wanted || !wantedAlive)) {
    return 'ghost';
  }
  return 'live';
}

/**
 * settings.json is GLOBAL, the layout a window believes in is local. A window
 * that did not make the change would otherwise keep acting on "split" while its
 * workers move into the `workers` window on the next wb-grid run — the same
 * invisible-workers incident, one window over. So every window watches the file
 * and treats a FOREIGN change like its own.
 *
 * Applying only ever touches the window's OWN tmux session, and only when the
 * value really differs from what this window last acted on. Two windows can
 * therefore not push each other in circles: after the first application both
 * agree with the file, and the next observation is a no-op.
 */
export function syncLayout(
  known: WorkerLayout,
  fromFile: WorkerLayout,
): { apply: boolean; known: WorkerLayout } {
  return { apply: known !== fromFile, known: fromFile };
}

/** How long the hint stays quiet after it was shown once. */
export const HINT_COOLDOWN_MS = 5 * 60 * 1000;

/**
 * Warn when workers are running in a `workers` window that nothing in this
 * window shows. No workers, no tab needed yet; and never more than once per
 * cooldown, so the hint stays a hint and does not become noise.
 */
export function shouldHintWorkerTab(
  layout: WorkerLayout,
  tab: WorkerTabState,
  workerCount: number,
  lastHintAt: number | undefined,
  now: number,
  cooldownMs: number = HINT_COOLDOWN_MS,
): boolean {
  // A ghost tab counts as missing: it shows nothing, which is exactly the
  // failure this hint exists for.
  if (layout !== 'window' || tab === 'live' || workerCount < 1) {
    return false;
  }
  return lastHintAt === undefined || now - lastHintAt >= cooldownMs;
}

export function hintMessage(workerCount: number): string {
  const workers = workerCount === 1 ? '1 worker runs' : `${workerCount} workers run`;
  return `${workers} in their own worker tab, which is not open here.`;
}

export const OPEN_TAB_LABEL = 'Open worker tab';

/** The one worker-tab window that always exists once layout is 'window'. */
export const PRIMARY_WORKER_WINDOW = 'workers';

/**
 * Terminal name for an overflow worker-tab window ('workers-2' -> '<base> 2').
 * `base` is the primary tab's own name (extension.ts's WORKER_TERMINAL_NAME) —
 * kept as a parameter instead of a second literal here, so the two names cannot
 * drift apart. Anything that is not a recognised overflow window falls back to
 * the base name unchanged.
 */
export function overflowWorkerTerminalName(base: string, windowName: string): string {
  const match = /^workers-([0-9]+)$/.exec(windowName);
  return match ? `${base} ${match[1]}` : base;
}

export interface OverflowTabsPlan {
  /** Overflow windows (workers-2, ...) that exist in tmux but have no terminal yet. */
  toOpen: string[];
  /** Overflow windows whose terminal must close — layout switched away, or wb-grid folded the window back. */
  toClose: string[];
}

/**
 * What to do about the OVERFLOW worker tabs (workers-2, workers-3, ... —
 * 2026-08-04, once wb-grid's maxWorkerPanesPerTab is exceeded). The PRIMARY tab
 * ('workers') is deliberately excluded on both sides: it is opened at session
 * start and via the hint's button (workerTabAction/shouldHintWorkerTab above),
 * and closed on an explicit layout switch — a periodic poll fighting over the
 * SAME tab would race that flow for no reason. Overflow tabs have no such
 * moment: wb-grid opens and folds them purely by worker count, at any time, so
 * nothing but a poll against tmux's actual window list can open or close them
 * correctly. This is rule 2 of the task that added it: a tab may never keep
 * pointing at a window that stopped existing, and a window that newly exists
 * must not need a manual `tmux select-window` to become visible.
 */
export function syncOverflowWorkerTabs(
  layout: WorkerLayout,
  tmuxWindows: string[],
  openWindows: string[],
): OverflowTabsPlan {
  const overflowTmux = tmuxWindows.filter((w) => w !== PRIMARY_WORKER_WINDOW);
  const overflowOpen = openWindows.filter((w) => w !== PRIMARY_WORKER_WINDOW);
  if (layout !== 'window') {
    return { toOpen: [], toClose: overflowOpen };
  }
  const tmuxSet = new Set(overflowTmux);
  const openSet = new Set(overflowOpen);
  return {
    toOpen: overflowTmux.filter((w) => !openSet.has(w)),
    toClose: overflowOpen.filter((w) => !tmuxSet.has(w)),
  };
}

/**
 * Budget for the self-heal loop (2026-08-04): if the tab keeps disappearing,
 * something is putting it away on purpose and re-fighting that is not a fix —
 * see planReopen below for the reasoning behind the numbers.
 */
export const AUTO_REOPEN_MAX_ATTEMPTS = 3;
export const AUTO_REOPEN_WINDOW_MS = 60 * 1000;

/** Tracks one reopen burst: how many attempts so far, since when. */
export interface ReopenThrottle {
  attempts: number;
  windowStart: number;
}

export interface ReopenPlan {
  reopen: boolean;
  next: ReopenThrottle;
}

/**
 * Whether a poll tick that found the tab missing may put it back, and the
 * throttle state to carry into the next tick.
 *
 * The tab must reopen itself when it disappears out from under a running
 * session — a dead shell, a reload that dropped it, anything short of
 * alice deliberately closing it. But a deliberate close looks IDENTICAL to
 * the poll: the tab is just gone. Reopening unconditionally would mean a
 * closed tab pops right back on the next tick, forever — the one behaviour
 * expressly ruled out for this feature (no dialog is fine; a tab that cannot
 * be closed is not).
 *
 * The distinguishing signal is speed: a crash or a reload produces exactly
 * ONE missing-tab event, because nothing keeps taking the replacement away
 * again. Only a human clicking the close button repeatedly produces a BURST
 * of them. Three attempts inside one minute is generous enough that a single
 * unlucky run of poll ticks (e.g. two crashes minutes apart, each their own
 * fresh burst) never trips it, while a person closing the tab three times
 * inside sixty seconds unambiguously means "stop". Past that budget this
 * returns reopen: false for the rest of the window, and the caller's
 * existing hint (shouldHintWorkerTab) is the fallback — it still offers the
 * manual "open" button, it just no longer happens on its own.
 *
 * The window resets on the first attempt after it has expired, so self-heal
 * is not disabled forever: once alice stops closing the tab, the very
 * next unrelated disappearance (a crash, a reload) gets its own fresh burst
 * and is healed immediately.
 */
export function planReopen(
  throttle: ReopenThrottle | undefined,
  now: number,
  maxAttempts: number = AUTO_REOPEN_MAX_ATTEMPTS,
  windowMs: number = AUTO_REOPEN_WINDOW_MS,
): ReopenPlan {
  if (throttle === undefined || now - throttle.windowStart >= windowMs) {
    return { reopen: true, next: { attempts: 1, windowStart: now } };
  }
  if (throttle.attempts >= maxAttempts) {
    return { reopen: false, next: throttle };
  }
  return { reopen: true, next: { attempts: throttle.attempts + 1, windowStart: throttle.windowStart } };
}

/**
 * Re-tiles the session for the CURRENT setting: wb-grid reads workerLayout
 * itself and MOVES panes (break-pane/join-pane), so a running worker survives
 * the switch. `paneRef` is any pane of the session — wb-grid derives the session
 * from it. Login shell because wb-grid lives in ~/.local/bin.
 */
export const REGRID_TIMEOUT_MS = 10000;

export function regridCommand(paneRef: string): string {
  return `wb-grid ${paneRef}`;
}

/** Never rejects: a failed re-tile must not stop the layout switch. */
export function regrid(paneRef: string): Promise<void> {
  return new Promise((resolve) => {
    execFile(
      '/bin/bash',
      ['-lc', regridCommand(paneRef)],
      { timeout: REGRID_TIMEOUT_MS },
      () => resolve(),
    );
  });
}
