// Extension host test: starts VS Code with this extension in development mode, a temporary
// profile (user data + extensions dir), a temporary workspace and state dir, and a fake
// OpenAI-compatible server on an ephemeral 127.0.0.1 port. Nothing of the user's VS Code setup
// is read or changed.
//
// macOS: VS Code is launched with `open -g -n` so the test window never takes focus.
// Linux/other: @vscode/test-electron (VSCODE_EXECUTABLE selects an installed VS Code).
import { execFile, spawn } from 'node:child_process';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const EXT = fileURLToPath(new URL('../..', import.meta.url));
const FAKE_LM = fileURLToPath(new URL('./fake-lm', import.meta.url));
const TESTS = fileURLToPath(new URL('./index.cjs', import.meta.url));
const TIMEOUT_MS = Number(process.env.KITWB_HOST_TIMEOUT_MS ?? 240_000);
const MAC_APP = process.env.VSCODE_APP ?? '/Applications/Visual Studio Code.app';

const root = await mkdtemp(join(tmpdir(), 'kitwb-host-'));
const dirs = {
  userData: join(root, 'user-data'),
  extensions: join(root, 'extensions'),
  workspace: join(root, 'workspace'),
  state: join(root, 'state'),
  config: join(root, 'config'),
  skills: join(root, 'skills'),
  bin: join(root, 'bin'),
  templates: join(root, 'templates'),
};
for (const d of Object.values(dirs)) {
  await mkdir(d, { recursive: true });
}

// Fake OpenAI-compatible server. Model "scripted": write a file, then finish. Model "slow":
// answers after 30 s, so the stop test has something to stop.
function toolCall(id, name, args) {
  return { id, type: 'function', function: { name, arguments: JSON.stringify(args) } };
}
const server = createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const send = (status, body) => {
      if (!res.writableEnded) {
        res.writeHead(status, { 'content-type': 'application/json' });
        res.end(JSON.stringify(body));
      }
    };
    if (req.method === 'GET' && req.url === '/v1/models') {
      return send(200, { data: [{ id: 'scripted' }] });
    }
    if (req.method !== 'POST' || req.url !== '/v1/chat/completions') {
      return send(404, { error: 'not found' });
    }
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const toolResults = body.messages.filter((m) => m.role === 'tool').length;
    if (body.model === 'slow') {
      const timer = setTimeout(() => send(200, { choices: [{ message: { role: 'assistant', content: 'late' } }] }), 30_000);
      res.on('close', () => clearTimeout(timer));
      return undefined;
    }
    if (body.model === 'orchestrate') {
      const spawnCall = toolCall('o1', 'spawn_worker', { name: 'via-orchestrator', task: 'Write out/hello.txt', model: 'fake-local:scripted', paths: ['out/'], done: 'file exists' });
      const orchestratorMessage = toolResults === 0
        ? { role: 'assistant', content: 'Delegating.', tool_calls: [spawnCall] }
        : { role: 'assistant', content: `Spawned: ${body.messages.at(-1).content}` };
      return send(200, { choices: [{ message: orchestratorMessage }] });
    }
    const message = toolResults === 0
      ? { role: 'assistant', content: null, tool_calls: [toolCall('c1', 'write_file', { path: 'out/hello.txt', content: 'from the fake server' })] }
      : toolResults === 1
        ? { role: 'assistant', content: null, tool_calls: [toolCall('c2', 'finish', { result: '## What\nwrote out/hello.txt\n\n## Verified\nread back\n\n## Open\nnone' })] }
        : { role: 'assistant', content: 'finished' };
    return send(200, { choices: [{ message }] });
  });
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const baseUrl = `http://127.0.0.1:${server.address().port}/v1`;

// Unreachable address for the built-in local providers, so discovery never touches a real server.
const OFF = 'http://127.0.0.1:9/v1';
const registryPath = join(dirs.config, 'models.json');
await writeFile(registryPath, JSON.stringify({
  version: 1,
  providers: [
    { id: 'fake-local', label: 'Fake local', kind: 'local', baseUrl, api: 'openai' },
    { id: 'ollama', label: 'Ollama (off)', kind: 'local', baseUrl: 'http://127.0.0.1:9', api: 'ollama' },
    { id: 'llamacpp', label: 'llama.cpp (off)', kind: 'local', baseUrl: OFF, api: 'openai' },
    { id: 'mlx', label: 'MLX (off)', kind: 'local', baseUrl: OFF, api: 'openai' },
  ],
  harnesses: [
    { id: 'missing-cli', label: 'Missing CLI', command: 'kitwb-no-such-cli' },
    { id: 'fake-cli', label: 'Fake CLI', command: 'bash', args: ['-c', 'printf "## What\\nterminal worker ran\\n\\nDONE\\n" > "$0"', '{resultFile}'], promptArgs: [] },
  ],
  models: [
    { id: 'fake-local:scripted', label: 'Scripted fake', harness: 'api', provider: 'fake-local', modelRef: 'scripted', roles: ['worker', 'orchestrator'] },
    { id: 'fake-local:orchestrate', label: 'Orchestrator fake', harness: 'api', provider: 'fake-local', modelRef: 'orchestrate', roles: ['orchestrator'] },
    { id: 'fake-local:slow', label: 'Slow fake', harness: 'api', provider: 'fake-local', modelRef: 'slow', roles: ['worker'] },
    { id: 'fake-cli-default', label: 'Fake CLI', harness: 'fake-cli', provider: 'fake-local', modelRef: '', roles: ['worker'] },
    { id: 'missing-cli-model', label: 'Missing CLI', harness: 'missing-cli', provider: 'fake-local', modelRef: '', roles: ['worker'] },
  ],
}, null, 2));
await mkdir(join(dirs.skills, 'test-skill'), { recursive: true });
await writeFile(join(dirs.skills, 'test-skill', 'SKILL.md'), '---\nname: test-skill\ndescription: A test skill.\n---\n# Test\n');
await writeFile(join(dirs.templates, 'host-template.md'),
  '---\nname: host-template\ndescription: Host test template\nmodel: fake-local:scripted\npaths: out/\ndone: {{file}} exists\nskill: test-skill\n---\nWrite {{file}}.\n');
const rulesFile = join(dirs.config, 'AGENTS.md');
await writeFile(rulesFile, '# Rules\n\nBe precise.\n');
const brain = join(dirs.bin, 'brain');
await writeFile(brain, '#!/bin/sh\necho "no notes for: $*"\n');
await chmod(brain, 0o755);

await mkdir(join(dirs.userData, 'User'), { recursive: true });
await writeFile(join(dirs.userData, 'User', 'settings.json'), JSON.stringify({
  'kitWorkbench.stateDir': dirs.state,
  'kitWorkbench.registryPath': registryPath,
  'kitWorkbench.skillsDir': dirs.skills,
  'kitWorkbench.templatesDir': dirs.templates,
  'kitWorkbench.rulesFile': rulesFile,
  'kitWorkbench.brainCommand': brain,
  // The modal cloud confirmation cannot be answered in a test host; its decision rule
  // (dataStaysLocal) is unit-tested, the dialog itself is not.
  'kitWorkbench.confirmCloudModels': false,
  'security.workspace.trust.enabled': false,
  'extensions.autoUpdate': false,
  'extensions.autoCheckUpdates': false,
  'update.mode': 'none',
  'telemetry.telemetryLevel': 'off',
  'workbench.startupEditor': 'none',
  'window.restoreWindows': 'none',
}, null, 2));
await writeFile(join(dirs.workspace, '.kitwb-host-config.json'), JSON.stringify({
  stateDir: dirs.state,
  kitWb: join(EXT, 'resources', 'bin', 'kit-wb'),
}));

const args = [
  `--user-data-dir=${dirs.userData}`,
  `--extensions-dir=${dirs.extensions}`,
  `--extensionDevelopmentPath=${EXT}`,
  `--extensionDevelopmentPath=${FAKE_LM}`,
  `--extensionTestsPath=${TESTS}`,
  '--skip-welcome',
  '--skip-release-notes',
  '--disable-workspace-trust',
  '--new-window',
  dirs.workspace,
];

function run(cmd, cmdArgs) {
  return new Promise((resolve) => execFile(cmd, cmdArgs, (error, stdout) => resolve(error ? '' : stdout.trim())));
}

async function frontApp() {
  return run('osascript', ['-e', 'tell application "System Events" to get name of first application process whose frontmost is true']);
}

async function frontBundle() {
  return run('osascript', ['-e', 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true']);
}

let exitInfo = '';
const started = Date.now();
if (process.platform === 'darwin') {
  const before = await frontApp();
  const beforeBundle = await frontBundle();
  const child = spawn('open', ['-g', '-n', '-W', '-a', MAC_APP, '--args', ...args], { stdio: 'inherit' });
  // `open -g` starts the app in the background, but the Electron window still activates itself
  // when it appears (seen 2026-09-25: "Code" was frontmost 4 s into the run). Hand the focus
  // back to the app that had it, during the first seconds only; afterwards the user decides.
  let handedBack = 0;
  const guardUntil = Date.now() + 15_000;
  const focusGuard = setInterval(async () => {
    if (Date.now() > guardUntil) {
      clearInterval(focusGuard);
      return;
    }
    const now = await frontBundle();
    if (beforeBundle && now && now !== beforeBundle && /^com\.microsoft\.VSCode/.test(now)) {
      handedBack++;
      await run('osascript', ['-e', `tell application id "${beforeBundle.replace(/"/g, '')}" to activate`]);
    }
  }, 300);
  const timer = setTimeout(() => {
    exitInfo = 'timeout';
    // Only processes started with this run's temporary profile.
    execFile('pkill', ['-f', dirs.userData]);
  }, TIMEOUT_MS);
  let during = '';
  const probe = setTimeout(async () => {
    during = await frontApp();
  }, 4_000);
  await new Promise((resolve) => child.on('exit', resolve));
  clearTimeout(timer);
  clearTimeout(probe);
  clearInterval(focusGuard);
  console.log(`front app before: ${before || 'unknown'}, 4 s into the run: ${during || 'not sampled'}, focus handed back ${handedBack} times`);
} else {
  const { runTests } = await import('@vscode/test-electron');
  try {
    await runTests({
      extensionDevelopmentPath: [EXT, FAKE_LM],
      extensionTestsPath: TESTS,
      vscodeExecutablePath: process.env.VSCODE_EXECUTABLE || undefined,
      launchArgs: args.filter((a) => !a.startsWith('--extension')),
    });
  } catch (error) {
    exitInfo = String(error);
  }
}
server.close();
// Leftover helper processes of the temporary profile (none expected).
execFile('pkill', ['-f', dirs.userData]);

let checks = [];
try {
  checks = JSON.parse(await readFile(join(dirs.workspace, '.kitwb-host-result.json'), 'utf8'));
} catch {
  // No result file: the host did not run the tests.
}
for (const c of checks) {
  console.log(`${c.ok ? 'ok  ' : 'FAIL'} ${c.name}${c.ok ? '' : `\n     ${c.error.split('\n').slice(0, 4).join('\n     ')}`}`);
}
const failed = checks.filter((c) => !c.ok).length;
console.log(`host checks: ${checks.length - failed} passed, ${failed} failed, ${Math.round((Date.now() - started) / 1000)} s${exitInfo ? ` (${exitInfo})` : ''}`);
if (process.env.KITWB_HOST_KEEP) {
  console.log(`kept: ${root}`);
} else {
  await rm(root, { recursive: true, force: true });
}
process.exit(checks.length > 0 && failed === 0 && !exitInfo ? 0 : 1);
