import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after } from 'node:test';

/** A fresh temporary directory, removed when the test file ends. */
export async function tempDir(prefix = 'kitwb-'): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), prefix));
  after(() => rm(dir, { recursive: true, force: true }));
  return dir;
}
