// Every instruction, skill, resource and kit path the extension references must exist
// (known live defect: generated instructions pointed at paths that did not exist).
import assert from 'node:assert/strict';
import { access, readdir, readFile, stat } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const EXT = fileURLToPath(new URL('..', import.meta.url));
const MODULE = join(EXT, '..');
const REPO_KIT = join(MODULE, '..', '..');
const pkg = JSON.parse(await readFile(join(EXT, 'package.json'), 'utf8'));
const settings = pkg.contributes.configuration.properties as Record<string, { default: unknown }>;

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

/** Maps an installed kit path (~/work/kit/...) to this checkout's kit/ folder. */
function inCheckout(path: string): string {
  assert.ok(path.startsWith('~/work/kit/'), `${path} is a kit path`);
  return join(REPO_KIT, path.slice('~/work/kit/'.length));
}

async function sourceFiles(dir: string): Promise<string[]> {
  const out: string[] = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === 'dist' || e.name.startsWith('.vscode-test')) {
      continue;
    }
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      out.push(...(await sourceFiles(p)));
    } else if (/\.(ts|md|sh|json|mjs)$/.test(e.name) || e.name === 'kit-wb') {
      out.push(p);
    }
  }
  return out;
}

test('default rules file and data classes exist in the kit', async () => {
  const rules = settings['kitWorkbench.rulesFile'].default as string;
  assert.ok(await exists(inCheckout(rules)), `${rules} -> ${inCheckout(rules)}`);
  const src = await readFile(join(EXT, 'src/workbench.ts'), 'utf8');
  for (const m of src.matchAll(/'(~\/work\/kit\/[^']+)'/g)) {
    assert.ok(await exists(inCheckout(m[1])), `${m[1]} referenced in workbench.ts`);
  }
});

test('the skills directory is the one 30-agent-setup installs', async () => {
  assert.equal(settings['kitWorkbench.skillsDir'].default, '~/.agents/skills');
  const kitSync = await readFile(join(REPO_KIT, 'modules/30-agent-setup/kit-sync'), 'utf8');
  assert.match(kitSync, /\.agents\/skills/);
  assert.ok((await stat(join(REPO_KIT, 'modules/30-agent-setup/source/skills'))).isDirectory());
});

test('skills named in prompts and guides exist in 30-agent-setup', async () => {
  const skills = new Set(await readdir(join(REPO_KIT, 'modules/30-agent-setup/source/skills')));
  for (const file of await sourceFiles(EXT)) {
    const text = await readFile(file, 'utf8');
    for (const m of text.matchAll(/skill[s]?\/([a-z0-9-]+)\/SKILL\.md/g)) {
      assert.ok(skills.has(m[1]), `${relative(MODULE, file)} names skill ${m[1]}`);
    }
  }
});

test('resources the extension loads at run time are packaged', async () => {
  for (const rel of ['resources/orchestrator.md', 'resources/bin/kit-wb', 'resources/templates/code-review.md', pkg.contributes.viewsContainers.activitybar[0].icon]) {
    assert.ok(await exists(join(EXT, rel)), rel);
  }
  const ignore = await readFile(join(EXT, '.vscodeignore'), 'utf8');
  assert.doesNotMatch(ignore, /^resources/m);
  assert.ok(((await stat(join(EXT, 'resources/bin/kit-wb'))).mode & 0o111) !== 0, 'kit-wb is executable');
});

test('skills named by task templates exist in 30-agent-setup', async () => {
  const skills = new Set(await readdir(join(REPO_KIT, 'modules/30-agent-setup/source/skills')));
  const dir = join(EXT, 'resources/templates');
  for (const file of await readdir(dir)) {
    const m = /^skill:\s*(\S+)/m.exec(await readFile(join(dir, file), 'utf8'));
    if (m) {
      assert.ok(skills.has(m[1]), `template ${file} names skill ${m[1]}`);
    }
  }
});

test('the data classes path is the one 40-data-guard installs', async () => {
  const src = await readFile(join(EXT, 'src/workbench.ts'), 'utf8');
  assert.match(src, /'~\/\.config\/work-kit\/data-classes\.md'/);
  const install = await readFile(join(REPO_KIT, 'modules/40-data-guard/install.sh'), 'utf8');
  assert.match(install, /"\$CONF_DIR\/data-classes\.md"/);
  assert.match(await readFile(join(REPO_KIT, 'modules/40-data-guard/data-guard'), 'utf8'), /work-kit\}?/);
});

test('every command a view, card or menu calls is contributed', async () => {
  const contributed = new Set((pkg.contributes.commands as { command: string }[]).map((c) => c.command));
  const views = await readFile(join(EXT, 'src/views.ts'), 'utf8');
  for (const m of views.matchAll(/'(kitWorkbench\.[A-Za-z]+)'/g)) {
    assert.ok(contributed.has(m[1]) || m[1].startsWith('kitWorkbench.overview') || m[1] === 'kitWorkbench.result', `views.ts calls ${m[1]}`);
  }
  for (const items of Object.values(pkg.contributes.menus as Record<string, { command: string }[]>)) {
    for (const item of items) {
      assert.ok(contributed.has(item.command), `menu entry ${item.command}`);
    }
  }
});

test('every contributed command is registered in extension.ts and vice versa', async () => {
  const src = await readFile(join(EXT, 'src/extension.ts'), 'utf8');
  const registered = new Set([...src.matchAll(/command\('(kitWorkbench\.[A-Za-z]+)'/g)].map((m) => m[1]));
  const contributed = new Set((pkg.contributes.commands as { command: string }[]).map((c) => c.command));
  assert.deepEqual([...contributed].sort(), [...registered].sort());
  const tools = new Set([...src.matchAll(/'(kit_[a-z_]+)'/g)].map((m) => m[1]));
  for (const t of pkg.contributes.languageModelTools as { name: string }[]) {
    assert.ok(tools.has(t.name), `tool ${t.name} registered`);
  }
});

test('no private setup references or personal data in the module', async () => {
  const banned = new RegExp([
    'werkbank', 'll' + 'pc', 'sync' + 'thing', 'skr' + 'yx', 'lille' + 'bor',
    'avi' + 'sion', '/Users/', '90-secrets', 'knowledge vault', 'wb-state', 'wb-spawn',
  ].join('|'), 'i');
  for (const file of [...(await sourceFiles(MODULE))]) {
    if (file.endsWith('package-lock.json') || file.endsWith('paths.test.ts')) {
      continue;
    }
    const text = await readFile(file, 'utf8');
    const hit = banned.exec(text);
    assert.equal(hit, null, `${relative(MODULE, file)}: ${hit?.[0]}`);
  }
});
