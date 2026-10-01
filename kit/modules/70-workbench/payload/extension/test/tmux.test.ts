import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import {
  baseSessionName,
  exact,
  hasSessionArgs,
  killSessionArgs,
  listPanesArgs,
  listWindowsArgs,
  listWorkerPanes,
  listWorkerTabWindows,
  parseRolePanes,
  parseWorkerPanes,
  statusFromError,
  parseWorkerTabWindows,
  pickOrchestrator,
  ROLE_FORMAT,
  sessionName,
  viewSessionName,
  workerTabNumber,
  WORKER_FORMAT,
} from '../src/tmux.ts';

const md5 = (value: string) => createHash('md5').update(value).digest('hex').slice(0, 6);

test('sessionName: wb-<sanitized basename>-<md5-6 of the full path>', () => {
  assert.equal(sessionName('/Users/alice/AI/foo'), `wb-foo-${md5('/Users/alice/AI/foo')}`);
});

test('sessionName replaces special characters instead of dropping them', () => {
  // my_app and my-app must not collapse onto the same session (review finding 3)
  const underscore = sessionName('/Users/alice/AI/my_app');
  const hyphen = sessionName('/Users/alice/AI/my-app');
  assert.match(underscore, /^wb-my-app-[0-9a-f]{6}$/);
  assert.match(hyphen, /^wb-my-app-[0-9a-f]{6}$/);
  assert.notEqual(underscore, hyphen);
});

test('sessionName keeps same-basename projects apart', () => {
  assert.notEqual(sessionName('/Users/alice/AI/foo'), sessionName('/Users/alice/work/foo'));
});

test('exact() anchors the session name against tmux prefix matching', () => {
  assert.equal(exact('wb-Vox'), '=wb-Vox');
});

test('has-session is anchored against tmux prefix matching', () => {
  // '-t wb-Vox' would match a running 'wb-a project' — see review finding 1
  assert.deepEqual(hasSessionArgs('wb-Vox'), ['has-session', '-t', '=wb-Vox']);
});

test('pane listings ask the whole server and carry the session name', () => {
  // '=' does NOT anchor 'list-panes -s' (tmux 3.7b resolves it as a window
  // target and prefix-matches anyway), so the session is filtered in code.
  assert.deepEqual(listPanesArgs(WORKER_FORMAT), [
    'list-panes', '-a', '-F', '#{session_name}|#{pane_id}|#{@wb_worker}|#{pane_dead}',
  ]);
  assert.deepEqual(listPanesArgs(ROLE_FORMAT), [
    'list-panes', '-a', '-F', '#{session_name}|#{pane_id}|#{@wb_role}|#{pane_dead}',
  ]);
});

test('parseWorkerPanes reads pane_id / @wb_worker / pane_dead of the exact session', () => {
  const panes = parseWorkerPanes('wb-Vox|%3|builder|0\nwb-Vox|%7|reviewer|1\n', 'wb-Vox');
  assert.deepEqual(panes, [
    { paneId: '%3', worker: 'builder', dead: false },
    { paneId: '%7', worker: 'reviewer', dead: true },
  ]);
});

test('parseWorkerPanes ignores panes of a prefix-sharing session', () => {
  const out = 'wb-a project|%9|fremd|0\nwb-Vox|%3|builder|0\n';
  assert.deepEqual(parseWorkerPanes(out, 'wb-Vox'), [
    { paneId: '%3', worker: 'builder', dead: false },
  ]);
  assert.deepEqual(parseWorkerPanes(out, 'wb-a project'), [
    { paneId: '%9', worker: 'fremd', dead: false },
  ]);
});

test('parseWorkerPanes skips panes without @wb_worker', () => {
  assert.deepEqual(parseWorkerPanes('wb-foo|%1||0\nwb-foo|%2|builder|0\n', 'wb-foo'), [
    { paneId: '%2', worker: 'builder', dead: false },
  ]);
});

test('parseRolePanes reads pane_id / @wb_role / pane_dead of the exact session', () => {
  const out = 'wb-foolong|%9|orchestrator|0\nwb-foo|%1|orchestrator|0\nwb-foo|%2|worker|1\n\n';
  assert.deepEqual(parseRolePanes(out, 'wb-foo'), [
    { paneId: '%1', role: 'orchestrator', dead: false },
    { paneId: '%2', role: 'worker', dead: true },
  ]);
});

test('pickOrchestrator prefers the living pane and reports a dead one', () => {
  assert.deepEqual(
    pickOrchestrator([
      { paneId: '%1', role: 'orchestrator', dead: true },
      { paneId: '%4', role: 'orchestrator', dead: false },
      { paneId: '%2', role: 'worker', dead: false },
    ]),
    { status: 'ok', paneId: '%4' },
  );
  assert.deepEqual(
    pickOrchestrator([{ paneId: '%1', role: 'orchestrator', dead: true }]),
    { status: 'dead' },
  );
  assert.deepEqual(
    pickOrchestrator([{ paneId: '%2', role: 'worker', dead: false }]),
    { status: 'missing' },
  );
});

test('killSessionArgs anchors the view session (a group member, no window dies)', () => {
  assert.deepEqual(killSessionArgs(viewSessionName('wb-foo-1a2b3c')), [
    'kill-session', '-t', '=wb-foo-1a2b3c-view',
  ]);
});

test('baseSessionName strips every -view suffix', () => {
  // Measured 2026-08-04: 'wb-a project-view-view' and 'wb-a project-view-view-view'
  // stood in the live server, three links showing the same windows, because a
  // view had been used as the base of another view.
  assert.equal(baseSessionName('wb-a project-8932bc'), 'wb-a project-8932bc');
  assert.equal(baseSessionName('wb-a project-8932bc-view'), 'wb-a project-8932bc');
  assert.equal(baseSessionName('wb-a project-8932bc-view-view-view'), 'wb-a project-8932bc');
});

test('a view name never grows another view', () => {
  assert.equal(viewSessionName('wb-foo-1a2b3c'), 'wb-foo-1a2b3c-view');
  assert.equal(viewSessionName('wb-foo-1a2b3c-view'), 'wb-foo-1a2b3c-view');
  assert.equal(viewSessionName('wb-foo-1a2b3c-view-view'), 'wb-foo-1a2b3c-view');
});

test('listWindowsArgs anchors the session and asks only for window names', () => {
  assert.deepEqual(listWindowsArgs('wb-foo-1a2b3c'), [
    'list-windows', '-t', '=wb-foo-1a2b3c', '-F', '#{window_name}',
  ]);
});

test('workerTabNumber recognises workers/workers-N, rejects everything else', () => {
  assert.equal(workerTabNumber('workers'), 1);
  assert.equal(workerTabNumber('workers-2'), 2);
  assert.equal(workerTabNumber('workers-11'), 11);
  // not a worker-tab window at all — the placeholder/other windows this must ignore
  assert.equal(workerTabNumber('_wbhold'), undefined);
  assert.equal(workerTabNumber('main'), undefined);
  assert.equal(workerTabNumber('workers-'), undefined);
  assert.equal(workerTabNumber('workers-x'), undefined);
});

test('parseWorkerTabWindows keeps only worker-tab windows, ordered by tab number', () => {
  const out = 'main\nworkers-3\n_wbhold\nworkers\nworkers-2\n';
  assert.deepEqual(parseWorkerTabWindows(out), ['workers', 'workers-2', 'workers-3']);
});

test('parseWorkerTabWindows on an empty/missing session (no output) is an empty list', () => {
  assert.deepEqual(parseWorkerTabWindows(''), []);
});

test('a missing tmux binary is not the same answer as a missing session', () => {
  // Measured 2026-08-04: hasSession swallowed every error alike, so "tmux is not
  // on this PATH" and "that session has ended" arrived as the same false — and
  // the restore path drew the wrong conclusion in silence either way.
  const notFound = Object.assign(new Error('spawn tmux ENOENT'), { code: 'ENOENT' });
  assert.equal(statusFromError(notFound), 'unavailable');
  // tmux answering "can't find session" exits 1
  assert.equal(statusFromError(Object.assign(new Error("can't find session"), { code: 1 })), 'missing');
  assert.equal(statusFromError(undefined), 'missing');
});

// --- Failure-case tests for runQuiet (2026-09-03, Audit "tmux-Aufrufe ohne Frist") -
//
// A fake `tmux` on PATH so a real failure/hang is exercised end to end, instead of
// only asserting against a hand-built error object. Put in front of the real PATH,
// removed again in `finally` — the two tests below run sequentially (this file's
// tests are not marked concurrent), so no other test sees the fake binary.
function withFakeTmux(script: string, body: () => Promise<void>): Promise<void> {
  const dir = mkdtempSync(join(tmpdir(), 'wb-fake-tmux-'));
  const bin = join(dir, 'tmux');
  writeFileSync(bin, `#!/bin/bash\n${script}\n`);
  chmodSync(bin, 0o755);
  const before = process.env.PATH;
  process.env.PATH = `${dir}:${before ?? ''}`;
  return body().finally(() => {
    process.env.PATH = before;
    rmSync(dir, { recursive: true, force: true });
  });
}

function captureConsoleErrors(): { errors: string[]; restore: () => void } {
  const errors: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => { errors.push(args.map(String).join(' ')); };
  return { errors, restore: () => { console.error = original; } };
}

test('a failing tmux does not become a false empty list, silently', async () => {
  const { errors, restore } = captureConsoleErrors();
  try {
    await withFakeTmux('echo "boom" >&2; exit 1', async () => {
      const started = Date.now();
      const { panes, ok } = await listWorkerPanes('wb-foo');
      // A plain non-zero exit is not a timeout — this must come back almost
      // immediately, not anywhere near the 5s configured timeout.
      assert.ok(Date.now() - started < 2000, 'a failing tmux must not take long to report');
      assert.deepEqual(panes, [], 'the empty-on-failure fallback stays unchanged');
      assert.equal(ok, false, 'a failure must be distinguishable from a genuinely empty list');
    });
  } finally {
    restore();
  }
  assert.ok(
    errors.some((e) => e.includes('tmux') && e.toLowerCase().includes('fail')),
    `the failure must be visible on the console, got: ${JSON.stringify(errors)}`,
  );
});

test('a hanging tmux is killed and the caller comes back in bounded time', { timeout: 10_000 }, async () => {
  const { errors, restore } = captureConsoleErrors();
  try {
    // Ignoring SIGTERM is the point: the Node default `killSignal` is SIGTERM,
    // which a child can simply not die to — measured in this house's main
    // process (app/src/main/sessions.ts) leaving spawnSync hanging past its
    // stated timeout for over two minutes. SIGKILL cannot be ignored, so a
    // fixed `run()` comes back at (or shortly after) its own 5s timeout
    // regardless of this trap; a regression to the old default would instead
    // run into this test's own 10s ceiling below and fail loudly.
    await withFakeTmux('trap "" TERM; sleep 30', async () => {
      const started = Date.now();
      const { windows, ok } = await listWorkerTabWindows('wb-foo');
      const elapsed = Date.now() - started;
      assert.ok(
        elapsed < 7000,
        `a hanging tmux must be killed well before its own 30s sleep ends, took ${elapsed}ms`,
      );
      assert.deepEqual(windows, []);
      assert.equal(ok, false);
    });
  } finally {
    restore();
  }
  assert.ok(errors.length > 0, 'a hang must also be visible on the console, not just bounded in time');
});
