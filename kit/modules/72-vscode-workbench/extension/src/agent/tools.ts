// Tool sets for API workers and orchestrators. Pure module (the workbench is injected).
import { mkdir, readdir, readFile, realpath, stat, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, normalize, relative, resolve, sep } from 'node:path';
import type { Brain } from '../brain.ts';
import { readSkill } from '../skills.ts';
import type { ToolHandler } from './loop.ts';

const MAX_READ = 200_000;

function str(input: Record<string, unknown>, key: string): string {
  const v = input[key];
  return typeof v === 'string' ? v : v === undefined || v === null ? '' : String(v);
}

function isInside(root: string, target: string): boolean {
  const rel = relative(root, target);
  return rel === '' || (!rel.startsWith('..') && !isAbsolute(rel));
}

/** Nearest existing ancestor, resolved through symlinks. */
async function realAncestor(path: string): Promise<string> {
  let current = path;
  for (;;) {
    try {
      return await realpath(current);
    } catch {
      const parent = dirname(current);
      if (parent === current) {
        return current;
      }
      current = parent;
    }
  }
}

/**
 * Resolves a workspace-relative path and rejects anything outside `root`, including `..` and
 * symlinks that point out of it.
 */
export async function resolveInside(root: string, rel: string): Promise<string> {
  if (!rel || isAbsolute(rel)) {
    throw new Error(`path must be relative to the working directory: "${rel}"`);
  }
  const target = resolve(root, normalize(rel));
  const realRoot = await realAncestor(root);
  if (!isInside(root, target) || !isInside(realRoot, await realAncestor(target))) {
    throw new Error(`path is outside the working directory: "${rel}"`);
  }
  return target;
}

/** Write permission: inside one of the exclusive paths (a file or a folder prefix). */
export function writeAllowed(paths: readonly string[], rel: string): boolean {
  if (paths.length === 0) {
    return true;
  }
  const n = normalize(rel).replace(/[\\/]+$/, '');
  return paths.some((p) => {
    const q = normalize(p).replace(/[\\/]+$/, '');
    return q === '.' || n === q || n.startsWith(q + sep) || n.startsWith(q + '/');
  });
}

export interface WorkerToolContext {
  cwd: string;
  paths: readonly string[];
  resultFile: string;
  /** Undefined when knowledge search is switched off for the task. */
  brain?: Brain;
  skillsDir: string;
}

export function brainTool(brain: Brain): ToolHandler {
  return {
    spec: {
      name: 'brain_search',
      description: 'Hybrid search over the work notes (brain). Returns matching notes with snippets.',
      parameters: {
        type: 'object',
        properties: { query: { type: 'string' }, k: { type: 'number', description: 'Number of hits, default 5' } },
        required: ['query'],
      },
    },
    async run(input) {
      return { content: await brain.search(str(input, 'query'), Number(input.k ?? 5) || 5) };
    },
  };
}

export function skillTool(skillsDir: string): ToolHandler {
  return {
    spec: {
      name: 'read_skill',
      description: 'Read the full instructions (SKILL.md) of an installed skill by name.',
      parameters: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] },
    },
    async run(input) {
      const text = await readSkill(skillsDir, str(input, 'name'));
      return { content: text ?? `No skill named "${str(input, 'name')}".` };
    },
  };
}

export function workerTools(ctx: WorkerToolContext): ToolHandler[] {
  return [
    {
      spec: {
        name: 'read_file',
        description: 'Read a text file, path relative to the working directory.',
        parameters: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] },
      },
      async run(input) {
        const file = await resolveInside(ctx.cwd, str(input, 'path'));
        const text = await readFile(file, 'utf8');
        return { content: text.length > MAX_READ ? text.slice(0, MAX_READ) + '\n[truncated]' : text };
      },
    },
    {
      spec: {
        name: 'list_dir',
        description: 'List a directory, path relative to the working directory ("." for the root).',
        parameters: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] },
      },
      async run(input) {
        const rel = str(input, 'path') || '.';
        const dir = rel === '.' ? ctx.cwd : await resolveInside(ctx.cwd, rel);
        const entries = await readdir(dir, { withFileTypes: true });
        const lines = entries
          .filter((e) => e.name !== '.git' && e.name !== 'node_modules')
          .map((e) => (e.isDirectory() ? `${e.name}/` : e.name))
          .sort();
        return { content: lines.join('\n') || '(empty)' };
      },
    },
    {
      spec: {
        name: 'write_file',
        description: 'Create or replace a text file. Only allowed inside the exclusive paths of the task.',
        parameters: {
          type: 'object',
          properties: { path: { type: 'string' }, content: { type: 'string' } },
          required: ['path', 'content'],
        },
      },
      async run(input) {
        const rel = str(input, 'path');
        if (!writeAllowed(ctx.paths, rel)) {
          return { content: `Error: "${rel}" is not inside the exclusive paths (${ctx.paths.join(', ')}).` };
        }
        const file = await resolveInside(ctx.cwd, rel);
        await mkdir(dirname(file), { recursive: true });
        await writeFile(file, str(input, 'content'), 'utf8');
        return { content: `Wrote ${rel} (${str(input, 'content').length} characters).` };
      },
    },
    ...(ctx.brain ? [brainTool(ctx.brain)] : []),
    skillTool(ctx.skillsDir),
    {
      spec: {
        name: 'finish',
        description:
          'End the task. `result` is the Markdown result with sections What, Verified, Open. ' +
          'Set success=false when the task could not be completed.',
        parameters: {
          type: 'object',
          properties: { result: { type: 'string' }, success: { type: 'boolean' } },
          required: ['result'],
        },
      },
      async run(input) {
        const success = input.success !== false;
        const body = str(input, 'result').trim();
        const text = `${body}\n\n${success ? 'DONE' : 'FAILED: reported by the worker'}\n`;
        await mkdir(dirname(ctx.resultFile), { recursive: true });
        await writeFile(ctx.resultFile, text, 'utf8');
        return { content: 'Result written.', stop: true };
      },
    },
  ];
}

// ---------------------------------------------------------------------------------------------
// Orchestrator tools

export interface SpawnInput {
  name: string;
  task: string;
  model?: string;
  paths: string[];
  done: string;
  /** false switches the knowledge search step off for this task. */
  brain?: boolean;
}

export interface WorkbenchApi {
  spawn(input: SpawnInput, origin: string): Promise<{ runId: string; model: string; resultFile: string }>;
  describeRuns(): Promise<string>;
  describeModels(): Promise<string>;
  readRun(runId: string): Promise<string>;
}

function asPaths(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.map(String).map((s) => s.trim()).filter(Boolean);
  }
  if (typeof value === 'string') {
    return value.split(',').map((s) => s.trim()).filter(Boolean);
  }
  return [];
}

export function spawnInputFrom(input: Record<string, unknown>): SpawnInput {
  return {
    name: str(input, 'name') || 'worker',
    task: str(input, 'task'),
    model: str(input, 'model') || undefined,
    paths: asPaths(input.paths),
    done: str(input, 'done'),
    brain: input.brain === false || input.brain === 'false' ? false : undefined,
  };
}

export function orchestratorTools(api: WorkbenchApi, brain: Brain | undefined, skillsDir: string, origin: string): ToolHandler[] {
  return [
    {
      spec: {
        name: 'spawn_worker',
        description:
          'Start a worker for a delegated, clearly scoped task. It writes a result file. Returns the run id. ' +
          'Give a complete task, exclusive paths, and a checkable done criterion.',
        parameters: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            task: { type: 'string' },
            model: { type: 'string', description: 'Model id from list_workers; omit for the default.' },
            paths: { type: 'array', items: { type: 'string' } },
            done: { type: 'string' },
            brain: { type: 'boolean', description: 'false: the worker must not search the brain.' },
          },
          required: ['name', 'task'],
        },
      },
      async run(input) {
        const spawn = spawnInputFrom(input);
        if (!spawn.task.trim()) {
          return { content: 'Error: task is empty.' };
        }
        const r = await api.spawn(spawn, origin);
        return { content: `Started run ${r.runId} with ${r.model}. Result file: ${r.resultFile}` };
      },
    },
    {
      spec: {
        name: 'list_workers',
        description: 'List worker runs with status, and the models available for workers.',
        parameters: { type: 'object', properties: {} },
      },
      async run() {
        return { content: `${await api.describeRuns()}\n\n${await api.describeModels()}` };
      },
    },
    {
      spec: {
        name: 'read_result',
        description: 'Read the status and result of a worker run.',
        parameters: { type: 'object', properties: { runId: { type: 'string' } }, required: ['runId'] },
      },
      async run(input) {
        return { content: await api.readRun(str(input, 'runId')) };
      },
    },
    ...(brain ? [brainTool(brain)] : []),
    skillTool(skillsDir),
  ];
}

/** Reads the start of a file, or undefined when it does not exist. */
export async function readIfExists(file: string, max = 100_000): Promise<string | undefined> {
  try {
    const s = await stat(file);
    if (!s.isFile()) {
      return undefined;
    }
    const text = await readFile(file, 'utf8');
    return text.length > max ? text.slice(0, max) : text;
  } catch {
    return undefined;
  }
}

