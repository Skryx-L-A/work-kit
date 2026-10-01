// Kit status: which optional modules the workbench can use right now. Pure module; every check
// is injected, so the rules are unit-tested and the extension supplies the real probes.
export type StatusLevel = 'ok' | 'off' | 'warn' | 'missing';

export interface StatusItem {
  id: 'brain' | 'skills' | 'rules' | 'dataGuard' | 'models' | 'kitWb' | 'autonomy';
  label: string;
  level: StatusLevel;
  detail: string;
  /** Extra lines for the tooltip (e.g. the first lines of `brain status`). */
  more?: string[];
  /** Command id that helps with this item. */
  action?: string;
}

export interface StatusFacts {
  brainBinary?: string;
  brainEnabled: boolean;
  /** Output of `brain status`, or an error text; undefined when not run. */
  brainStatus?: string;
  skillsDir: string;
  skillCount: number;
  rulesSource?: string;
  rulesIsProject: boolean;
  dataGuardBinary?: string;
  /** Output of `data-guard status`, or undefined when not run. */
  dataGuardStatus?: string;
  dataClassesFile?: string;
  confirmCloud: boolean;
  registryFile: string;
  registryExists: boolean;
  modelCounts: { ready: number; total: number; lm: number };
  kitWbOnPath?: string;
  workerAutonomy: boolean;
}

function firstLines(text: string | undefined, n = 6): string[] {
  return (text ?? '').split(/\r?\n/).map((l) => l.trimEnd()).filter((l) => l.trim()).slice(0, n);
}

export function statusItems(f: StatusFacts): StatusItem[] {
  const items: StatusItem[] = [];

  if (!f.brainBinary) {
    items.push({ id: 'brain', label: 'Brain', level: 'missing', detail: 'not installed (module 20-brain); workers continue without it' });
  } else if (!f.brainEnabled) {
    items.push({ id: 'brain', label: 'Brain', level: 'off', detail: 'switched off for this workspace (kitWorkbench.brainSearch)', more: [f.brainBinary] });
  } else {
    const failed = f.brainStatus !== undefined && /failed|error|not found/i.test(f.brainStatus.split('\n')[0] ?? '');
    items.push({
      id: 'brain', label: 'Brain', level: failed ? 'warn' : 'ok',
      detail: failed ? 'installed, but brain status reports a problem' : 'search on',
      more: [f.brainBinary, ...firstLines(f.brainStatus)],
      action: 'kitWorkbench.brainSearch',
    });
  }

  items.push(f.skillCount > 0
    ? { id: 'skills', label: 'Skills', level: 'ok', detail: `${f.skillCount} installed`, more: [f.skillsDir] }
    : { id: 'skills', label: 'Skills', level: 'missing', detail: `none in ${f.skillsDir} (module 30-agent-setup)` });

  items.push(f.rulesSource
    ? { id: 'rules', label: 'Work rules', level: 'ok', detail: f.rulesIsProject ? 'project AGENTS.md' : 'kit AGENTS.md', more: [f.rulesSource] }
    : { id: 'rules', label: 'Work rules', level: 'warn', detail: 'no AGENTS.md found; API agents get a short built-in rule set' });

  const guardLines = firstLines(f.dataGuardStatus);
  const cloud = f.confirmCloud ? 'cloud confirmation on' : 'cloud confirmation OFF';
  if (!f.dataGuardBinary) {
    items.push({
      id: 'dataGuard', label: 'Data guard', level: f.confirmCloud ? 'missing' : 'warn',
      detail: `not installed (module 40-data-guard); ${cloud}`,
      more: f.dataClassesFile ? [`data classes: ${f.dataClassesFile}`] : undefined,
    });
  } else {
    const noGitleaks = guardLines.some((l) => /gitleaks:\s*NOT FOUND/i.test(l));
    items.push({
      id: 'dataGuard', label: 'Data guard', level: !f.confirmCloud || noGitleaks ? 'warn' : 'ok',
      detail: `${noGitleaks ? 'installed, gitleaks missing' : 'installed'}; ${cloud}`,
      more: [f.dataGuardBinary, ...(f.dataClassesFile ? [`data classes: ${f.dataClassesFile}`] : []), ...guardLines],
    });
  }

  const m = f.modelCounts;
  items.push({
    id: 'models', label: 'Models',
    level: m.ready > 0 ? 'ok' : 'warn',
    detail: `${m.ready} of ${m.total} ready${m.lm > 0 ? `, ${m.lm} from VS Code` : ''}`,
    more: [f.registryExists ? f.registryFile : `${f.registryFile} (not created yet: built-ins only)`],
    action: 'kitWorkbench.listModels',
  });

  items.push(f.kitWbOnPath
    ? { id: 'kitWb', label: 'kit-wb', level: 'ok', detail: 'on PATH', more: [f.kitWbOnPath] }
    : { id: 'kitWb', label: 'kit-wb', level: 'off', detail: 'not on PATH (terminal orchestrators started here still get it)' });

  items.push(f.workerAutonomy
    ? { id: 'autonomy', label: 'Worker autonomy', level: 'warn', detail: 'ON: terminal workers skip permission prompts' }
    : { id: 'autonomy', label: 'Worker autonomy', level: 'ok', detail: 'off: a human approves tool use in the terminal' });

  return items;
}

/** One-line summary for the overview header and the status bar tooltip. */
export function statusSummary(items: readonly StatusItem[]): string {
  return items.map((i) => `${i.label}: ${i.detail}`).join(' · ');
}
