// Removing a resumable session (part C of the 2026-08-04 repair).
//
// The extension does not delete anything itself. It builds the call to
// `wb-session-delete`, which owns the whole operation: it decides which paths
// belong to the session, checks every one of them against the allowed roots,
// closes the tmux session through wb-session-close, writes the snapshot, and only
// then removes the two files. Keeping the deletion in ONE place means there is
// one set of guards to read and one set of tests to trust — a second
// implementation over here would be a second chance to get the scope wrong.
import { execFile } from 'node:child_process';
import { shellQuote } from './format.ts';

export const DELETE_TIMEOUT_MS = 20000;

/** `wb-session-delete --dir <dir> [--key <k>] [--yes]`. */
export function deleteCommand(dir: string, sessionKey?: string, confirmed = false): string {
  const parts = ['wb-session-delete', '--dir', shellQuote(dir)];
  if (sessionKey) {
    parts.push('--key', shellQuote(sessionKey));
  }
  if (confirmed) {
    parts.push('--yes');
  }
  return parts.join(' ');
}

export const DELETE_LABEL = 'Delete for good';

/**
 * The modal text. It names what goes AND what stays, because the one question
 * alice asked about this feature was the boundary: no kbase, no brain
 * material, no project file. A confirmation that only says "delete?" does not
 * answer it.
 */
export function confirmMessage(name: string, dir: string): string {
  return `Delete session "${name}"?`
    + `\n\nRemoved: the entry of this session, its tmux session and its agent transcript.`
    + `\nNot touched: the project folder ${dir}, its files, the notes`
    + ` and every other session.`
    + `\n\nEverything is backed up to ~/.local/trash-snapshots/ first.`;
}

export interface DeleteResult {
  ok: boolean;
  output: string;
}

/**
 * Runs the deletion through a login shell — ~/.local/bin is not necessarily in
 * the extension host's PATH. Never throws: the caller reports the output either
 * way, and a refused deletion (a window still attached, a worker still running)
 * arrives here as a normal non-zero exit with its reason on stderr.
 */
export function runDelete(dir: string, sessionKey?: string): Promise<DeleteResult> {
  return new Promise((resolve) => {
    execFile(
      '/bin/bash',
      ['-lc', deleteCommand(dir, sessionKey, true)],
      { timeout: DELETE_TIMEOUT_MS },
      (error, stdout, stderr) => resolve({
        ok: !error,
        output: `${stdout}${stderr}`.trim(),
      }),
    );
  });
}
