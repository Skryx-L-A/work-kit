// Command lines for terminal workers and terminal orchestrators. Pure module.
import { shellQuote } from './format.ts';
import { expandHome } from './runs.ts';
import {
  allPlaceholdersEmpty,
  fillArgs,
  fillPlaceholders,
  type Harness,
  type Model,
  type PlaceholderValues,
  type Registry,
} from './registry.ts';

export interface LaunchOptions {
  name: string;
  cwd: string;
  prompt: string;
  effort?: string;
  autonomy: boolean;
  runDir?: string;
  taskFile?: string;
  resultFile?: string;
}

export interface TerminalLaunch {
  /** Shell command line typed into the terminal. */
  commandLine: string;
  env: Record<string, string>;
  /** True when the harness takes no prompt argument: type `prompt` after it started. */
  sendPromptAfterStart: boolean;
}

export function effortValue(harness: Harness, effort: string | undefined): string {
  if (!effort) {
    return '';
  }
  return harness.effortMap ? (harness.effortMap[effort] ?? '') : effort;
}

export function terminalLaunch(registry: Registry, harness: Harness, model: Model, opts: LaunchOptions): TerminalLaunch {
  if (harness.runner !== 'terminal' || !harness.command) {
    throw new Error(`Harness ${harness.id} does not run in a terminal`);
  }
  const values: PlaceholderValues = {
    model: model.modelRef,
    effort: effortValue(harness, opts.effort),
    workdir: opts.cwd,
    name: opts.name,
    prompt: opts.prompt,
    runDir: opts.runDir,
    taskFile: opts.taskFile,
    resultFile: opts.resultFile,
  };
  const args = [
    ...fillArgs(harness.args ?? [], values, registry),
    ...(values.effort && harness.effortArgs ? fillArgs(harness.effortArgs, values, registry) : []),
    ...(opts.autonomy && harness.autonomyArgs ? harness.autonomyArgs : []),
    ...(harness.promptArgs ? fillArgs(harness.promptArgs, values, registry) : []),
  ];
  const env: Record<string, string> = {};
  for (const [key, template] of Object.entries(harness.env ?? {})) {
    if (allPlaceholdersEmpty(template, values)) {
      continue;
    }
    env[key] = fillPlaceholders(template, values, registry);
  }
  const command = expandHome(harness.command);
  return {
    commandLine: [shellQuote(command), ...args.map(shellQuote)].join(' '),
    env,
    sendPromptAfterStart: !harness.promptArgs,
  };
}

/** The one-line prompt a terminal worker starts with; the details live in the task file. */
export function workerPrompt(taskFile: string, resultFile: string): string {
  return `Read the task file ${taskFile} and complete it. Follow its protocol: write your result to ${resultFile}, last line exactly DONE.`;
}

export function orchestratorPrompt(guideFile: string): string {
  return `You are the orchestrator of this workspace. Read ${guideFile} for how to delegate work to workers with the kit-wb command, then ask me for the goal.`;
}
