import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  hasOrchestratorDescendant,
  isOrchestratorProcess,
  launchFailureMessage,
  launchOutcome,
  openPlan,
  orchestratorAttachCommand,
  orchestratorCommand,
  parseProcesses,
  restoreCandidates,
  restorePlan,
  shellStateOf,
  terminalPlan,
  workerViewCommand,
  sessionPrefix,
} from '../src/terminal.ts';
import { sessionName } from '../src/tmux.ts';

/** The real name derivation — the fallback when a folder has no state file. */
const derive = sessionName;

test('terminalPlan never launches wb-code in a live workbench terminal', () => {
  // that terminal sits in the orchestrator's Claude prompt — see review finding 6
  assert.equal(terminalPlan({ createdByUs: true, exited: false, liveness: 'alive' }), 'show');
  assert.equal(terminalPlan(undefined), 'launch');
});

test('terminalPlan relaunches for a terminal VSCode restored after the reload', () => {
  // same name, but not created by this extension host: wb-code is dead in there
  assert.equal(terminalPlan({ createdByUs: false, exited: false, liveness: 'alive' }), 'launch');
});

test('terminalPlan relaunches whenever liveness is not certain', () => {
  // an empty shell prompt is worse than a second tmux client (tmux is multi-client)
  assert.equal(terminalPlan({ createdByUs: true, exited: false, liveness: 'unknown' }), 'launch');
  assert.equal(terminalPlan({ createdByUs: true, exited: false, liveness: 'dead' }), 'launch');
  assert.equal(terminalPlan({ createdByUs: true, exited: true, liveness: 'alive' }), 'launch');
});

test('orchestratorCommand quotes dir and session id', () => {
  assert.equal(
    orchestratorCommand('/Users/alice/AI/foo'),
    `wb-code '/Users/alice/AI/foo'`,
  );
  assert.equal(
    orchestratorCommand('/Users/alice/AI/foo', { sessionId: 'abc-123' }),
    `wb-code '/Users/alice/AI/foo' --resume 'abc-123'`,
  );
  assert.equal(
    orchestratorCommand(`/tmp/it's`),
    `wb-code '/tmp/it'\\''s'`,
  );
});

test('orchestratorCommand passes session name and key (SPEC-V2 B)', () => {
  assert.equal(
    orchestratorCommand('/Users/alice/AI/foo', { name: 'Refactor', sessionKey: '9f2a1c' }),
    `wb-code '/Users/alice/AI/foo' --name 'Refactor' --key '9f2a1c'`,
  );
  assert.equal(
    orchestratorCommand('/Users/alice/AI/foo', {
      sessionId: 'abc-123',
      name: `Lil's Session`,
      sessionKey: '00beef',
    }),
    `wb-code '/Users/alice/AI/foo' --resume 'abc-123' --name 'Lil'\\''s Session' --key '00beef'`,
  );
  // the folder's default session has no key, and an empty name is left out
  assert.equal(
    orchestratorCommand('/Users/alice/AI/foo', { name: '' }),
    `wb-code '/Users/alice/AI/foo'`,
  );
});

test('workerViewCommand hands the attach to wb-worker-tab, with the BASE name', () => {
  // The tmux chain that used to stand here moved into shell/wb-worker-tab, where
  // shell/tests/test-worker-tab.sh runs it against a real server on its own
  // socket. Three of the four faults of 2026-08-04 lived in that untestable
  // chain; a string assertion could never have caught them.
  assert.equal(
    workerViewCommand('wb-foo-1a2b3c'),
    `command -v wb-worker-tab >/dev/null 2>&1 || { echo "wb-worker-tab is not on PATH — the worker tab cannot attach."; exec "$SHELL"; }; exec wb-worker-tab 'wb-foo-1a2b3c'`,
  );
});

test('workerViewCommand never passes a view name on as a base', () => {
  // Fault 2 of that night: the tab ran with the name of the VIEW, and tmux
  // grouped a view onto a view — 'wb-a project-view-view-view' stood in the live
  // server, three links showing the same windows.
  assert.match(workerViewCommand('wb-a project-view'), /exec wb-worker-tab 'wb-a project'$/);
  assert.match(workerViewCommand('wb-a project-view-view'), /exec wb-worker-tab 'wb-a project'$/);
});

test('workerViewCommand passes an overflow window through, but stays silent about the default', () => {
  // 'workers' is every existing caller's implicit target — the command must stay
  // byte-identical to before this parameter existed (checked above) whether the
  // caller now passes 'workers' explicitly or omits it.
  assert.equal(workerViewCommand('wb-foo-1a2b3c', 'workers'), workerViewCommand('wb-foo-1a2b3c'));
  assert.match(
    workerViewCommand('wb-foo-1a2b3c', 'workers-2'),
    /exec wb-worker-tab 'wb-foo-1a2b3c' --window 'workers-2'$/,
  );
});

test('sessionPrefix keeps the folder part and drops the session suffixes', () => {
  assert.equal(sessionPrefix('wb-AI'), 'wb-AI');
  assert.equal(sessionPrefix('wb-AI-c574d0'), 'wb-AI');
  assert.equal(sessionPrefix('wb-AI-c574d0-e8d13f'), 'wb-AI');
  assert.equal(sessionPrefix('wb-Minecraft-Shader-767130'), 'wb-Minecraft-Shader');
  // a folder whose own name looks like a suffix stays intact — the first two
  // parts are never dropped
  assert.equal(sessionPrefix('wb-abc123'), 'wb-abc123');
});

const PS = `
    1     0 /sbin/launchd
  500     1 /bin/zsh -il
  600   500 tmux attach -t =wb-scratch-abc123
  700     1 /bin/zsh -il
  800   700 /usr/bin/less README.md
`;

test('parseProcesses reads the ps columns', () => {
  const processes = parseProcesses(PS);
  assert.equal(processes.length, 5);
  assert.deepEqual(processes[2], {
    pid: 600,
    ppid: 500,
    command: 'tmux attach -t =wb-scratch-abc123',
  });
});

test('hasOrchestratorDescendant finds the tmux client under the shell', () => {
  const processes = parseProcesses(PS);
  assert.equal(hasOrchestratorDescendant(processes, 500), true);
  // the restored ghost terminal: a shell with nothing of ours below it
  assert.equal(hasOrchestratorDescendant(processes, 700), false);
});

test('hasOrchestratorDescendant looks deeper than the direct children', () => {
  const processes = parseProcesses(`
  900     1 /bin/zsh -il
  910   900 /bin/bash /Users/alice/.local/bin/wb-code /Users/alice/AI/x
  920   910 tmux attach -t =wb-x-1
`);
  assert.equal(hasOrchestratorDescendant(processes, 900), true);
});

test('hasOrchestratorDescendant does not match the shell itself', () => {
  // the terminal's own shell never counts as an attached orchestrator
  const processes = parseProcesses(`
  930     1 /bin/zsh -il claude
`);
  assert.equal(hasOrchestratorDescendant(processes, 930), false);
});

/**
 * Measured 2026-08-04 in alice's session, and reproduced on a test socket:
 * the restore path sends `exec tmux attach-session …`, so the tab's shell is
 * REPLACED by the tmux client and keeps its pid. Nothing hangs below that pid
 * any more. The tab was therefore read as 'idle', verifyTab concluded the
 * command had never arrived and sent it a second time — into a terminal that
 * was by then the tmux client, so the text appeared as a typed prompt in the
 * orchestrator's Claude pane.
 */
test('a tab that exec-replaced its shell with tmux counts as attached, not idle', () => {
  // ps as it really looked: pid 79617 was `zsh -il` before the exec, tmux after
  const processes = parseProcesses(`
79617 79616 tmux -L wbfenster attach-session -t =wb-testproj-live
`);
  assert.equal(shellStateOf(processes, 79617), 'attached');
  // and with that, the command is never sent a second time
  assert.equal(
    launchOutcome({ sessionAlive: true, shell: shellStateOf(processes, 79617), attempt: 1 }),
    'ok',
  );
});

test('only argv[0] may make a process itself the orchestrator', () => {
  // a login shell that merely carries the word in its arguments is not attached —
  // matching anywhere would turn every idle tab into an "attached" one
  assert.equal(isOrchestratorProcess('/bin/zsh -il claude'), false);
  assert.equal(shellStateOf(parseProcesses('\n 931 1 /bin/zsh -il claude\n'), 931), 'idle');
  assert.equal(isOrchestratorProcess('tmux attach-session -t =wb-AI'), true);
  assert.equal(isOrchestratorProcess('/opt/homebrew/bin/tmux attach -t =wb-AI'), true);
  assert.equal(isOrchestratorProcess('/Users/alice/.local/bin/wb-code /Users/alice/AI'), true);
});

test('a shell with a busy child is still not attached', () => {
  // unchanged behaviour: work running in the tab is 'busy', never 'attached'
  const processes = parseProcesses(`
  940     1 /bin/zsh -il
  941   940 npm run build
`);
  assert.equal(shellStateOf(processes, 940), 'busy');
});

test('restore: a live session brings the terminals back, a dead one does not', () => {
  const base = { hasFolder: true, sessionAlive: true, handledPending: false, layout: 'split' as const };
  assert.deepEqual(restorePlan(base), { orchestrator: true, workerTab: false });
  // workerLayout "window" restores BOTH tabs
  assert.deepEqual(restorePlan({ ...base, layout: 'window' }), { orchestrator: true, workerTab: true });
  // a session alice ended must not be resurrected by a reload
  assert.deepEqual(restorePlan({ ...base, sessionAlive: false }), { orchestrator: false, workerTab: false });
  assert.deepEqual(restorePlan({ ...base, hasFolder: false }), { orchestrator: false, workerTab: false });
});

test('restore does nothing when the launch path already ran (no double tab)', () => {
  assert.deepEqual(
    restorePlan({ hasFolder: true, sessionAlive: true, handledPending: true, layout: 'window' }),
    { orchestrator: false, workerTab: false },
  );
});

/**
 * The measured case of 2026-08-04: VSCode was quit and started fresh while the
 * folder's session 'wb-AI' ran on with six workers. The window still remembered
 * session key 'e8d13f' from the evening before, whose session had ended long
 * ago. Restore asked about that one session, got 'no', and left the window
 * empty. The live session must be found.
 */
const staleKeyStates = [
  { dir: '/Users/alice/AI', tmuxSession: 'wb-AI', lastActive: '2026-08-04T05:37:05Z' },
  {
    dir: '/Users/alice/AI',
    sessionKey: 'e8d13f',
    tmuxSession: 'wb-AI-c574d0-e8d13f',
    lastActive: '2026-08-03T19:10:46Z',
  },
  { dir: '/Users/alice/AI/a project', tmuxSession: 'wb-a project-1', lastActive: '2026-08-04T03:44:00Z' },
];

/** Stand-in for tmux: only 'wb-AI' answers, exactly as on the machine that day. */
const alive = (session: string): boolean => session === 'wb-AI';

test('a fresh window finds the live session even when its remembered key is dead', () => {
  const candidates = restoreCandidates('/Users/alice/AI', 'e8d13f', staleKeyStates, derive);
  // the remembered key is asked FIRST — a live keyed session keeps its window
  assert.deepEqual(candidates[0], { sessionKey: 'e8d13f', session: 'wb-AI-c574d0-e8d13f' });
  // …and the folder's other sessions follow, so the search does not end there
  assert.deepEqual(candidates.map((c) => c.session), ['wb-AI-c574d0-e8d13f', 'wb-AI']);
  // no session of another folder is ever a candidate
  assert.equal(candidates.some((c) => c.session === 'wb-a project-1'), false);

  const found = candidates.find((c) => alive(c.session));
  assert.deepEqual(found, { sessionKey: undefined, session: 'wb-AI' });
  // and with a live session found, the terminals come back
  assert.deepEqual(
    restorePlan({
      hasFolder: true,
      sessionAlive: found !== undefined,
      handledPending: false,
      layout: 'window',
    }),
    { orchestrator: true, workerTab: true },
  );
});

test('a live remembered session is kept — the newest session does not steal the window', () => {
  const candidates = restoreCandidates('/Users/alice/AI', 'e8d13f', staleKeyStates, derive);
  const found = candidates.find((c) => c.session === 'wb-AI-c574d0-e8d13f' || alive(c.session));
  assert.deepEqual(found, { sessionKey: 'e8d13f', session: 'wb-AI-c574d0-e8d13f' });
});

test('restoreCandidates falls back to the derived name and lists each session once', () => {
  // no state file at all: the name wb-code would have used is the only candidate
  assert.deepEqual(restoreCandidates('/Users/alice/AI', undefined, [], derive), [
    { sessionKey: undefined, session: 'wb-AI-c574d0' },
  ]);
  // the default session must not appear twice just because it is also the key
  assert.deepEqual(
    restoreCandidates('/Users/alice/AI', undefined, staleKeyStates, derive).map((c) => c.session),
    ['wb-AI', 'wb-AI-c574d0-e8d13f'],
  );
});

// ── Teil A: der Start wird geprueft, nicht angenommen ────────────────────────

test('a start that did not arrive is re-sent once, then reported', () => {
  // Measured 2026-08-04: the orchestrator tab got a '^C' before the shell had
  // finished its profile, the typed wb-code line was discarded, and the tab sat
  // at a bare prompt while the tmux session ran on unseen — in silence.
  const bare = { sessionAlive: false, shell: 'idle' as const };
  assert.equal(launchOutcome({ ...bare, attempt: 1 }), 'retry');
  assert.equal(launchOutcome({ ...bare, attempt: 2 }), 'report');
  // arrived: session there AND a tmux client under this tab's own shell
  assert.equal(
    launchOutcome({ sessionAlive: true, shell: 'attached', attempt: 1 }),
    'ok',
  );
});

test('a live session is not enough — the TAB has to be on it', () => {
  // Another window can keep the session alive while this tab shows a bare
  // prompt. That is precisely the state to catch, so it must not read as 'ok'.
  assert.equal(launchOutcome({ sessionAlive: true, shell: 'idle', attempt: 1 }), 'retry');
  assert.equal(launchOutcome({ sessionAlive: true, shell: 'idle', attempt: 2 }), 'report');
});

test('a busy shell is never typed into again', () => {
  // Text sent to a terminal whose foreground process does not read stdin waits
  // in the tty buffer — and wb-code ends in `exec tmux attach`, so tmux would
  // read it afterwards and type it into the orchestrator's Claude prompt. A
  // slow start is reported, never re-sent.
  assert.equal(launchOutcome({ sessionAlive: false, shell: 'busy', attempt: 1 }), 'report');
  assert.equal(launchOutcome({ sessionAlive: false, shell: 'unknown', attempt: 1 }), 'report');
});

test('shellStateOf tells a bare prompt apart from a busy shell', () => {
  const processes = parseProcesses(`
  500     1 /bin/zsh -il
  600   500 tmux attach -t =wb-scratch-abc123
  700     1 /bin/zsh -il
  800     1 /bin/zsh -il
  810   800 /usr/bin/python3 -c import venv
`);
  assert.equal(shellStateOf(processes, 500), 'attached');
  assert.equal(shellStateOf(processes, 700), 'idle');   // the '^C' aftermath
  assert.equal(shellStateOf(processes, 800), 'busy');   // profile still running
  assert.equal(shellStateOf(processes, undefined), 'unknown');
});

test('a tab that never arrived says so, naming the session', () => {
  const message = launchFailureMessage('Claude Workbench', 'wb-AI-c574d0');
  assert.match(message, /wb-AI-c574d0/);
  assert.ok(!/\p{Extended_Pictographic}/u.test(message));
});

test('terminalPlan relaunches when the live tab hangs on ANOTHER session', () => {
  // Part B's failure: starting a second session in a folder found the live
  // orchestrator tab of the FIRST one and merely revealed it — the newly named
  // session never started, and alice was back in the old conversation.
  const live = { createdByUs: true, exited: false, liveness: 'alive' as const };
  assert.equal(terminalPlan({ ...live, attachedTo: 'wb-AI-c574d0' }, 'wb-AI-c574d0'), 'show');
  assert.equal(terminalPlan({ ...live, attachedTo: 'wb-AI-c574d0' }, 'wb-AI-c574d0-9f2a1c'), 'launch');
  // unknown target (a restored tab) never counts as the right one
  assert.equal(terminalPlan({ ...live, attachedTo: undefined }, 'wb-AI-c574d0'), 'launch');
  // without a wanted session the old behaviour stands unchanged
  assert.equal(terminalPlan(live), 'show');
});

// ── Teil B: eine weitere Session landet in einem eigenen Fenster ─────────────

test('a further session of the open folder gets its own window', () => {
  const base = {
    currentFolder: '/Users/alice/AI',
    dir: '/Users/alice/AI',
    windowSessionKey: undefined,
    windowHasLiveSession: true,
  };
  // same session: stay here and just show it
  assert.equal(openPlan({ ...base, targetSessionKey: undefined }), 'same-window');
  // a DIFFERENT session while one runs here: own window, never a takeover
  assert.equal(openPlan({ ...base, targetSessionKey: '9f2a1c' }), 'new-window');
  // nothing running here: no reason for a second window
  assert.equal(
    openPlan({ ...base, targetSessionKey: '9f2a1c', windowHasLiveSession: false }),
    'same-window',
  );
});

test('another folder still reloads this window, as before', () => {
  assert.equal(
    openPlan({
      currentFolder: '/Users/alice/AI',
      dir: '/Users/alice/AI/a project',
      windowSessionKey: undefined,
      targetSessionKey: undefined,
      windowHasLiveSession: true,
    }),
    'reload-window',
  );
  // a window without any folder open
  assert.equal(
    openPlan({
      currentFolder: undefined,
      dir: '/Users/alice/AI',
      targetSessionKey: undefined,
      windowHasLiveSession: false,
    }),
    'reload-window',
  );
});

test('the restored orchestrator tab ATTACHES — it can never start a second Claude', () => {
  const command = orchestratorAttachCommand('wb-foo-1a2b3c');
  assert.equal(command, `exec tmux attach-session -t '=wb-foo-1a2b3c'`);
  assert.ok(!command.includes('wb-code'), 'wb-code could decide to start Claude');
  assert.ok(!command.includes('claude'), 'nothing here may launch an agent');
});
