import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { WorkerLayout } from '../src/settings.ts';
import { workerViewCommand } from '../src/terminal.ts';
import { viewSessionName } from '../src/tmux.ts';
import {
  AUTO_REOPEN_MAX_ATTEMPTS,
  AUTO_REOPEN_WINDOW_MS,
  type ExistingWorkerTab,
  HINT_COOLDOWN_MS,
  hintMessage,
  overflowWorkerTerminalName,
  planReopen,
  PRIMARY_WORKER_WINDOW,
  regridCommand,
  type ReopenThrottle,
  resolveWorkerTabState,
  shouldHintWorkerTab,
  syncLayout,
  syncOverflowWorkerTabs,
  workerTabAction,
} from '../src/workerTab.ts';

test('switching to "window" opens the tab, switching back closes it', () => {
  assert.equal(workerTabAction('window', 'none'), 'open');
  assert.equal(workerTabAction('window', 'live'), 'none', 'a live tab stays as it is');
  // a tab VSCode restored across a reload shows nothing — it gets replaced
  assert.equal(workerTabAction('window', 'ghost'), 'open');
  // after wb-grid pulled the panes back, the workers window is gone — no tab
  // pointing at it may survive, not even a dead one
  assert.equal(workerTabAction('split', 'live'), 'close');
  assert.equal(workerTabAction('split', 'ghost'), 'close');
  assert.equal(workerTabAction('split', 'none'), 'none');
});

// Fixture for a tab this host created for `attachedTo`, still running.
const ownTab = (attachedTo: string | undefined): ExistingWorkerTab => (
  { createdByUs: true, exited: false, attachedTo }
);

test('resolveWorkerTabState: right session, alive -> live', () => {
  assert.equal(resolveWorkerTabState(ownTab('wb-foo-1a2b3c'), 'wb-foo-1a2b3c', true), 'live');
});

test('resolveWorkerTabState: wrong session -> ghost, even if that session is alive', () => {
  // the exact bug this function exists for: a tab left attached to a session
  // that this window no longer wants (wb-session-delete, a session key change,
  // a restart) looked exactly like a healthy tab before this check existed.
  assert.equal(resolveWorkerTabState(ownTab('wb-foo-OLD'), 'wb-foo-NEW', true), 'ghost');
});

test('resolveWorkerTabState: right session, but it no longer exists -> ghost', () => {
  // attachedTo matches wanted, yet the session itself is gone (tmux restart,
  // the folder's session was deleted) — a stored name that outlived what it
  // named, same failure family as wb-doctor's six 2026-08-04 structure bugs.
  assert.equal(resolveWorkerTabState(ownTab('wb-foo-1a2b3c'), 'wb-foo-1a2b3c', false), 'ghost');
});

test('resolveWorkerTabState: no tab -> none', () => {
  assert.equal(resolveWorkerTabState(undefined, 'wb-foo-1a2b3c', true), 'none');
});

test('resolveWorkerTabState: a foreign tab (not in ownTerminals) -> ghost', () => {
  const foreign: ExistingWorkerTab = { createdByUs: false, exited: false, attachedTo: 'wb-foo-1a2b3c' };
  assert.equal(resolveWorkerTabState(foreign, 'wb-foo-1a2b3c', true), 'ghost');
});

test('resolveWorkerTabState: an exited tab -> ghost, even on the right session', () => {
  const exited: ExistingWorkerTab = { createdByUs: true, exited: true, attachedTo: 'wb-foo-1a2b3c' };
  assert.equal(resolveWorkerTabState(exited, 'wb-foo-1a2b3c', true), 'ghost');
});

test('resolveWorkerTabState: wanted undefined (remote window) falls back to createdByUs/exited alone', () => {
  // host2 windows cannot ask their local tmux about a session that lives on the
  // other machine — session identity is not checkable there, so this must not
  // regress remote windows to always-ghost.
  assert.equal(resolveWorkerTabState(ownTab('wb-foo-anything'), undefined, false), 'live');
  const exited: ExistingWorkerTab = { createdByUs: true, exited: true, attachedTo: undefined };
  assert.equal(resolveWorkerTabState(exited, undefined, false), 'ghost');
  const foreign: ExistingWorkerTab = { createdByUs: false, exited: false, attachedTo: undefined };
  assert.equal(resolveWorkerTabState(foreign, undefined, false), 'ghost');
});

test('a missing tab while workers run leads to the hint', () => {
  const now = 1_000_000;
  // the real incident: four workers in the workers window, no tab, no sign of them
  assert.equal(shouldHintWorkerTab('window', 'none', 4, undefined, now), true);
  assert.equal(shouldHintWorkerTab('window', 'ghost', 4, undefined, now), true, 'a ghost shows nothing');
  assert.equal(shouldHintWorkerTab('window', 'live', 4, undefined, now), false, 'tab is there');
  assert.equal(shouldHintWorkerTab('split', 'none', 4, undefined, now), false, 'split needs no tab');
  assert.equal(shouldHintWorkerTab('window', 'none', 0, undefined, now), false, 'nothing running');
});

test('the hint does not nag: once per cooldown', () => {
  const shown = 1_000_000;
  assert.equal(shouldHintWorkerTab('window', 'none', 2, shown, shown + 1000), false);
  assert.equal(shouldHintWorkerTab('window', 'none', 2, shown, shown + HINT_COOLDOWN_MS), true);
});

test('hintMessage names how many workers are hidden, without emoji', () => {
  assert.match(hintMessage(1), /^1 worker runs in their own worker tab/);
  assert.match(hintMessage(4), /^4 workers run in their own worker tab/);
  assert.ok(!/\p{Extended_Pictographic}/u.test(hintMessage(4)));
});

test('a live tab suppresses the hint regardless of which session it landed on', () => {
  // wb-worker-tab (2026-08-04) may attach the tab to the newest running session
  // of the same FOLDER when the window's own session has died (see
  // shell/tests/test-worker-tab.sh, "Fehler 4"). shouldHintWorkerTab only ever
  // sees the abstract 'live'/'ghost'/'none' state, never a session name — session
  // identity is deliberately out of scope here (checked instead where a *stale*
  // tab would be dangerous: showWorkerTerminal's own-session comparison before
  // revealing it). A regression that tried to make this function session-aware,
  // or one that dropped the fallback's promotion to 'live', would slip past every
  // other test in this file without this one.
  const now = 1_000_000;
  assert.equal(shouldHintWorkerTab('window', 'live', 4, undefined, now), false,
    'a tab attached via the same-folder fallback still counts as showing the workers');
});

test('the worker tab hands the whole attach to wb-worker-tab', () => {
  const session = 'wb-foo-1a2b3c';
  const command = workerViewCommand(session);
  // The tmux calls moved into the tool (shell/wb-worker-tab), where they can be
  // executed against a real server — see shell/tests/test-worker-tab.sh. What is
  // left here has to be exactly the handover, with no tmux of its own.
  assert.match(command, /exec wb-worker-tab 'wb-foo-1a2b3c'$/);
  assert.ok(!command.includes('new-session'), 'no session may be created from inside the extension');
  assert.ok(!command.includes('select-window'), 'window selection belongs to the tool');
  // The view session is derived by the tool; the extension names only the base.
  assert.equal(viewSessionName(session), 'wb-foo-1a2b3c-view');
});

test('a missing wb-worker-tab is said out loud, not swallowed', () => {
  // A tab that dies without a word is what made four running workers invisible.
  const command = workerViewCommand('wb-foo-1a2b3c');
  assert.match(command, /command -v wb-worker-tab/);
  assert.match(command, /wb-worker-tab is not on PATH/);
  assert.match(command, /exec "\$SHELL"/);
});

test('regridCommand hands wb-grid a pane of the session', () => {
  // wb-grid derives the session from the pane and moves panes for the CURRENT
  // setting — running workers survive the switch
  assert.equal(regridCommand('%12'), 'wb-grid %12');
});

test('a foreign settings change is adopted, and only once', () => {
  // window B still believes "split" while the file says "window"
  const first = syncLayout('split', 'window');
  assert.deepEqual(first, { apply: true, known: 'window' });
  // seeing the same value again does nothing — no regrid ping-pong
  assert.deepEqual(syncLayout(first.known, 'window'), { apply: false, known: 'window' });
});

test('overflowWorkerTerminalName numbers overflow tabs off the primary tab\'s own name', () => {
  const base = 'Claude Workbench — Worker';
  assert.equal(overflowWorkerTerminalName(base, 'workers-2'), 'Claude Workbench — Worker 2');
  assert.equal(overflowWorkerTerminalName(base, 'workers-11'), 'Claude Workbench — Worker 11');
  // the primary window itself, or anything unrecognised, falls back to the base
  // name unchanged rather than inventing a number
  assert.equal(overflowWorkerTerminalName(base, PRIMARY_WORKER_WINDOW), base);
  assert.equal(overflowWorkerTerminalName(base, '_wbhold'), base);
});

test('syncOverflowWorkerTabs opens a tab for a window that newly exists in tmux', () => {
  // the real incident this guards against: wb-grid opened 'workers-2' once a
  // 7th worker arrived, and nothing in the extension knew to show it
  const plan = syncOverflowWorkerTabs('window', ['workers', 'workers-2'], []);
  assert.deepEqual(plan, { toOpen: ['workers-2'], toClose: [] });
});

test('syncOverflowWorkerTabs closes a tab whose window wb-grid folded back away', () => {
  // rule 2 of the task that added this: a tab may never keep pointing at a
  // window that stopped existing (worker count dropped, wb-grid closed workers-2)
  const plan = syncOverflowWorkerTabs('window', ['workers'], ['workers-2']);
  assert.deepEqual(plan, { toOpen: [], toClose: ['workers-2'] });
});

test('syncOverflowWorkerTabs never touches the primary tab', () => {
  // 'workers' is governed by workerTabAction/shouldHintWorkerTab instead — a
  // periodic poll fighting over the SAME tab would race that flow
  assert.deepEqual(syncOverflowWorkerTabs('window', ['workers'], []), { toOpen: [], toClose: [] });
  assert.deepEqual(syncOverflowWorkerTabs('split', ['workers'], ['workers']), { toOpen: [], toClose: [] });
});

test('syncOverflowWorkerTabs closes every overflow tab on switching away from "window"', () => {
  const plan = syncOverflowWorkerTabs('split', [], ['workers-2', 'workers-3']);
  assert.deepEqual(plan, { toOpen: [], toClose: ['workers-2', 'workers-3'] });
});

test('syncOverflowWorkerTabs settles once open matches tmux: no-op', () => {
  const plan = syncOverflowWorkerTabs('window', ['workers', 'workers-2', 'workers-3'], ['workers-2', 'workers-3']);
  assert.deepEqual(plan, { toOpen: [], toClose: [] });
});

test('syncOverflowWorkerTabs handles several tabs opening and closing at once', () => {
  // workers-2 stays, workers-3 disappeared, workers-4 is new
  const plan = syncOverflowWorkerTabs('window', ['workers', 'workers-2', 'workers-4'], ['workers-2', 'workers-3']);
  assert.deepEqual(plan, { toOpen: ['workers-4'], toClose: ['workers-3'] });
});

test('two windows observing each other settle after one application each', () => {
  // both believe "split", the file says "window" (somebody switched it)
  let knownA: 'split' | 'window' = 'split';
  let knownB: 'split' | 'window' = 'split';
  const applied: string[] = [];
  for (let tick = 0; tick < 5; tick++) {
    const a = syncLayout(knownA, 'window');
    knownA = a.known;
    if (a.apply) applied.push('A');
    const b = syncLayout(knownB, 'window');
    knownB = b.known;
    if (b.apply) applied.push('B');
  }
  assert.deepEqual(applied, ['A', 'B'], 'each window regrids exactly once, then both are quiet');
});

test('planReopen starts a fresh burst on the first attempt', () => {
  const now = 1_000_000;
  const plan = planReopen(undefined, now);
  assert.deepEqual(plan, { reopen: true, next: { attempts: 1, windowStart: now } });
});

test('planReopen allows further attempts inside the window, counting them', () => {
  const start = 1_000_000;
  const throttle: ReopenThrottle = { attempts: 1, windowStart: start };
  const plan = planReopen(throttle, start + 1000, 3, 60_000);
  assert.deepEqual(plan, { reopen: true, next: { attempts: 2, windowStart: start } },
    'windowStart of the burst does not move — only the count grows');
});

test('planReopen refuses once the burst budget is spent', () => {
  const start = 1_000_000;
  const throttle: ReopenThrottle = { attempts: 3, windowStart: start };
  const plan = planReopen(throttle, start + 1000, 3, 60_000);
  assert.deepEqual(plan, { reopen: false, next: throttle },
    'the exhausted throttle is handed back unchanged, not reset');
});

test('planReopen resets once the window has fully elapsed, even after being spent', () => {
  const start = 1_000_000;
  const exhausted: ReopenThrottle = { attempts: 3, windowStart: start };
  // exactly windowMs later — the boundary itself counts as elapsed (>=)
  const plan = planReopen(exhausted, start + 60_000, 3, 60_000);
  assert.deepEqual(plan, { reopen: true, next: { attempts: 1, windowStart: start + 60_000 } },
    'a burst that used up its budget an hour ago must not block a brand new one');
});

test('planReopen: a real close loop — three quick reopens, then silence for the rest of the window', () => {
  // alice closes the tab six times, one poll tick (5s, the default
  // workerPollSeconds) apart — far inside the one-minute burst window.
  let throttle: ReopenThrottle | undefined;
  const start = 1_000_000;
  const results: boolean[] = [];
  for (let closeNumber = 0; closeNumber < 6; closeNumber++) {
    const now = start + closeNumber * 5000;
    const plan = planReopen(throttle, now, AUTO_REOPEN_MAX_ATTEMPTS, AUTO_REOPEN_WINDOW_MS);
    throttle = plan.next;
    results.push(plan.reopen);
  }
  assert.deepEqual(results, [true, true, true, false, false, false],
    'the first three closes get healed, the rest are left to the hint');
});

test('planReopen: the loop breaker lets go once alice actually stops closing it', () => {
  // Same six closes as above, but the last one arrives after the burst
  // window has fully elapsed — self-heal must not stay disabled forever.
  let throttle: ReopenThrottle | undefined;
  const start = 1_000_000;
  const closeTimes = [0, 5000, 10_000, 15_000, 20_000, AUTO_REOPEN_WINDOW_MS + 1000];
  const results: boolean[] = [];
  for (const offset of closeTimes) {
    const plan = planReopen(throttle, start + offset, AUTO_REOPEN_MAX_ATTEMPTS, AUTO_REOPEN_WINDOW_MS);
    throttle = plan.next;
    results.push(plan.reopen);
  }
  assert.deepEqual(results, [true, true, true, false, false, true],
    'the sixth close lands in a new window and gets healed again');
});

test(
  'overflow tabs on a layout switch: neither survive "window" -> "split" (a) nor '
  + 'reopen themselves while stuck on "split" (b) (Betriebslauf-Befund 2026-08-04)',
  () => {
    // Models the exact handshake applyWorkerTabAutoHeal drives in extension.ts
    // (extension.ts:950-996, called both from the poll loop and, synchronously,
    // at the end of a layout switch in applyWorkerLayout, extension.ts:1127)
    // between three pieces of state it owns: which overflow tabs THIS host has
    // open (openTabs, stands in for the module-level `overflowTerminals` Map),
    // their reopen budgets (throttles, stands in for `overflowReopenThrottle`),
    // and what tmux actually shows (tmuxWindows, stands in for
    // listWorkerTabWindows). syncOverflowWorkerTabs is the sole decision-maker
    // for open/close; nothing in this simulation reaches into extension.ts or
    // vscode — see the OPEN section of this task's result file for why the
    // remaining wiring (real vscode.Terminal objects, the real tmux calls, the
    // await-ordering between regrid() and this function) cannot be pulled out
    // into a pure function the same way.
    const openTabs = new Set<string>(['workers-2', 'workers-3']);
    const throttles = new Map<string, ReopenThrottle | undefined>();
    let now = 1_000_000;

    function tick(layout: WorkerLayout, tmuxWindows: string[]): void {
      const plan = syncOverflowWorkerTabs(layout, tmuxWindows, [...openTabs]);
      for (const w of plan.toClose) {
        openTabs.delete(w);
        // extension.ts:987 — a later window reusing the same name must start
        // with a clean budget, not the one left over from before the switch.
        throttles.delete(w);
      }
      for (const w of plan.toOpen) {
        const reopen = planReopen(throttles.get(w), now);
        throttles.set(w, reopen.next);
        if (reopen.reopen) {
          openTabs.add(w);
        }
      }
    }

    // wb-grid has already folded workers-2/workers-3 back by the time this
    // runs (applyWorkerLayout awaits regrid() BEFORE calling
    // applyWorkerTabAutoHeal, extension.ts:1100 then :1127) — tmuxWindows is
    // empty. syncOverflowWorkerTabs's `layout !== 'window'` branch ignores
    // tmuxWindows entirely and closes every tracked tab regardless, so this
    // holds even if wb-grid had NOT finished yet (e.g. regrid skipped because
    // no orchestrator pane was found, extension.ts:1099).
    tick('split', []);
    assert.deepEqual([...openTabs].sort(), [],
      '(a) excluded: no tab survives the switch to "split"');

    // A later poll tick while still on "split" must not bring anything back —
    // this is failure mode (b), shaped like the wb-doctor point-4 regression
    // (Befund B5) named in the finding.
    now += 5000;
    tick('split', []);
    assert.deepEqual([...openTabs].sort(), [],
      '(b) excluded: nothing reopens on its own while layout stays "split"');

    // Task item 3, the reverse direction: switching straight back to "window"
    // with enough workers that wb-grid already opened workers-2 AND workers-3
    // during this SAME regrid — both must come back immediately, in the one
    // applyWorkerTabAutoHeal call the layout switch itself triggers, not on
    // some later poll tick.
    now += 5000;
    tick('window', ['workers', 'workers-2', 'workers-3']);
    assert.deepEqual([...openTabs].sort(), ['workers-2', 'workers-3'],
      'both overflow tabs reopen in the same tick that switched layout back');
  },
);
