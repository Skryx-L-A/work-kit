// Closing the tmux session when the WINDOW closes (2026-08-04).
//
// The measured problem: alice closed three VS Code windows, the tmux sessions
// `wb-a project`, `wb-a project-view`, `wb-LocalAI-d0220f-view` and
// `wb-acme-87cd2f-4ba4b4-view` kept running unchanged, and the Claude
// processes behind them held 6,0 GB. A closed window ends its terminals; the
// tmux session behind them is built to survive exactly that.
//
// WHY A MARKER AND NOT A DIRECT KILL — the measurement (isolated VS Code 1.131,
// own --user-data-dir/--extensions-dir, probe extension, 2026-08-04 03:39-03:43):
//
//   window CLOSE (workbench.action.closeWindow):
//     03:41:35.508  onDidCloseTerminal name=probe-term   (three times)
//     03:41:35.519  DEACTIVATE start
//     ... no further activation, ever. The marker written in deactivate stayed.
//
//   window RELOAD (workbench.action.reloadWindow), four rounds:
//     03:42:38.913  DEACTIVATE end
//     03:42:39.460  ACTIVATE  (found the marker, removed it)
//     gaps measured: 574 ms, 547 ms, 559 ms, 592 ms
//
// So `deactivate()` fires for BOTH and cannot tell them apart on its own — there
// is no onWillCloseWindow in the API. The one difference that held in every run
// is what happens AFTERWARDS: a reload brings a new extension host up on the same
// workspace within about half a second, a close never does.
//
// Hence the safe variant the task asked for: deactivate() kills nothing. It
// writes "orphaned since <time>" and hands the decision to a detached watcher
// that waits out the grace period and only then acts — by which time a reload has
// long since removed the marker. The same measurement showed the watcher is
// possible at all: a detached child spawned from the dying host wrote its line
// 8 seconds later, after both a reload and a window close ("child alive at
// 2026-08-04T03:41:43Z").
//
// The closing itself is never done here. `wb-session-orphan` calls
// `wb-session-close`, which owns the checks that must not be duplicated: a client
// still attached, a worker still running, the caller's own session.
import { spawn } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { shellQuote } from './format.ts';
import { ORPHAN_GRACE_SECONDS } from './settings.ts';

/**
 * How long the watcher waits before it believes the window is really gone.
 *
 * The four measured reload gaps were 547-592 ms in a bare window. The value is
 * two orders of magnitude above that, on purpose: waiting too long only delays
 * freeing memory, while waiting too briefly would close the session of a window
 * that is still coming back — and that is exactly how a running conversation was
 * lost in the night of 2026-08-04. A real window carries more extensions and a
 * slower startup than the probe did, and the margin has to cover that unmeasured
 * difference too. Declared in settings.ts so the settings page can name it.
 */
export { ORPHAN_GRACE_SECONDS };

export interface OrphanMarker {
  /** tmux session this window was showing. */
  session: string;
  /** Project folder of the window — half of the identity a reload matches on. */
  folder: string;
  /** Session key inside that folder; absent for a folder's default session. */
  sessionKey?: string;
  /** Distinguishes two markers for the same session; a stale watcher stands down. */
  token: string;
  /** Epoch milliseconds — "verwaist seit". */
  at: number;
}

export function orphanDir(home: string = homedir()): string {
  return join(home, '.claude', 'workbench', 'orphans');
}

/**
 * One file per tmux session. The session name is already file-safe (wb-code
 * builds it from a sanitised basename plus a hash), so it is used verbatim —
 * a second encoding would only make the file hard to match up with `wb-grid`.
 */
export function orphanMarkerPath(session: string, home?: string): string {
  return join(orphanDir(home), `${session}.json`);
}

/** Arguments for the detached watcher; the shell tool owns everything after this. */
export function orphanWatchCommand(
  session: string,
  token: string,
  graceSeconds: number = ORPHAN_GRACE_SECONDS,
): string[] {
  return ['wb-session-orphan', '--session', session, '--token', token, '--grace', String(graceSeconds)];
}

export interface ArmInput {
  /** The setting closeSessionOnWindowClose. */
  enabled: boolean;
  /** tmux session this window is showing, if it has one. */
  session: string | undefined;
  /**
   * A Remote-SSH window. Its tmux server runs on the other machine, so a watcher
   * started here would look at the Mac's sessions and find the wrong ones — or
   * nothing at all. Never armed.
   */
  remote: boolean;
}

/** Should this window arm the orphan watch when it goes away? */
export function shouldArmOrphanWatch(input: ArmInput): boolean {
  return input.enabled && !input.remote && typeof input.session === 'string'
    && input.session.length > 0;
}

/**
 * Does this marker belong to the window that is starting up? Folder AND session
 * key must match: two windows can show the same folder, and clearing a foreign
 * window's marker would leave its session running forever.
 */
export function markerBelongsToWindow(
  marker: OrphanMarker,
  folder: string | undefined,
  sessionKey: string | undefined,
): boolean {
  return marker.folder === folder && (marker.sessionKey ?? undefined) === (sessionKey ?? undefined);
}

export function parseMarker(raw: string): OrphanMarker | undefined {
  try {
    const data = JSON.parse(raw);
    if (typeof data?.session !== 'string' || typeof data?.folder !== 'string') {
      return undefined;
    }
    return {
      session: data.session,
      folder: data.folder,
      sessionKey: typeof data.sessionKey === 'string' ? data.sessionKey : undefined,
      token: typeof data.token === 'string' ? data.token : '',
      at: typeof data.at === 'number' ? data.at : 0,
    };
  } catch {
    return undefined;
  }
}

/**
 * Everything below runs SYNCHRONOUSLY on purpose. `deactivate()` gets a shutdown
 * budget, not a promise VS Code waits on indefinitely, and an awaited write that
 * never lands would leave the session orphaned with nothing to clean it up.
 */
export function writeOrphanMarker(marker: OrphanMarker, home?: string): void {
  mkdirSync(orphanDir(home), { recursive: true });
  writeFileSync(orphanMarkerPath(marker.session, home), JSON.stringify(marker), 'utf8');
}

/**
 * Removes every marker of THIS window — called first thing on activation, so a
 * reload disarms the watcher its own predecessor started. Matching on folder and
 * key rather than on the session name is deliberate: the name may come from the
 * state file (`tmuxSession`) or be computed, and a mismatch would leave a live
 * session marked as orphaned.
 */
export function clearOrphanMarkers(
  folder: string | undefined,
  sessionKey: string | undefined,
  home?: string,
): string[] {
  const dir = orphanDir(home);
  let files: string[];
  try {
    files = readdirSync(dir);
  } catch {
    return [];
  }
  const cleared: string[] = [];
  for (const file of files) {
    if (!file.endsWith('.json')) {
      continue;
    }
    const path = join(dir, file);
    let marker: OrphanMarker | undefined;
    try {
      marker = parseMarker(readFileSync(path, 'utf8'));
    } catch {
      continue;
    }
    if (marker && markerBelongsToWindow(marker, folder, sessionKey)) {
      try {
        rmSync(path, { force: true });
        cleared.push(marker.session);
      } catch {
        // unreadable or already gone — the watcher's own checks still hold
      }
    }
  }
  return cleared;
}

/**
 * Starts the watcher DETACHED, so it outlives the extension host that spawns it.
 * Measured on 2026-08-04: a child spawned this way from `deactivate()` was still
 * alive 8 seconds later, both after a reload and after a window close.
 *
 * The login shell is needed because ~/.local/bin is not necessarily on the
 * extension host's PATH — the same reason sessionDelete.ts uses one.
 */
export function spawnOrphanWatcher(command: string[], shell = '/bin/bash'): number | undefined {
  try {
    const child = spawn(shell, ['-lc', command.map(shellQuote).join(' ')], {
      detached: true,
      stdio: 'ignore',
    });
    child.unref();
    return child.pid;
  } catch {
    return undefined;
  }
}
