import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseResult, section, taskBody } from '../src/results.ts';
import { renderTask } from '../src/runs.ts';

test('sections and the DONE marker', () => {
  const r = parseResult('intro\n\n## What\nwrote a file\n\n## Verified\nls shows it\n\n## Open\nnone\n\nDONE\n\n');
  assert.equal(r.outcome, 'done');
  assert.deepEqual(r.sections.map((s) => s.heading), ['', 'What', 'Verified', 'Open']);
  assert.equal(section(r, 'what'), 'wrote a file');
  assert.equal(section(r, 'Open'), 'none');
  assert.equal(section(r, 'Missing'), undefined);
});

test('FAILED marker and open results', () => {
  const failed = parseResult('## What\nhalf\n\nFAILED: step limit reached');
  assert.equal(failed.outcome, 'failed');
  assert.equal(failed.failure, 'step limit reached');
  assert.equal(section(failed, 'What'), 'half');
  const open = parseResult('## What\nstill writing');
  assert.equal(open.outcome, 'open');
  assert.equal(parseResult('').sections.length, 0);
});

test('taskBody recovers the original task from task.md', () => {
  const task = 'Update the README.\n\nKeep the tone.';
  const md = renderTask({ name: 'docs', task, paths: ['README.md'], done: 'ok', cwd: '/w', resultFile: '/r.md', brain: true });
  assert.equal(taskBody(md), task);
  assert.equal(taskBody('plain text'), 'plain text');
});
