// Spawn requests written by `kit-wb spawn` (terminal orchestrators). Pure module.
//
//   <stateDir>/requests/<id>/request   key=value lines: name, model, paths, done, cwd, brain=off
//   <stateDir>/requests/<id>/task.md   task text
//   <stateDir>/requests/<id>/run-id    written by the extension once the run exists
//   <stateDir>/requests/<id>/error     written by the extension when the request is rejected
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

export interface SpawnRequest {
  name: string;
  model?: string;
  paths: string[];
  done: string;
  cwd?: string;
  task: string;
  /** false when `kit-wb spawn --no-brain` switched knowledge search off. */
  brain?: boolean;
}

export function parseRequestFile(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split(/\r?\n/)) {
    const m = /^([a-z]+)=(.*)$/.exec(line);
    if (m) {
      out[m[1]] = m[2];
    }
  }
  return out;
}

export function buildRequest(fields: Record<string, string>, task: string): SpawnRequest | string {
  const name = (fields.name ?? '').trim();
  if (!name) {
    return 'request has no name';
  }
  if (!task.trim()) {
    return 'request has an empty task';
  }
  return {
    name,
    model: fields.model?.trim() || undefined,
    paths: (fields.paths ?? '').split(',').map((p) => p.trim()).filter((p) => p.length > 0),
    done: (fields.done ?? '').trim(),
    cwd: fields.cwd?.trim() || undefined,
    task,
    brain: fields.brain === 'off' ? false : undefined,
  };
}

export type RequestState = 'pending' | 'accepted' | 'rejected' | 'incomplete';

async function exists(file: string): Promise<boolean> {
  try {
    await readFile(file);
    return true;
  } catch {
    return false;
  }
}

export async function requestState(dir: string): Promise<RequestState> {
  if (await exists(join(dir, 'run-id'))) {
    return 'accepted';
  }
  if (await exists(join(dir, 'error'))) {
    return 'rejected';
  }
  // kit-wb writes task.md first and `request` last, so `request` means complete.
  return (await exists(join(dir, 'request'))) ? 'pending' : 'incomplete';
}

export async function readRequest(dir: string): Promise<SpawnRequest | string> {
  try {
    const fields = parseRequestFile(await readFile(join(dir, 'request'), 'utf8'));
    const task = await readFile(join(dir, 'task.md'), 'utf8').catch(() => '');
    return buildRequest(fields, task);
  } catch (error) {
    return `cannot read request: ${(error as Error).message}`;
  }
}

export async function acceptRequest(dir: string, runId: string): Promise<void> {
  await writeFile(join(dir, 'run-id'), runId + '\n', 'utf8');
}

export async function rejectRequest(dir: string, reason: string): Promise<void> {
  await writeFile(join(dir, 'error'), reason + '\n', 'utf8');
}
