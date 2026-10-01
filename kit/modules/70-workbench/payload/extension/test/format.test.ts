import assert from 'node:assert/strict';
import { test } from 'node:test';
import { escapeHtml, previewText, relativeTime, shellQuote } from '../src/format.ts';

const now = new Date('2026-07-11T16:00:00Z');
const ago = (seconds: number) => new Date(now.getTime() - seconds * 1000).toISOString();

test('relativeTime speaks English (kit)', () => {
  assert.equal(relativeTime(ago(30), now), 'just now');
  assert.equal(relativeTime(ago(60), now), '1 min ago');
  assert.equal(relativeTime(ago(45 * 60), now), '45 min ago');
  assert.equal(relativeTime(ago(2 * 3600), now), '2 h ago');
  assert.equal(relativeTime(ago(26 * 3600), now), 'yesterday');
  assert.equal(relativeTime(ago(3 * 86400), now), '3 days ago');
  assert.equal(relativeTime(ago(14 * 86400), now), '2 weeks ago');
  assert.equal(relativeTime(ago(60 * 86400), now), '2 months ago');
});

test('relativeTime handles missing and broken timestamps', () => {
  assert.equal(relativeTime(undefined, now), 'unknown');
  assert.equal(relativeTime('kaputt', now), 'unknown');
});

test('previewText collapses whitespace and truncates', () => {
  assert.equal(previewText('  a \n  b  '), 'a b');
  assert.equal(previewText('abcdefghij', 5), 'abcd…');
});

test('escapeHtml neutralises markup', () => {
  assert.equal(escapeHtml('<b>&"</b>'), '&lt;b&gt;&amp;&quot;&lt;/b&gt;');
});

test('shellQuote survives quotes in paths', () => {
  assert.equal(shellQuote('/Users/alice/AI/foo'), `'/Users/alice/AI/foo'`);
  assert.equal(shellQuote(`/tmp/it's`), `'/tmp/it'\\''s'`);
});
