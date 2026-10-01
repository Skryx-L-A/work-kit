import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { fillTemplate, listTemplates, parseTemplate, templateSpawn, templateVariables, variablesOf } from '../src/templates.ts';
import { tempDir } from './helpers.ts';

const BUILTIN = fileURLToPath(new URL('../resources/templates', import.meta.url));

test('frontmatter fields and body are read', () => {
  const t = parseTemplate('---\nname: review\ndescription: Review it\nmodel: m1\npaths: a/, b.md\ndone: all found\nbrain: false\nskill: code-review\n---\nReview {{target}}.\n', '/t.md', 'user', 'x');
  assert.ok(t);
  assert.equal(t.name, 'review');
  assert.equal(t.model, 'm1');
  assert.deepEqual(t.paths, ['a/', 'b.md']);
  assert.equal(t.done, 'all found');
  assert.equal(t.brain, false);
  assert.equal(t.skill, 'code-review');
  assert.equal(t.body, 'Review {{target}}.');
});

test('a template without a body is ignored; the file name is the fallback name', () => {
  assert.equal(parseTemplate('---\nname: empty\n---\n', '/e.md', 'user', 'e'), undefined);
  assert.equal(parseTemplate('Just a task.', '/plain.md', 'user', 'plain')?.name, 'plain');
});

test('variables are found once, in order, and filled; unknown ones stay', () => {
  assert.deepEqual(templateVariables('{{a}} {{ b }} {{a}} {{c-d}}'), ['a', 'b', 'c-d']);
  assert.equal(fillTemplate('{{a}} and {{b}}', { a: 'x' }), 'x and {{b}}');
});

test('templateSpawn fills body, paths and done, and names the skill', () => {
  const t = parseTemplate('---\nname: docs\npaths: {{docs}}\ndone: {{docs}} checked\nskill: technical-writing\n---\nUpdate {{docs}}.', '/d.md', 'builtin', 'docs')!;
  assert.deepEqual(variablesOf(t), ['docs']);
  const s = templateSpawn(t, { docs: 'README.md' });
  assert.equal(s.name, 'docs');
  assert.deepEqual(s.paths, ['README.md']);
  assert.equal(s.done, 'README.md checked');
  assert.match(s.task, /^Update README\.md\./);
  assert.match(s.task, /skill `technical-writing`/);
  assert.equal(templateSpawn(t, { docs: 'x' }, 'my-name').name, 'my-name');
});

test('user templates replace built-ins of the same name', async () => {
  const dir = await tempDir();
  const builtin = join(dir, 'builtin');
  const user = join(dir, 'user');
  await mkdir(builtin);
  await mkdir(user);
  await writeFile(join(builtin, 'a.md'), '---\nname: a\n---\nbuilt-in a');
  await writeFile(join(builtin, 'b.md'), '---\nname: b\n---\nbuilt-in b');
  await writeFile(join(user, 'a.md'), '---\nname: a\n---\nmy a');
  await writeFile(join(user, 'notes.txt'), 'not a template');
  const list = await listTemplates(builtin, user);
  assert.deepEqual(list.map((t) => `${t.name}:${t.source}:${t.body}`), ['a:user:my a', 'b:builtin:built-in b']);
  assert.deepEqual((await listTemplates(join(dir, 'none'), join(dir, 'none2'))), []);
});

test('built-in templates parse, have a description and a done criterion', async () => {
  const list = await listTemplates(BUILTIN, '/nonexistent');
  assert.ok(list.length >= 5, `${list.length} built-in templates`);
  for (const t of list) {
    assert.ok(t.description, `${t.name} has a description`);
    assert.ok(t.done, `${t.name} has a done criterion`);
    assert.ok(variablesOf(t).length > 0, `${t.name} asks for at least one value`);
  }
});
