// Result files: sections and end marker, for the worker overview and the result view. Pure module.
import { DONE_MARKER } from './runs.ts';

export interface ParsedResult {
  /** `## Heading` sections in file order; text before the first heading goes under "". */
  sections: { heading: string; text: string }[];
  /** 'done' (last line DONE), 'failed' (last line FAILED: ...), or 'open' (neither yet). */
  outcome: 'done' | 'failed' | 'open';
  /** Text after "FAILED:" when the result failed. */
  failure?: string;
}

export function parseResult(text: string): ParsedResult {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  while (lines.length > 0 && lines[lines.length - 1].trim() === '') {
    lines.pop();
  }
  const last = lines[lines.length - 1]?.trim() ?? '';
  let outcome: ParsedResult['outcome'] = 'open';
  let failure: string | undefined;
  if (last === DONE_MARKER) {
    outcome = 'done';
    lines.pop();
  } else if (/^FAILED\b:?/.test(last)) {
    outcome = 'failed';
    failure = last.replace(/^FAILED\b:?\s*/, '');
    lines.pop();
  }
  const sections: ParsedResult['sections'] = [];
  let current = { heading: '', text: [] as string[] };
  const flush = () => {
    const body = current.text.join('\n').trim();
    if (current.heading || body) {
      sections.push({ heading: current.heading, text: body });
    }
  };
  for (const line of lines) {
    const h = /^##\s+(.+?)\s*$/.exec(line);
    if (h) {
      flush();
      current = { heading: h[1], text: [] };
    } else {
      current.text.push(line);
    }
  }
  flush();
  return { sections, outcome, failure };
}

/** The section whose heading matches one of `names` (case-insensitive), if any. */
export function section(result: ParsedResult, ...names: string[]): string | undefined {
  const wanted = names.map((n) => n.toLowerCase());
  return result.sections.find((s) => wanted.includes(s.heading.toLowerCase()))?.text;
}

/**
 * The original task text inside a rendered task.md (between the title and "## Working
 * directory"), so a run can be started again with another model.
 */
export function taskBody(taskMd: string): string {
  const text = taskMd.replace(/\r\n/g, '\n');
  const start = text.startsWith('# Task:') ? text.indexOf('\n') + 1 : 0;
  const end = text.indexOf('\n## Working directory');
  return text.slice(start, end > start ? end : undefined).trim();
}
