// Run store and result protocol. Pure Node module, no vscode import.
//
//   <stateDir>/runs/<id>/meta.json   run metadata and status
//   <stateDir>/runs/<id>/task.md     full task for the worker
//   <stateDir>/runs/<id>/result.md   written by the worker; last non-empty line "DONE" = success
//   <stateDir>/runs/<id>/log.jsonl   API workers: model turns and tool calls
//   <stateDir>/archive/<id>/         finished runs moved out of the lists (kept, not deleted)
import { appendFile, mkdir, readdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

export type RunStatus = 'running' | 'done' | 'failed' | 'stopped';
export type RunRole = 'worker' | 'orchestrator';

export interface RunMeta {
  id: string;
  name: string;
  role: RunRole;
  modelId: string;
  modelLabel: string;
  runner: string;
  cwd: string;
  paths: string[];
  done: string;
  status: RunStatus;
  createdAt: string;
  endedAt?: string;
  /** Short reason for failed/stopped, shown in the tree view. */
  reason?: string;
  /** Who asked for the run: 'user', 'chat', 'panel', 'tool', 'request'. */
  origin?: string;
  /** Knowledge search step on (default) or off for this run. */
  brain?: boolean;
  /** Process id of the extension host that drives the run. */
  owner?: number;
}

export const RUN_STATUSES: readonly RunStatus[] = ['running', 'done', 'failed', 'stopped'];
export const DONE_MARKER = 'DONE';

export function expandHome(path: string, home: string = homedir()): string {
  if (path === '~') {
    return home;
  }
  return path.startsWith('~/') ? join(home, path.slice(2)) : path;
}

export function runsDir(stateDir: string): string {
  return join(stateDir, 'runs');
}

export function requestsDir(stateDir: string): string {
  return join(stateDir, 'requests');
}

export interface RunFiles {
  dir: string;
  meta: string;
  task: string;
  result: string;
  log: string;
}

export function runFiles(stateDir: string, id: string): RunFiles {
  const dir = join(runsDir(stateDir), id);
  return {
    dir,
    meta: join(dir, 'meta.json'),
    task: join(dir, 'task.md'),
    result: join(dir, 'result.md'),
    log: join(dir, 'log.jsonl'),
  };
}

/** True when the last non-empty line of a result is exactly the DONE marker. */
export function resultIsDone(text: string): boolean {
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter((l) => l.length > 0);
  return lines.length > 0 && lines[lines.length - 1] === DONE_MARKER;
}

export interface TaskSpec {
  name: string;
  task: string;
  paths: string[];
  done: string;
  cwd: string;
  resultFile: string;
  /** Knowledge search step in the protocol; off per project (setting) or per task. */
  brain: boolean;
}

/** The task file every worker reads, whatever its runner. */
export function renderTask(spec: TaskSpec): string {
  const paths = spec.paths.length > 0
    ? spec.paths.map((p) => `- \`${p}\``).join('\n')
    : '- none given: change only what the task needs, and list every changed file in the result';
  return [
    `# Task: ${spec.name}`,
    '',
    spec.task.trim(),
    '',
    '## Working directory',
    '',
    `\`${spec.cwd}\``,
    '',
    '## Exclusive paths (the only files you may change)',
    '',
    paths,
    '',
    '## Done criterion',
    '',
    spec.done.trim() || 'Not given: state in the result how you checked your work.',
    '',
    '## Protocol',
    '',
    spec.brain
      ? '1. Before non-trivial work, search the brain if it is installed (`brain search "<topic>" -k 5`); if it is not, continue without it.'
      : '1. Knowledge search is switched off for this task: do not search the brain.',
    '2. Do the task. Keep changes others made. Report only results you observed.',
    `3. Write the result as Markdown to \`${spec.resultFile}\` with the sections`,
    '   `## What` (what you did), `## Verified` (commands and observed output), `## Open`',
    '   (open points and decisions). The last line of the file must be exactly `DONE`.',
    '   If you cannot finish, write the result anyway and end it with `FAILED: <reason>` instead.',
    '',
  ].join('\n');
}

export function parseMeta(raw: string): RunMeta | undefined {
  try {
    const m = JSON.parse(raw) as Partial<RunMeta>;
    if (!m || typeof m.id !== 'string' || typeof m.name !== 'string') {
      return undefined;
    }
    const status = (RUN_STATUSES as readonly string[]).includes(m.status as string) ? m.status! : 'failed';
    return {
      id: m.id,
      name: m.name,
      role: m.role === 'orchestrator' ? 'orchestrator' : 'worker',
      modelId: String(m.modelId ?? ''),
      modelLabel: String(m.modelLabel ?? m.modelId ?? ''),
      runner: String(m.runner ?? ''),
      cwd: String(m.cwd ?? ''),
      paths: Array.isArray(m.paths) ? m.paths.map(String) : [],
      done: String(m.done ?? ''),
      status,
      createdAt: String(m.createdAt ?? ''),
      endedAt: m.endedAt,
      reason: m.reason,
      origin: m.origin,
      brain: m.brain === false ? false : undefined,
      owner: typeof m.owner === 'number' ? m.owner : undefined,
    };
  } catch {
    return undefined;
  }
}

async function writeAtomic(file: string, text: string): Promise<void> {
  const tmp = `${file}.${process.pid}.tmp`;
  await writeFile(tmp, text, 'utf8');
  await rename(tmp, file);
}

export async function writeMeta(stateDir: string, meta: RunMeta): Promise<void> {
  await writeAtomic(runFiles(stateDir, meta.id).meta, JSON.stringify(meta, null, 2) + '\n');
}

export async function readMeta(stateDir: string, id: string): Promise<RunMeta | undefined> {
  try {
    return parseMeta(await readFile(runFiles(stateDir, id).meta, 'utf8'));
  } catch {
    return undefined;
  }
}

export async function readResult(stateDir: string, id: string): Promise<string | undefined> {
  try {
    return await readFile(runFiles(stateDir, id).result, 'utf8');
  } catch {
    return undefined;
  }
}

export async function createRun(stateDir: string, meta: RunMeta, taskText: string): Promise<RunFiles> {
  const files = runFiles(stateDir, meta.id);
  await mkdir(files.dir, { recursive: true });
  await writeFile(files.task, taskText, 'utf8');
  await writeMeta(stateDir, meta);
  return files;
}

export async function appendLog(stateDir: string, id: string, entry: Record<string, unknown>): Promise<void> {
  const line = JSON.stringify({ at: new Date().toISOString(), ...entry }) + '\n';
  await appendFile(runFiles(stateDir, id).log, line, 'utf8');
}

export async function listRuns(stateDir: string): Promise<RunMeta[]> {
  let ids: string[];
  try {
    ids = await readdir(runsDir(stateDir));
  } catch {
    return [];
  }
  const metas = await Promise.all(ids.map((id) => readMeta(stateDir, id)));
  return metas
    .filter((m): m is RunMeta => m !== undefined)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

/**
 * Settles a running run from its result file: DONE marker -> done, other text -> failed.
 * Returns the updated meta, or undefined when nothing changed.
 */
export async function settleFromResult(stateDir: string, id: string, now: Date = new Date()): Promise<RunMeta | undefined> {
  const meta = await readMeta(stateDir, id);
  if (!meta || meta.status !== 'running') {
    return undefined;
  }
  const result = await readResult(stateDir, id);
  if (result === undefined || result.trim().length === 0) {
    return undefined;
  }
  const done = resultIsDone(result);
  const lastLine = result.trim().split(/\r?\n/).pop() ?? '';
  const updated: RunMeta = {
    ...meta,
    status: done ? 'done' : 'failed',
    endedAt: now.toISOString(),
    reason: done ? undefined : lastLine.slice(0, 200),
  };
  await writeMeta(stateDir, updated);
  return updated;
}

export async function markRun(
  stateDir: string,
  id: string,
  status: Exclude<RunStatus, 'running'>,
  reason?: string,
  now: Date = new Date(),
): Promise<RunMeta | undefined> {
  const meta = await readMeta(stateDir, id);
  if (!meta || meta.status !== 'running') {
    return meta;
  }
  const updated: RunMeta = { ...meta, status, reason, endedAt: now.toISOString() };
  await writeMeta(stateDir, updated);
  return updated;
}

export function processAlive(pid: number | undefined): boolean {
  if (!pid) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === 'EPERM';
  }
}

/** A running run is orphaned when the extension host that drove it is gone. */
export function isOrphaned(meta: RunMeta, alive: (pid: number | undefined) => boolean = processAlive): boolean {
  return meta.status === 'running' && meta.owner !== process.pid && !alive(meta.owner);
}

export function archiveDir(stateDir: string): string {
  return join(stateDir, 'archive');
}

/**
 * Moves finished runs (not running) into <stateDir>/archive/, newest `keep` runs excepted.
 * Nothing is deleted. Returns the ids that were moved.
 */
export async function archiveRuns(stateDir: string, keep = 0, only?: readonly string[]): Promise<string[]> {
  const finished = (await listRuns(stateDir)).filter((r) => r.status !== 'running' && (!only || only.includes(r.id)));
  const move = finished.slice(Math.max(0, keep));
  if (move.length === 0) {
    return [];
  }
  await mkdir(archiveDir(stateDir), { recursive: true });
  const moved: string[] = [];
  for (const run of move) {
    try {
      await rename(runFiles(stateDir, run.id).dir, join(archiveDir(stateDir), run.id));
      moved.push(run.id);
    } catch {
      // Another window moved it first, or the target exists: leave it.
    }
  }
  return moved;
}

/** Newest modification time of a run's files, as ISO string. */
export async function lastActivity(stateDir: string, id: string): Promise<string | undefined> {
  const f = runFiles(stateDir, id);
  let newest = 0;
  for (const file of [f.meta, f.log, f.result, f.task]) {
    try {
      newest = Math.max(newest, (await stat(file)).mtimeMs);
    } catch {
      // Not written yet.
    }
  }
  return newest > 0 ? new Date(newest).toISOString() : undefined;
}
