// Task templates: Markdown files with frontmatter that prefill a worker spawn. Pure module.
//
//   ---
//   name: code-review
//   description: Review a change for correctness and risk
//   model: claude-sonnet          (optional: default worker model when empty)
//   paths: review/                (optional, comma separated)
//   done: review/REVIEW.md lists every finding with file:line
//   brain: false                  (optional: switch the knowledge search step off)
//   skill: code-review            (optional: skill the worker reads first)
//   ---
//   Review {{target}} ...          ({{variable}} values are asked for at spawn time)
//
// Built-in templates ship in resources/templates; files in the user templates folder with the
// same name win.
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parseFrontmatter } from './skills.ts';

export interface TaskTemplate {
  name: string;
  description: string;
  model?: string;
  paths: string[];
  done: string;
  brain?: boolean;
  skill?: string;
  body: string;
  file: string;
  source: 'builtin' | 'user';
}

const VARIABLE = /\{\{\s*([a-zA-Z][a-zA-Z0-9_-]*)\s*\}\}/g;

function splitList(value: string | undefined): string[] {
  return (value ?? '').split(',').map((s) => s.trim()).filter(Boolean);
}

export function parseTemplate(text: string, file: string, source: TaskTemplate['source'], fallbackName: string): TaskTemplate | undefined {
  const fm = parseFrontmatter(text);
  const body = text.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, '').trim();
  if (!body) {
    return undefined;
  }
  return {
    name: fm.name || fallbackName,
    description: fm.description || '',
    model: fm.model || undefined,
    paths: splitList(fm.paths),
    done: fm.done || '',
    brain: fm.brain === 'false' ? false : undefined,
    skill: fm.skill || undefined,
    body,
    file,
    source,
  };
}

async function readDir(dir: string, source: TaskTemplate['source']): Promise<TaskTemplate[]> {
  let entries: string[];
  try {
    entries = await readdir(dir);
  } catch {
    return [];
  }
  const out: TaskTemplate[] = [];
  for (const entry of entries.filter((e) => e.endsWith('.md')).sort()) {
    const file = join(dir, entry);
    try {
      const t = parseTemplate(await readFile(file, 'utf8'), file, source, entry.replace(/\.md$/, ''));
      if (t) {
        out.push(t);
      }
    } catch {
      // Unreadable file: skip it, the others still count.
    }
  }
  return out;
}

/** Built-in and user templates; a user template replaces the built-in one of the same name. */
export async function listTemplates(builtinDir: string, userDir: string): Promise<TaskTemplate[]> {
  const byName = new Map<string, TaskTemplate>();
  for (const t of [...(await readDir(builtinDir, 'builtin')), ...(await readDir(userDir, 'user'))]) {
    byName.set(t.name, t);
  }
  return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name));
}

/** Variable names in order of first appearance. */
export function templateVariables(body: string): string[] {
  const seen: string[] = [];
  for (const m of body.matchAll(VARIABLE)) {
    if (!seen.includes(m[1])) {
      seen.push(m[1]);
    }
  }
  return seen;
}

/** Variables of a template's body, paths and done criterion. */
export function variablesOf(t: TaskTemplate): string[] {
  return templateVariables([t.body, ...t.paths, t.done].join('\n'));
}

export function fillTemplate(text: string, values: Record<string, string>): string {
  return text.replace(VARIABLE, (whole, name: string) => (name in values ? values[name] : whole));
}

/** The spawn input a template yields; variables fill the body, the paths and the done criterion. */
export function templateSpawn(t: TaskTemplate, values: Record<string, string>, name?: string) {
  const skillLine = t.skill ? `\n\nBefore you start, read the skill \`${t.skill}\` (read_skill tool, or its SKILL.md in the skills folder).` : '';
  return {
    name: name || t.name,
    task: fillTemplate(t.body, values) + skillLine,
    model: t.model,
    paths: t.paths.map((p) => fillTemplate(p, values)),
    done: fillTemplate(t.done, values),
    brain: t.brain,
  };
}
