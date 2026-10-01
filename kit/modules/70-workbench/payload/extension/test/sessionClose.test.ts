import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import {
  clearOrphanMarkers,
  markerBelongsToWindow,
  ORPHAN_GRACE_SECONDS,
  orphanDir,
  orphanMarkerPath,
  orphanWatchCommand,
  parseMarker,
  shouldArmOrphanWatch,
  writeOrphanMarker,
} from '../src/sessionClose.ts';

function home(): string {
  return mkdtempSync(join(tmpdir(), 'wb-orphan-'));
}

test('closing a window arms the watch, reloading it disarms the watch again', () => {
  // The measured difference (isolated VS Code 1.131, 2026-08-04): after a reload
  // a new extension host activates 547-592 ms later and clears the marker; after
  // a close nothing ever comes back and the marker stays. Both halves are tested
  // here on the same directory, in that order.
  const h = home();
  const marker = {
    session: 'wb-a project-1a2b3c',
    folder: '/Users/alice/AI/a project',
    sessionKey: undefined,
    token: 'p1-1000',
    at: 1_000_000,
  };

  // window goes away: deactivate() writes the marker
  writeOrphanMarker(marker, h);
  assert.equal(
    readdirSync(orphanDir(h)).length,
    1,
    'nach dem Schliessen muss genau eine Marke liegen',
  );

  // …a RELOAD comes back on the same folder and takes it away again
  const cleared = clearOrphanMarkers('/Users/alice/AI/a project', undefined, h);
  assert.deepEqual(cleared, ['wb-a project-1a2b3c']);
  assert.equal(readdirSync(orphanDir(h)).length, 0, 'ein Reload muss die Marke abraeumen');

  // …a CLOSE leaves it: nothing activates afterwards, so nothing clears it
  writeOrphanMarker(marker, h);
  assert.equal(readdirSync(orphanDir(h)).length, 1);
  const stored = parseMarker(readFileSync(orphanMarkerPath(marker.session, h), 'utf8'));
  assert.equal(stored?.session, 'wb-a project-1a2b3c');
  assert.equal(stored?.at, 1_000_000);
});

test('a window only clears the marker of ITS OWN session', () => {
  // Two windows can show the same folder under different session keys. Clearing
  // a foreign marker would leave that window's session running for good.
  const h = home();
  writeOrphanMarker(
    { session: 'wb-AI-aaaaaa', folder: '/Users/alice/AI', sessionKey: undefined, token: 't1', at: 1 },
    h,
  );
  writeOrphanMarker(
    { session: 'wb-AI-aaaaaa-9f2a1c', folder: '/Users/alice/AI', sessionKey: '9f2a1c', token: 't2', at: 2 },
    h,
  );

  assert.deepEqual(clearOrphanMarkers('/Users/alice/AI', '9f2a1c', h), ['wb-AI-aaaaaa-9f2a1c']);
  assert.deepEqual(readdirSync(orphanDir(h)), ['wb-AI-aaaaaa.json']);
  // a different folder never matches
  assert.deepEqual(clearOrphanMarkers('/Users/alice/AI/a project', undefined, h), []);
  assert.deepEqual(readdirSync(orphanDir(h)), ['wb-AI-aaaaaa.json']);
});

test('markerBelongsToWindow treats the default session and a keyed one as different', () => {
  const marker = { session: 's', folder: '/dir', sessionKey: undefined, token: 't', at: 0 };
  assert.equal(markerBelongsToWindow(marker, '/dir', undefined), true);
  assert.equal(markerBelongsToWindow(marker, '/dir', '9f2a1c'), false);
  assert.equal(markerBelongsToWindow({ ...marker, sessionKey: '9f2a1c' }, '/dir', '9f2a1c'), true);
  assert.equal(markerBelongsToWindow({ ...marker, sessionKey: '9f2a1c' }, '/dir', undefined), false);
});

test('a remote window, a disabled setting and a session-less window never arm', () => {
  // The host2 tmux server is on the other machine — a watcher started here would
  // ask this machine about a session it does not have.
  assert.equal(shouldArmOrphanWatch({ enabled: true, session: 'wb-AI-aaaaaa', remote: false }), true);
  assert.equal(shouldArmOrphanWatch({ enabled: true, session: 'wb-AI-aaaaaa', remote: true }), false);
  assert.equal(shouldArmOrphanWatch({ enabled: false, session: 'wb-AI-aaaaaa', remote: false }), false);
  assert.equal(shouldArmOrphanWatch({ enabled: true, session: undefined, remote: false }), false);
  assert.equal(shouldArmOrphanWatch({ enabled: true, session: '', remote: false }), false);
});

test('the watcher is called by name, with the grace period the measurement justifies', () => {
  // 90 s against measured reload gaps of 547-592 ms: closing too early would
  // cost a running conversation, closing too late only costs memory for a while.
  assert.ok(ORPHAN_GRACE_SECONDS >= 30, 'Karenzzeit muss deutlich ueber der Reload-Luecke liegen');
  assert.deepEqual(
    orphanWatchCommand('wb-AI-aaaaaa', 'p1-1000'),
    ['wb-session-orphan', '--session', 'wb-AI-aaaaaa', '--token', 'p1-1000', '--grace', String(ORPHAN_GRACE_SECONDS)],
  );
  assert.deepEqual(
    orphanWatchCommand('wb-AI-aaaaaa', 'p1-1000', 5),
    ['wb-session-orphan', '--session', 'wb-AI-aaaaaa', '--token', 'p1-1000', '--grace', '5'],
  );
});

test('an unreadable or foreign file in the marker directory is ignored, not fatal', () => {
  const h = home();
  mkdirSync(orphanDir(h), { recursive: true });
  writeFileSync(join(orphanDir(h), 'kaputt.json'), '{ not json', 'utf8');
  writeFileSync(join(orphanDir(h), 'notiz.txt'), 'kein Marker', 'utf8');
  writeOrphanMarker(
    { session: 'wb-AI-aaaaaa', folder: '/Users/alice/AI', sessionKey: undefined, token: 't', at: 1 },
    h,
  );
  assert.deepEqual(clearOrphanMarkers('/Users/alice/AI', undefined, h), ['wb-AI-aaaaaa']);
  // the two files that were never markers stay untouched
  assert.deepEqual(readdirSync(orphanDir(h)).sort(), ['kaputt.json', 'notiz.txt']);
});

test('clearing markers in a home without a marker directory is a no-op', () => {
  assert.deepEqual(clearOrphanMarkers('/Users/alice/AI', undefined, home()), []);
});

test('parseMarker rejects anything that is not a marker', () => {
  assert.equal(parseMarker('nope'), undefined);
  assert.equal(parseMarker('{}'), undefined);
  assert.equal(parseMarker('{"session":"s"}'), undefined);
  assert.deepEqual(parseMarker('{"session":"s","folder":"/d"}'), {
    session: 's', folder: '/d', sessionKey: undefined, token: '', at: 0,
  });
});
