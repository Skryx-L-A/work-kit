// Skills from ~/.agents/skills/<name>/SKILL.md (agentskills.io format). Pure module.
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

export interface Skill {
  name: string;
  description: string;
  file: string;
}

/** Minimal frontmatter reader: `key: value`, quoted values, and `>`/`|` blocks. */
export function parseFrontmatter(text: string): Record<string, string> {
  const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
  if (!m) {
    return {};
  }
  const out: Record<string, string> = {};
  const lines = m[1].split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const kv = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(lines[i]);
    if (!kv) {
      continue;
    }
    let value = kv[2].trim();
    if (/^[>|][-+]?$/.test(value)) {
      const block: string[] = [];
      while (i + 1 < lines.length && (/^\s+\S/.test(lines[i + 1]) || lines[i + 1].trim() === '')) {
        block.push(lines[++i].trim());
      }
      value = block.join(value.startsWith('|') ? '\n' : ' ').trim();
    } else if (/^(['"]).*\1$/.test(value)) {
      value = value.slice(1, -1);
    }
    out[kv[1]] = value;
  }
  return out;
}

export async function listSkills(dir: string): Promise<Skill[]> {
  let entries: string[];
  try {
    entries = await readdir(dir);
  } catch {
    return [];
  }
  const skills: Skill[] = [];
  for (const entry of entries.sort()) {
    const file = join(dir, entry, 'SKILL.md');
    try {
      const fm = parseFrontmatter(await readFile(file, 'utf8'));
      skills.push({ name: fm.name || entry, description: fm.description || '', file });
    } catch {
      // Not a skill folder.
    }
  }
  return skills;
}

export function skillIndex(skills: readonly Skill[]): string {
  if (skills.length === 0) {
    return 'No skills installed.';
  }
  return skills.map((s) => `- ${s.name}: ${s.description}`).join('\n');
}

export async function readSkill(dir: string, name: string): Promise<string | undefined> {
  const skill = (await listSkills(dir)).find((s) => s.name === name);
  if (!skill) {
    return undefined;
  }
  return readFile(skill.file, 'utf8');
}
