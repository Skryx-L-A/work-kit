// Brain integration (module 20-brain): the `brain` CLI. Pure module.
import { execFile } from 'node:child_process';
import { access, constants } from 'node:fs/promises';
import { delimiter, isAbsolute, join } from 'node:path';
import { expandHome } from './runs.ts';

export type Exec = (command: string, args: string[], timeoutMs: number) => Promise<{ stdout: string; stderr: string }>;

export const defaultExec: Exec = (command, args, timeoutMs) =>
  new Promise((resolve, reject) => {
    execFile(command, args, { timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        reject(Object.assign(error, { stdout: String(stdout), stderr: String(stderr) }));
      } else {
        resolve({ stdout: String(stdout), stderr: String(stderr) });
      }
    });
  });

/** Resolves a command like `command -v`: absolute paths as is, else the first executable on PATH. */
export async function findExecutable(command: string, pathEnv: string = process.env.PATH ?? ''): Promise<string | undefined> {
  const expanded = expandHome(command);
  const candidates = isAbsolute(expanded)
    ? [expanded]
    : [...pathEnv.split(delimiter).filter(Boolean), expandHome('~/.local/bin')].map((d) => join(d, expanded));
  for (const candidate of candidates) {
    try {
      await access(candidate, constants.X_OK);
      return candidate;
    } catch {
      // next
    }
  }
  return undefined;
}

export const BRAIN_MISSING = 'The brain CLI is not installed (module 20-brain). Continue without it and say so in the result.';

export class Brain {
  private readonly command: string;
  private readonly exec: Exec;

  constructor(command: string, exec: Exec = defaultExec) {
    this.command = command;
    this.exec = exec;
  }

  async available(): Promise<string | undefined> {
    return findExecutable(this.command);
  }

  private async run(args: string[], timeoutMs = 60_000): Promise<string> {
    const bin = await this.available();
    if (!bin) {
      return BRAIN_MISSING;
    }
    try {
      const { stdout } = await this.exec(bin, args, timeoutMs);
      return stdout.trim() || '(no output)';
    } catch (error) {
      const e = error as Error & { stderr?: string };
      return `brain ${args[0]} failed: ${(e.stderr || e.message).trim().slice(0, 500)}`;
    }
  }

  search(query: string, k = 5): Promise<string> {
    return this.run(['search', query, '-k', String(Math.max(1, Math.min(20, Math.round(k))))]);
  }

  read(pathOrTitle: string): Promise<string> {
    return this.run(['read', pathOrTitle]);
  }

  /** `brain status` for the status view; short timeout, the view must not hang. */
  status(): Promise<string> {
    return this.run(['status'], 15_000);
  }
}
