// vscode.openFolder reloads the window, so the terminal launch is handed to the
// next activation through globalState. Because this extension is extensionKind
// "ui" it always runs in the local (Mac) host — even inside a Remote-SSH (host2)
// window — so globalState is the same store across the reload for both machines
// (Design C). globalState is shared across all windows of the profile, so a
// pending action that does not belong to this window must survive — but not
// forever.

export interface PendingAction {
  /** Absolute path on the target machine (the host2 path for an host2 session). */
  dir: string;
  sessionId?: string;
  /** Session name and key (SPEC-V2 B) — they must survive the reload too. */
  name?: string;
  sessionKey?: string;
  /** 'mac' local or 'host2' remote — informational; the launch command is the same. */
  machine?: 'mac' | 'host2';
  createdAt: number;
}

export const PENDING_TTL_MS = 2 * 60 * 1000;

export type PendingDecision = 'consume' | 'keep' | 'expire' | 'none';

/**
 * consume — this window opened the pending folder: run it and clear it.
 * keep    — another window's pending action: leave it alone.
 * expire  — nobody picked it up in time: clear it and tell the user.
 */
export function decidePending(
  pending: PendingAction | undefined,
  folder: string | undefined,
  now: number,
): PendingDecision {
  if (!pending) {
    return 'none';
  }
  if (folder && pending.dir === folder) {
    return 'consume';
  }
  if (now - pending.createdAt > PENDING_TTL_MS) {
    return 'expire';
  }
  return 'keep';
}
