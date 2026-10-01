import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { appendUriReceipt, formatReceiptLine, uriReceiptLogPath } from '../src/uriReceiptLog.ts';

function logFile(): string {
  return join(mkdtempSync(join(tmpdir(), 'wb-uri-receipt-')), 'wb-window-uri.log');
}

test('formatReceiptLine is three tab-separated fields: timestamp, action, folder', () => {
  const now = new Date('2026-08-04T09:36:12.345Z');
  assert.equal(
    formatReceiptLine('reload', '/Users/alice/AI/claude-workbench', now),
    '2026-08-04T09:36:12.345Z\treload\t/Users/alice/AI/claude-workbench\n',
  );
});

test('formatReceiptLine is written for the unknown action too', () => {
  // a silently dropped unrecognised path is exactly the mismatch the receipt
  // exists to surface — it must not be the one action that stays invisible
  const now = new Date('2026-08-04T09:36:12.345Z');
  assert.equal(formatReceiptLine('unknown', '/tmp/x', now), '2026-08-04T09:36:12.345Z\tunknown\t/tmp/x\n');
});

test('formatReceiptLine never omits the folder column when no folder is open', () => {
  const now = new Date('2026-08-04T09:36:12.345Z');
  assert.equal(
    formatReceiptLine('worker-tab', undefined, now),
    '2026-08-04T09:36:12.345Z\tworker-tab\t\n',
    'empty string, not a dropped field — a downstream cut -f3 must still find three columns',
  );
});

test('uriReceiptLogPath points at ~/.local/state/wb-window-uri.log', () => {
  assert.ok(uriReceiptLogPath().endsWith('/.local/state/wb-window-uri.log'), uriReceiptLogPath());
});

test('appendUriReceipt appends, does not overwrite, and creates the directory', () => {
  const file = logFile();
  appendUriReceipt('worker-tab', '/a', file);
  appendUriReceipt('reload', '/b', file);
  const lines = readFileSync(file, 'utf8').trim().split('\n');
  assert.equal(lines.length, 2);
  assert.match(lines[0], /\tworker-tab\t\/a$/);
  assert.match(lines[1], /\treload\t\/b$/);
});

test('a receipt that cannot be written never throws', () => {
  // /dev/null/... can never be a directory — mkdir and append both fail.
  // Synchronous since 2026-08-04, so this asserts a throw, not a rejection.
  assert.doesNotThrow(() => appendUriReceipt('reload', '/x', '/dev/null/nope/wb-window-uri.log'));
});
