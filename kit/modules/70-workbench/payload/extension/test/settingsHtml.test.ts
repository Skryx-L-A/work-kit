// Die Einstellungs-Seite der Erweiterung ist seit dem 11.08. eine DUENNE Seite,
// die auf das Programm zeigt und es oeffnet (siehe den Kopf von
// settingsHtml.ts). Damit sind die einunddreissig Zusagen dieser Datei
// hinfaellig geworden -- sie pruefen samt und sonders Bedienelemente, die es
// hier nicht mehr geben SOLL: Modell-Auswahlen, Effort-Deckel, Guard-Schwellen,
// die Registry-Tabelle, die mcp-shared-Knoepfe, die Hook-Liste.
//
// Was an ihre Stelle tritt, prueft die Eigenschaften, auf die es jetzt ankommt:
// dass die Seite nichts mehr schreibt, dass sie den Weg zum Programm anbietet,
// und dass die beiden Auflagen dieses Hauses stehen -- keine Emojis, und
// Skripte nur mit der Nonce. Die Zusagen zu den INHALTEN, die frueher hier
// standen, sind nicht verlorengegangen: sie gelten jetzt dem Menue der App und
// werden von shell/tests/test-app-einstellungen.sh gegen das laufende Programm
// gemessen statt gegen eine Zeichenkette.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DEFAULT_SETTINGS, type Settings } from '../src/settings.ts';
import { renderSettingsHtml } from '../src/settingsHtml.ts';

function render(settings: Partial<Settings> = {}, sprache?: string): string {
  return renderSettingsHtml(
    { ...DEFAULT_SETTINGS, ...settings },
    'vscode-resource:/codicon.css',
    'vscode-resource:',
    'N0NCE',
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    sprache,
  );
}

test('renderSettingsHtml zeigt auf das Programm und bietet den Weg dorthin an', () => {
  const html = render();
  assert.match(html, /Agent Workbench\.app/);
  assert.match(html, /id="oeffnen"/);
  assert.match(html, /command: 'open-app'/);
});

test('renderSettingsHtml stellt selbst nichts mehr ein', () => {
  const html = render();
  // Kein Bedienelement, das einen Wert traegt: keine Auswahl, kein Eingabefeld,
  // kein Haken. Ein einzelner Knopf bleibt, und der oeffnet nur.
  assert.ok(!/<select/.test(html), 'keine Auswahl mehr auf dieser Seite');
  assert.ok(!/<input/.test(html), 'kein Eingabefeld mehr auf dieser Seite');
  // Und kein Schreibweg: die Seite schickt kein 'set' mehr.
  assert.ok(!/command: 'set'/.test(html), 'die Seite schreibt keine Einstellung mehr');
});

test('renderSettingsHtml nennt die sieben Seiten, die es jetzt gibt (Englisch als Vorgabe)', () => {
  const html = render();
  for (const seite of ['Session', 'Permissions', 'Programs and models', 'Machines',
    'Oversight and notifications', 'Appearance', 'Program']) {
    assert.match(html, new RegExp(`<b>${seite}</b>`), `die Seite „${seite}" fehlt im Wegweiser`);
  }
});

test('renderSettingsHtml zeigt Deutsch, wenn die Einstellungsdatei "de" traegt', () => {
  const html = render(undefined, 'de');
  assert.match(html, /<html lang="de">/);
  for (const seite of ['Sitzung', 'Erlaubnisse', 'Programme und Modelle', 'Maschinen',
    'Aufsicht und Meldungen', 'Aussehen', 'Programm']) {
    assert.match(html, new RegExp(`<b>${seite}</b>`), `die Seite „${seite}" fehlt im deutschen Wegweiser`);
  }
});

test('renderSettingsHtml nennt die Datei, um die es geht', () => {
  const html = render();
  assert.match(html, /settings\.json/);
  assert.match(html, /wb-state settings set/);
});

test('renderSettingsHtml hat keine Emojis und bindet Skripte an die Nonce', () => {
  const html = render();
  assert.ok(!/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u.test(html), 'no emoji in the UI');
  assert.match(html, /<script nonce="N0NCE">/);
  assert.match(html, /script-src 'nonce-N0NCE'/);
});

test('renderSettingsHtml maskiert den gespeicherten Harness-Namen', () => {
  const html = render({ orchestratorHarness: '<img src=x onerror=alert(1)>' });
  assert.ok(!html.includes('<img src=x'), 'der Wert darf nicht als Markup landen');
  assert.match(html, /&lt;img src=x/);
});
