import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  isMachine,
  HOST2_REMOTE_AUTHORITY,
  host2RemoteUri,
  MACHINE_LABEL,
  MACHINES,
  otherMachine,
} from '../src/machine.ts';

test('isMachine accepts only the two machines', () => {
  assert.equal(isMachine('mac'), true);
  assert.equal(isMachine('host2'), true);
  assert.equal(isMachine('windows'), false);
  assert.equal(isMachine(undefined), false);
});

test('MACHINES and labels stay in sync, German, no emoji', () => {
  assert.deepEqual([...MACHINES], ['mac']); // Kit: one machine
  for (const machine of MACHINES) {
    assert.ok(MACHINE_LABEL[machine].length > 0);
  }
  const joined = Object.values(MACHINE_LABEL).join(' ');
  assert.ok(!/\p{Extended_Pictographic}/u.test(joined), 'emoji in a machine label');
});

test('otherMachine toggles', () => {
  assert.equal(otherMachine('mac'), 'host2');
  assert.equal(otherMachine('host2'), 'mac');
});

test('host2RemoteUri builds the vscode-remote parts for the absolute host2 path', () => {
  assert.deepEqual(host2RemoteUri('/home/alice/AI/Demo'), {
    scheme: 'vscode-remote',
    authority: HOST2_REMOTE_AUTHORITY,
    path: '/home/alice/AI/Demo',
  });
  assert.equal(HOST2_REMOTE_AUTHORITY, 'ssh-remote+host2');
});
