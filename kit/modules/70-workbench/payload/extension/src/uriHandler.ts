// Decides what a claude-workbench URI means, kept free of vscode so the
// routing itself is testable (same convention as terminal.ts/workerTab.ts).
//
// SECURITY (2026-08-04): a registered URI handler is reachable from ANY web
// page a browser ever opens — one `<a href="vscode://agent-workbench.claude-workbench/…">`
// is enough, no confirmation dialog, no origin check, nothing this extension
// gets to see about who asked. That is why this resolves to a CLOSED set of
// exactly two fixed actions and reads nothing else off the URI: no command
// name, no file path, no session key, no flag of any kind crosses this
// boundary. A handler that accepted e.g. `/run?cmd=<anything>` would be a
// remote-control endpoint for every site a browser ever opens — the enum
// return type here is the enforcement, not just a convention: there is no
// code path that can hand a caller-supplied string on to a command.
//
// Anlass: the worker-tab self-heal (workerTab.ts, 2026-08-04) only takes
// effect once the extension has been freshly loaded, and a window on another
// macOS Space is reachable by neither wb-shot nor System Events — blind
// Cmd+R risks landing keystrokes in the wrong window (measured: two stray
// sessions from exactly that in one night). A URI is the one channel that
// reaches a window without seeing or clicking it.
export type UriAction = 'worker-tab' | 'reload' | 'unknown';

/**
 * `path` is `vscode.Uri.path` — deliberately the ONLY part of the URI ever
 * looked at. The query string is never read, not even to be ignored more
 * carefully: this function's signature has no parameter for it, so there is
 * nothing later code could accidentally start consuming. If a caller ever
 * concatenates path and query into one string by mistake, everything from
 * '?' onward is still stripped below before matching, so such a slip stays
 * inert instead of silently starting to work.
 *
 * Matching is exact and case-sensitive on purpose — no normalising a
 * differently-cased path into a match. The two real callers (wb-window,
 * this extension's own package.json) only ever send the exact lowercase
 * strings below; anything else reaching here is either a typo worth
 * surfacing as "unknown" or a probe, and both get the same answer: nothing
 * happens.
 */
export function resolveUriAction(path: string): UriAction {
  const bare = path.split('?')[0].replace(/^\/+/, '');
  switch (bare) {
    case 'worker-tab':
      return 'worker-tab';
    case 'reload':
      return 'reload';
    default:
      return 'unknown';
  }
}
