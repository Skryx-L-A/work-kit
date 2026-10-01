// Quittung for a handled claude-workbench URI (2026-08-04) — appended to
// ~/.local/state/wb-window-uri.log so `wb-window` can tell whether a URI it
// sent actually reached a window, and WHICH one. That second part is the
// real question: with several windows open on the same profile it is
// unspecified which one's registerUriHandler fires, and only the receipt
// says. Kept free of vscode (only a type import from uriHandler.ts, erased
// at compile time), same convention as uriHandler.ts/terminal.ts, and the
// same append-only never-throw shape as settingsLog.ts's change log.
// Written SYNCHRONOUSLY, for the same reason sessionClose.ts is: the one
// action this receipt matters most for is 'reload', and that tears the
// extension host down within milliseconds of the command dispatch below. An
// awaited mkdir/appendFile pair would very likely still land — but "very
// likely" is the wrong guarantee for the line that exists to prove the URI
// arrived at all. The write is a few hundred bytes into a local file; there
// is nothing to gain by deferring it.
import { appendFileSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import type { UriAction } from './uriHandler.ts';

export function uriReceiptLogPath(): string {
  return join(homedir(), '.local', 'state', 'wb-window-uri.log');
}

/**
 * One line per URI `handleWorkbenchUri` handled, including 'unknown' — a
 * silently dropped unrecognised path is exactly the kind of mismatch the
 * receipt exists to surface. `folder` is the WORKSPACE FOLDER of the window
 * that handled it; empty string when none is open, never omitted, so the
 * line always has three tab-separated fields to parse.
 */
export function formatReceiptLine(
  action: UriAction,
  folder: string | undefined,
  now: Date = new Date(),
): string {
  return `${now.toISOString()}\t${action}\t${folder ?? ''}\n`;
}

/**
 * Appends the receipt line. NEVER throws: by the time this runs, the command
 * the URI asked for has already been dispatched (or, for 'unknown',
 * deliberately not) — a directory that cannot be created or a disk that
 * cannot be written must not take that back. Fire-and-forget from the caller
 * (not awaited before dispatching the command) for the same reason.
 */
export function appendUriReceipt(
  action: UriAction,
  folder: string | undefined,
  file: string = uriReceiptLogPath(),
): void {
  try {
    mkdirSync(dirname(file), { recursive: true });
    appendFileSync(file, formatReceiptLine(action, folder), 'utf8');
  } catch {
    // see docstring above — a failed quittung must never surface as a failure
  }
}
