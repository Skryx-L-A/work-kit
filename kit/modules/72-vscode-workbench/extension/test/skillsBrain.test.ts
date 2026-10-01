import assert from 'node:assert/strict';
import { chmod, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';
import { Brain, BRAIN_MISSING, findExecutable, type Exec } from '../src/brain.ts';
import { listSkills, parseFrontmatter, readSkill, skillIndex } from '../src/skills.ts';
import { tempDir } from './helpers.ts';

test('frontmatter: plain, quoted and folded values', () => {
  const fm = parseFrontmatter('---\nname: brain\ndescription: >\n  Search notes.\n  Not for secrets.\nother: "quoted: yes"\n---\nbody');
  assert.deepEqual(fm, { name: 'brain', description: 'Search notes. Not for secrets.', other: 'quoted: yes' });
  assert.deepEqual(parseFrontmatter('no frontmatter'), {});
});

test('skills are listed from SKILL.md folders', async () => {
  const dir = await tempDir();
  await mkdir(join(dir, 'b-skill'));
  await writeFile(join(dir, 'b-skill/SKILL.md'), '---\nname: b-skill\ndescription: Does B.\n---\n# B\n');
  await mkdir(join(dir, 'a-skill'));
  await writeFile(join(dir, 'a-skill/SKILL.md'), '---\ndescription: Does A.\n---\n');
  await mkdir(join(dir, 'not-a-skill'));
  const skills = await listSkills(dir);
  assert.deepEqual(skills.map((s) => s.name), ['a-skill', 'b-skill']);
  assert.equal(skillIndex(skills), '- a-skill: Does A.\n- b-skill: Does B.');
  assert.match((await readSkill(dir, 'b-skill')) ?? '', /# B/);
  assert.equal(await readSkill(dir, 'missing'), undefined);
  assert.deepEqual(await listSkills(join(dir, 'nope')), []);
  assert.equal(skillIndex([]), 'No skills installed.');
});

test('brain: missing CLI degrades to a message', async () => {
  const brain = new Brain('/nonexistent/brain');
  assert.equal(await brain.available(), undefined);
  assert.equal(await brain.search('x'), BRAIN_MISSING);
});

test('brain: search passes query and clamps k; failures are reported', async () => {
  const dir = await tempDir();
  const bin = join(dir, 'brain');
  await writeFile(bin, '#!/bin/sh\necho ok\n');
  await chmod(bin, 0o755);
  assert.equal(await findExecutable('brain', dir), bin);
  const seen: string[][] = [];
  const exec: Exec = async (_cmd, args) => {
    seen.push(args);
    if (args[0] === 'read') {
      throw Object.assign(new Error('exit 1'), { stderr: 'no such note' });
    }
    return { stdout: 'hit 1\n', stderr: '' };
  };
  const brain = new Brain(bin, exec);
  assert.equal(await brain.search('legacy cobol', 99), 'hit 1');
  assert.deepEqual(seen[0], ['search', 'legacy cobol', '-k', '20']);
  assert.equal(await brain.read('x'), 'brain read failed: no such note');
});

test('brain: real execution of a stub CLI', async () => {
  const dir = await tempDir();
  const bin = join(dir, 'brain');
  await writeFile(bin, '#!/bin/sh\necho "args: $*"\n');
  await chmod(bin, 0o755);
  assert.equal(await new Brain(bin).search('q', 3), 'args: search q -k 3');
});
