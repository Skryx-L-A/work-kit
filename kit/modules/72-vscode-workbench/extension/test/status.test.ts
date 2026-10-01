import assert from 'node:assert/strict';
import { test } from 'node:test';
import { statusItems, statusSummary, type StatusFacts } from '../src/status.ts';

const base: StatusFacts = {
  brainBinary: '/bin/brain',
  brainEnabled: true,
  brainStatus: 'notes: 12\nindex: fresh',
  skillsDir: '/skills',
  skillCount: 3,
  rulesSource: '/w/AGENTS.md',
  rulesIsProject: true,
  dataGuardBinary: '/bin/data-guard',
  dataGuardStatus: 'gitleaks:    /bin/gitleaks\ndeny-list:   /c/deny (2 active patterns)',
  dataClassesFile: '/c/data-classes.md',
  confirmCloud: true,
  registryFile: '/c/models.json',
  registryExists: true,
  modelCounts: { ready: 2, total: 5, lm: 1 },
  kitWbOnPath: '/bin/kit-wb',
  workerAutonomy: false,
};

function level(f: StatusFacts, id: string) {
  return statusItems(f).find((i) => i.id === id)?.level;
}

test('all modules present: every item ok', () => {
  const items = statusItems(base);
  assert.deepEqual(items.map((i) => i.id), ['brain', 'skills', 'rules', 'dataGuard', 'models', 'kitWb', 'autonomy']);
  assert.ok(items.every((i) => i.level === 'ok'), JSON.stringify(items.filter((i) => i.level !== 'ok')));
  assert.match(statusSummary(items), /Skills: 3 installed/);
  assert.ok(items[0].more?.includes('index: fresh'));
});

test('missing optional modules degrade to missing, never to an error', () => {
  const f = { ...base, brainBinary: undefined, skillCount: 0, dataGuardBinary: undefined, dataGuardStatus: undefined, rulesSource: undefined };
  assert.equal(level(f, 'brain'), 'missing');
  assert.equal(level(f, 'skills'), 'missing');
  assert.equal(level(f, 'dataGuard'), 'missing');
  assert.equal(level(f, 'rules'), 'warn');
});

test('switches and risks are visible', () => {
  assert.equal(level({ ...base, brainEnabled: false }, 'brain'), 'off');
  assert.equal(level({ ...base, brainStatus: 'brain status failed: no index' }, 'brain'), 'warn');
  assert.equal(level({ ...base, confirmCloud: false }, 'dataGuard'), 'warn');
  assert.equal(level({ ...base, dataGuardBinary: undefined, confirmCloud: false }, 'dataGuard'), 'warn');
  assert.equal(level({ ...base, dataGuardStatus: 'gitleaks:    NOT FOUND' }, 'dataGuard'), 'warn');
  assert.equal(level({ ...base, workerAutonomy: true }, 'autonomy'), 'warn');
  assert.equal(level({ ...base, modelCounts: { ready: 0, total: 4, lm: 0 } }, 'models'), 'warn');
  assert.equal(level({ ...base, kitWbOnPath: undefined }, 'kitWb'), 'off');
});
