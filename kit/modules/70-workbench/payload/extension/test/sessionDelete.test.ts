import assert from 'node:assert/strict';
import { test } from 'node:test';
import { confirmMessage, DELETE_LABEL, deleteCommand } from '../src/sessionDelete.ts';

test('deleteCommand names dir and key, and only deletes when confirmed', () => {
  // Without --yes wb-session-delete reports and changes nothing — that is what
  // makes an unconfirmed call harmless.
  assert.equal(
    deleteCommand('/Users/alice/AI/foo'),
    `wb-session-delete --dir '/Users/alice/AI/foo'`,
  );
  assert.equal(
    deleteCommand('/Users/alice/AI/foo', '9f2a1c', true),
    `wb-session-delete --dir '/Users/alice/AI/foo' --key '9f2a1c' --yes`,
  );
  // the folder's default session has no key
  assert.equal(
    deleteCommand('/Users/alice/AI/foo', undefined, true),
    `wb-session-delete --dir '/Users/alice/AI/foo' --yes`,
  );
});

test('deleteCommand quotes a path that would otherwise break out of the argument', () => {
  assert.equal(
    deleteCommand(`/tmp/it's; rm -rf ~`, undefined, true),
    `wb-session-delete --dir '/tmp/it'\\''s; rm -rf ~' --yes`,
  );
});

test('the confirmation names the boundary, not just the deletion', () => {
  // alice's one question about this feature was where it stops. A dialog that
  // only asks "delete?" does not answer it.
  const message = confirmMessage('Dictation2', '/Users/alice/AI/a project');
  assert.match(message, /Dictation2/);
  assert.match(message, /transcript/);
  assert.match(message, /Not touched/);
  assert.match(message, /notes/);
  assert.match(message, /\/Users\/alice\/AI\/a project/);
  assert.match(message, /trash-snapshots/);
  assert.ok(!/\p{Extended_Pictographic}/u.test(message + DELETE_LABEL));
});
