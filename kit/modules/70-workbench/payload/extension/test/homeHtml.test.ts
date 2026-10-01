import assert from 'node:assert/strict';
import { test } from 'node:test';
import { renderHtml, type SessionCard, TEXTE_EN } from '../src/homeHtml.ts';

const card: SessionCard = {
  dir: '/Users/alice/AI/foo',
  name: 'foo',
  folderName: 'foo',
  tmuxSession: 'wb-foo-1a2b3c',
  lastActive: new Date(Date.now() - 2 * 3600 * 1000).toISOString(),
  sessionId: 'abc-123',
  lastUserMessage: 'Baue Teil A',
  workers: [
    { name: 'builder', model: 'fable:medium', status: 'running', paneId: '%3' },
    { name: 'reviewer', status: 'done' },
  ],
  tmuxAlive: true,
};

test('renderHtml shows project, path, message, workers and the resume button', () => {
  const html = renderHtml([card], 'vscode-resource:/codicon.css', 'vscode-resource:', 'N0NCE');
  assert.match(html, /Sessions fortsetzen/);
  assert.match(html, /foo/);
  assert.match(html, /\/Users\/alice\/AI\/foo/);
  assert.match(html, /Baue Teil A/);
  assert.match(html, /2 h ago/);
  assert.match(html, /builder — running/);
  assert.match(html, /reviewer — done/);
  assert.match(html, /data-dir="\/Users\/alice\/AI\/foo" data-session="abc-123"/);
  assert.match(html, /Fortsetzen/);
});

test('renderHtml tells two sessions of the same folder apart (SPEC-V2 D)', () => {
  const second: SessionCard = {
    ...card,
    name: 'Refactor-Session',
    sessionKey: '9f2a1c',
    tmuxSession: 'wb-foo-1a2b3c-9f2a1c',
    sessionId: 'def-456',
  };
  const html = renderHtml([card, second], 'c.css', 'vscode-resource:', 'N0NCE');
  // Die Zusage ist unveraendert: zwei Sitzungen desselben Ordners muessen
  // auseinanderzuhalten sein. GEAENDERT hat sich am 03.09. nur, WO das steht.
  // Der Ordner wird nicht mehr je Karte wiederholt -- er ist die Ueberschrift
  // des Kastens, in dem beide Sitzungen liegen --, und die tmux-Kennung steht
  // im Schildchen der Zeile statt in ihrem sichtbaren Text: sie ist eine
  // Kennung fuer das Programm, kein Satz fuer einen Menschen.
  assert.match(html, /<span class="project">Refactor-Session<\/span>/);
  assert.match(html, /<span class="folder-name">foo<\/span>/);
  assert.match(html, /title="wb-foo-1a2b3c —/);
  assert.match(html, /title="wb-foo-1a2b3c-9f2a1c —/);
  // resume carries the key, so the right session of the folder is started
  assert.match(html, /data-session="def-456"\s+data-key="9f2a1c" data-name="Refactor-Session"/);
  assert.match(html, /data-session="abc-123"\s+data-key="" data-name="foo"/);
});

test('renderHtml shows harness and model when the state file has them (SPEC-V2 F)', () => {
  const pi: SessionCard = { ...card, harness: 'pi', model: 'lmalpha' };
  // Auch hier ist die Zusage dieselbe -- Harness und Modell werden gezeigt --
  // und nur der Ort ein anderer: sie stehen seit dem 03.09. in derselben
  // Fusszeile wie der Zustand statt in einer eigenen Zeile darueber. Das spart
  // je Sitzung eine Zeile, und in einem Kasten mit drei Sitzungen sind das drei.
  assert.match(
    renderHtml([pi], 'c.css', 'vscode-resource:', 'N0NCE'),
    /<span class="tmux" title="[^"]*">pi \(lokal\) · lmalpha · /,
  );
  // old state files carry neither field — the line names only the state
  const ohne = renderHtml([card], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.ok(!ohne.includes('pi (lokal)'));
  assert.match(ohne, /<span class="tmux" title="[^"]*">(läuft|beendet)</);
});

test('renderHtml marks a remote worker with its machine on the badge', () => {
  const remote: SessionCard = {
    ...card,
    workers: [
      { name: 'SSH-builder', model: 'sonnet5:high', status: 'running', paneId: '%3', machine: 'host2' },
      { name: 'reviewer', status: 'running', paneId: '%4' },
    ],
  };
  const html = renderHtml([remote], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.match(html, /SSH-builder — running · host2/);
  assert.match(html, /reviewer — running</, 'a local worker keeps the V1 badge');
});

test('renderHtml says "Zuordnung unsicher" instead of guessing quietly', () => {
  const shaky: SessionCard = { ...card, transcriptUncertain: true };
  const html = renderHtml([shaky], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.match(html, /Zuordnung unsicher/);
  assert.match(html, /class="uncertain"/);
  // the normal case stays clean (the style block always carries the class name)
  assert.ok(!renderHtml([card], 'c.css', 'vscode-resource:', 'N0NCE').includes('class="uncertain"'));
});

test('renderHtml offers the Einstellungen entry point', () => {
  const html = renderHtml([], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.match(html, /id="settings"/);
  assert.match(html, /Einstellungen/);
});

test('renderHtml escapes user content', () => {
  const evil: SessionCard = { ...card, lastUserMessage: '<img src=x onerror=alert(1)>', workers: [] };
  const html = renderHtml([evil], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.ok(!html.includes('<img src=x'), 'raw markup leaked into the webview');
  assert.match(html, /&lt;img src=x/);
});

test('renderHtml has an empty state and no emoji', () => {
  const html = renderHtml([], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.match(html, /Noch keine Sessions/);
  assert.ok(!/\p{Extended_Pictographic}/u.test(html), 'emoji found in the Startseite');
});

test('renderHtml locks scripts to the nonce (no unsafe-inline)', () => {
  const html = renderHtml([], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.match(html, /script-src 'nonce-N0NCE'/);
  assert.match(html, /<script nonce="N0NCE">/);
  assert.ok(!/script-src[^;]*unsafe-inline/.test(html), 'inline scripts still allowed');
});

test('renderHtml renders the Mac|Host2 switch with the active machine marked', () => {
  const html = renderHtml([], 'c.css', 'vscode-resource:', 'N0NCE',
    { machine: 'host2', reachable: true, loading: false });
  // Kit: one machine; the switch offers this machine only.
  assert.match(html, /data-machine="mac"/);
  assert.ok(!html.includes('data-machine="host2"'));
  assert.match(html, /Sessions fortsetzen — second machine/);
});

test('renderHtml shows a loading notice while Host2 state is fetched', () => {
  const html = renderHtml([], 'c.css', 'vscode-resource:', 'N0NCE',
    { machine: 'host2', reachable: true, loading: true });
  assert.match(html, /Sessions werden geladen/);
});

test('renderHtml shows an unreachable notice for Host2, escaping the error', () => {
  const html = renderHtml([], 'c.css', 'vscode-resource:', 'N0NCE',
    { machine: 'host2', reachable: false, loading: false, error: '<timeout>' });
  assert.match(html, /ließen sich nicht laden/);
  assert.match(html, /&lt;timeout&gt;/);
  assert.ok(!html.includes('<timeout>'), 'raw error leaked into the webview');
});

test('kit: the English start page names the app and no second machine', () => {
  const html = renderHtml([card], 'c.css', 'vscode-resource:', 'N0NCE', undefined, false, TEXTE_EN);
  assert.match(html, /<title>Agent Workbench<\/title>/);
  assert.match(html, /<h1>Agent Workbench<\/h1>/);
  assert.match(html, /New session/);
  assert.ok(!html.includes('class="machine'), 'machine switch shown');
  assert.ok(!/Claude Workbench|Linux-PC|\bMac\b|Einstellungen|Sessions fortsetzen/.test(html));
});

// ── Teil B/C: Sessions eines Ordners getrennt, und eine loeschbar ────────────

const zweite: SessionCard = {
  ...card,
  name: 'foo2',
  sessionKey: '9f2a1c',
  tmuxSession: 'wb-foo-1a2b3c-9f2a1c',
  lastUserMessage: 'Baue Teil B',
  workers: [],
  tmuxAlive: false,
};
const andererOrdner: SessionCard = {
  ...card,
  dir: '/Users/alice/AI/bar',
  name: 'bar',
  folderName: 'bar',
  tmuxSession: 'wb-bar-445566',
  workers: [],
};

test('the sessions of one folder are shown together, under that folder', () => {
  const html = renderHtml([card, zweite, andererOrdner], 'c.css', 'vscode-resource:', 'N0NCE');
  const groups = html.match(/<section class="folder-group">/g) ?? [];
  assert.equal(groups.length, 2, 'one group per folder');
  assert.match(html, /2 Sessions/);
  assert.match(html, /1 Session</);
  // both sessions of the folder are on the page and told apart by name
  assert.match(html, /foo2/);
  assert.match(html, /wb-foo-1a2b3c-9f2a1c/);
});

test('every folder can start a further session without picking the folder again', () => {
  const html = renderHtml([card, andererOrdner], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.match(html, /data-newdir="\/Users\/alice\/AI\/foo"/);
  assert.match(html, /data-newdir="\/Users\/alice\/AI\/bar"/);
  assert.match(html, /Weitere Session/);
  assert.match(html, /command: 'newInFolder'/);
});

test('every session card carries its own delete button, keyed to that session', () => {
  const html = renderHtml([card, zweite], 'c.css', 'vscode-resource:', 'N0NCE');
  // the default session has no key, the second one carries its own
  assert.match(html, /data-deletedir="\/Users\/alice\/AI\/foo" data-deletekey=""/);
  assert.match(html, /data-deletedir="\/Users\/alice\/AI\/foo" data-deletekey="9f2a1c"/);
  assert.match(html, /command: 'delete'/);
  // and it says what it does NOT touch
  assert.match(html, /Projektdateien und Kbase bleiben unberührt/);
});

test('the start page carries no emoji', () => {
  const html = renderHtml([card, zweite, andererOrdner], 'c.css', 'vscode-resource:', 'N0NCE');
  assert.ok(!/\p{Extended_Pictographic}/u.test(html));
});
