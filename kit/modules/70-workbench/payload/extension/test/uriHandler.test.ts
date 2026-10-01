import assert from 'node:assert/strict';
import { test } from 'node:test';
import { resolveUriAction } from '../src/uriHandler.ts';

test('resolveUriAction recognises the two fixed paths', () => {
  assert.equal(resolveUriAction('/worker-tab'), 'worker-tab');
  assert.equal(resolveUriAction('/reload'), 'reload');
});

test('resolveUriAction rejects anything not on the fixed list', () => {
  // the attack this guards against: a path that LOOKS like a command channel
  assert.equal(resolveUriAction('/run'), 'unknown');
  assert.equal(resolveUriAction('/openWorkerTab'), 'unknown', 'the command id itself is not a valid path');
  assert.equal(resolveUriAction('/worker-tab/extra'), 'unknown', 'no sub-paths are accepted');
});

test('resolveUriAction ignores a query string instead of reading it', () => {
  // '?cmd=…' is exactly the shape that would turn this into a remote control
  // if it were ever inspected — it must have zero effect either way
  assert.equal(resolveUriAction('/worker-tab?cmd=rm -rf /'), 'worker-tab');
  assert.equal(resolveUriAction('/run?cmd=rm -rf /'), 'unknown');
});

test('resolveUriAction on an empty path', () => {
  assert.equal(resolveUriAction(''), 'unknown');
  assert.equal(resolveUriAction('/'), 'unknown');
});

test('resolveUriAction is case-sensitive: no casing is normalised into a match', () => {
  // matching is exact on purpose (see uriHandler.ts) — a differently-cased
  // path is treated exactly like any other unrecognised one, never coerced
  assert.equal(resolveUriAction('/Worker-Tab'), 'unknown');
  assert.equal(resolveUriAction('/RELOAD'), 'unknown');
});
