// The machine dimension: a workbench session runs either on this Mac (local,
// unchanged V1 behaviour) or fully remote on Host2 via Remote-SSH. Pure helpers
// only — no vscode, no child_process — so the routing logic stays unit-testable.

export type Machine = 'mac' | 'host2';

// Kit: one machine (owner decision); 'mac' is the internal id of this machine on any system.
export const MACHINES: readonly Machine[] = ['mac'];

export const MACHINE_LABEL: Record<Machine, string> = {
  mac: 'this machine',
  host2: 'second machine',
};

/** ssh host alias (~/.ssh/config), keyless. */
export const HOST2_SSH_HOST = 'host2';

/**
 * SSH host for a machine name out of a state file, or undefined when there is
 * none to reach: 'mac' is where the extension host itself runs (Design C), and
 * an unknown name must not be turned into a host guess.
 */
export function sshHostFor(machine: string): string | undefined {
  return machine === 'host2' ? HOST2_SSH_HOST : undefined;
}

/** Remote-SSH authority VSCode uses for `vscode-remote://ssh-remote+host2<path>`. */
export const HOST2_REMOTE_AUTHORITY = 'ssh-remote+host2';

/** globalState key persisting the last chosen machine across windows/restarts. */
export const MACHINE_STATE_KEY = 'claudeWorkbench.machine';

export function isMachine(value: unknown): value is Machine {
  return value === 'mac' || value === 'host2';
}

export function otherMachine(machine: Machine): Machine {
  return machine === 'mac' ? 'host2' : 'mac';
}

export interface RemoteUriParts {
  scheme: 'vscode-remote';
  authority: string;
  path: string;
}

/**
 * Parts of the Remote-SSH URI that opens an host2 folder fully remote. The path
 * must be the absolute path ON host2 (e.g. /home/alice/AI/foo); VSCode reloads
 * the window into the remote extension host, where Explorer, editor and terminal
 * all operate on real host2 files.
 */
export function host2RemoteUri(absHost2Path: string): RemoteUriParts {
  return { scheme: 'vscode-remote', authority: HOST2_REMOTE_AUTHORITY, path: absHost2Path };
}
